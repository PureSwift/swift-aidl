public struct AIDLParserError: Error, Sendable, CustomStringConvertible {
    public let location: AIDLSourceLocation
    public let message: String

    public var description: String {
        "\(location.file):\(location.line):\(location.column): \(message)"
    }
}

/// A recursive-descent parser for AIDL declarations.
public struct AIDLParser {
    private var tokens: [AIDLToken]
    private var index = 0
    private let sourcePath: String
    private var packageName: [String] = []

    public init(source: String, sourcePath: String = "<input>") throws {
        var lexer = AIDLLexer(source: source, file: sourcePath)
        tokens = try lexer.tokenize()
        self.sourcePath = sourcePath
    }

    public mutating func parse() throws -> AIDLFile {
        if consume("package") {
            packageName = try qualifiedName()
            try expect(";")
        }
        var imports: [[String]] = []
        while consume("import") {
            imports.append(try qualifiedName())
            try expect(";")
        }
        var declarations: [AIDLDeclaration] = []
        while current.kind != .endOfFile {
            declarations.append(try declaration())
        }
        return AIDLFile(sourcePath: sourcePath, packageName: packageName, imports: imports, declarations: declarations)
    }

    private var current: AIDLToken { tokens[index] }
    private func failure(_ message: String) -> AIDLParserError { AIDLParserError(location: current.location, message: message) }
    @discardableResult private mutating func consume(_ text: String) -> Bool {
        guard current.text == text && current.kind != .endOfFile else { return false }
        index += 1
        return true
    }
    private mutating func expect(_ text: String) throws {
        guard consume(text) else { throw failure("expected '\(text)', found '\(current.text)'") }
    }
    private mutating func identifier() throws -> String {
        guard current.kind == .identifier else { throw failure("expected identifier") }
        let value = current.text
        index += 1
        return value
    }
    private mutating func qualifiedName() throws -> [String] {
        var parts = [try identifier()]
        while consume(".") { parts.append(try identifier()) }
        return parts
    }

    private mutating func annotations() throws -> [AIDLAnnotation] {
        var result: [AIDLAnnotation] = []
        while consume("@") {
            let name = try identifier()
            var arguments: [AIDLToken] = []
            if consume("(") {
                var depth = 1
                while depth > 0 {
                    guard current.kind != .endOfFile else { throw failure("unterminated annotation") }
                    let token = current
                    index += 1
                    if token.text == "(" { depth += 1 }
                    if token.text == ")" { depth -= 1 }
                    if depth > 0 { arguments.append(token) }
                }
            }
            result.append(AIDLAnnotation(name: name, arguments: arguments))
        }
        return result
    }

    private mutating func type(leadingAnnotations: [AIDLAnnotation] = []) throws -> AIDLType {
        let allAnnotations = leadingAnnotations + (try annotations())
        guard current.kind == .identifier || current.kind == .keyword else { throw failure("expected type") }
        var name = current.text
        index += 1
        while consume(".") { name += "." + (try identifier()) }
        var arguments: [AIDLType] = []
        if consume("<") {
            repeat { arguments.append(try type()) } while consume(",")
            // The lexer recognizes >> as an operator; in a generic type it closes two levels.
            if current.text == ">>" {
                let token = current
                tokens[index] = AIDLToken(kind: .symbol, text: ">", location: token.location)
            } else {
                try expect(">")
            }
        }
        var dimensions = 0
        while consume("[") { try expect("]"); dimensions += 1 }
        return AIDLType(name: name, typeArguments: arguments, arrayDimensions: dimensions, annotations: allAnnotations)
    }

    private mutating func declaration() throws -> AIDLDeclaration {
        let attrs = try annotations()
        let oneway = consume("oneway")
        if consume("interface") {
            let name = try identifier()
            try expect("{")
            var methods: [AIDLMethod] = []
            var constants: [AIDLConstant] = []
            var nested: [AIDLDeclaration] = []
            while !consume("}") {
                guard current.kind != .endOfFile else { throw failure("unterminated interface") }
                if isDeclarationStart() { nested.append(try declaration()); continue }
                let memberAnnotations = try annotations()
                if consume("const") { constants.append(try constant(annotations: memberAnnotations)); continue }
                let methodOneway = consume("oneway")
                let returnType = try type()
                let methodName = try identifier()
                try expect("(")
                var parameters: [AIDLParameter] = []
                if !consume(")") {
                    repeat {
                        let parameterAnnotations = try annotations()
                        let direction: AIDLParameter.Direction
                        if consume("in") { direction = .in }
                        else if consume("out") { direction = .out }
                        else if consume("inout") { direction = .inoutDirection }
                        else { direction = .in }
                        let parameterType = try type(leadingAnnotations: parameterAnnotations)
                        parameters.append(AIDLParameter(name: try identifier(), direction: direction, type: parameterType))
                    } while consume(",")
                    try expect(")")
                }
                var explicit: UInt32?
                if consume("=") {
                    guard current.kind == .integerLiteral, let value = transactionID(current.text) else { throw failure("expected valid transaction ID") }
                    explicit = value
                    index += 1
                }
                try expect(";")
                guard let offset = explicit ?? UInt32(exactly: methods.count), offset < UInt32.max else { throw failure("transaction ID is too large") }
                methods.append(AIDLMethod(name: methodName, annotations: memberAnnotations, isOneway: methodOneway, returnType: returnType, parameters: parameters, explicitTransactionId: explicit, computedTransactionCode: offset + 1))
            }
            _ = consume(";")
            return .interface(AIDLInterface(name: name, descriptor: (packageName + [name]).joined(separator: "."), annotations: attrs, isOneway: oneway, methods: methods, constants: constants, nestedDeclarations: nested))
        }
        guard !oneway else { throw failure("oneway requires an interface or method") }
        if consume("parcelable") {
            let name = try identifier()
            if consume(";") { return .parcelable(AIDLParcelable(name: name, annotations: attrs, isOpaqueForwardDecl: true, fields: [], constants: [], nestedDeclarations: [])) }
            let members = try fieldsAndDeclarations()
            return .parcelable(AIDLParcelable(name: name, annotations: attrs, isOpaqueForwardDecl: false, fields: members.0, constants: members.1, nestedDeclarations: members.2))
        }
        if consume("union") {
            let name = try identifier()
            let members = try fieldsAndDeclarations()
            return .union(AIDLUnion(name: name, annotations: attrs, fields: members.0, constants: members.1, nestedDeclarations: members.2))
        }
        if consume("enum") {
            let name = try identifier()
            try expect("{")
            var cases: [AIDLEnum.Case] = []
            while !consume("}") {
                let caseName = try identifier()
                let value = consume("=") ? try expression(until: [",", "}"]) : nil
                cases.append(AIDLEnum.Case(name: caseName, value: value))
                if !consume(",") { try expect("}"); break }
            }
            _ = consume(";")
            return .enumeration(AIDLEnum(name: name, annotations: attrs, cases: cases))
        }
        throw failure("expected declaration")
    }

    private func isDeclarationStart() -> Bool {
        // Look past annotation payloads without consuming them.
        var cursor = index
        while tokens[cursor].text == "@" {
            cursor += 1
            guard cursor < tokens.count, tokens[cursor].kind == .identifier else { return false }
            cursor += 1
            if cursor < tokens.count, tokens[cursor].text == "(" {
                var depth = 0
                repeat {
                    guard cursor < tokens.count, tokens[cursor].kind != .endOfFile else { return false }
                    if tokens[cursor].text == "(" { depth += 1 }
                    if tokens[cursor].text == ")" { depth -= 1 }
                    cursor += 1
                } while depth > 0
            }
        }
        if tokens[cursor].text == "oneway" { cursor += 1 }
        return cursor < tokens.count && ["interface", "parcelable", "enum", "union"].contains(tokens[cursor].text)
    }

    private mutating func fieldsAndDeclarations() throws -> ([AIDLField], [AIDLConstant], [AIDLDeclaration]) {
        try expect("{")
        var fields: [AIDLField] = []
        var constants: [AIDLConstant] = []
        var nested: [AIDLDeclaration] = []
        while !consume("}") {
            guard current.kind != .endOfFile else { throw failure("unterminated declaration") }
            if isDeclarationStart() { nested.append(try declaration()); continue }
            let attrs = try annotations()
            if consume("const") { constants.append(try constant(annotations: attrs)); continue }
            let fieldType = try type(leadingAnnotations: attrs)
            let name = try identifier()
            let value = consume("=") ? try expression(until: [";"]) : nil
            try expect(";")
            fields.append(AIDLField(name: name, type: fieldType, defaultValue: value))
        }
        _ = consume(";")
        return (fields, constants, nested)
    }

    private mutating func constant(annotations: [AIDLAnnotation]) throws -> AIDLConstant {
        let constantType = try type(leadingAnnotations: annotations)
        let name = try identifier()
        try expect("=")
        let value = try expression(until: [";"])
        try expect(";")
        return AIDLConstant(name: name, type: constantType, value: value)
    }

    private mutating func expression(until delimiters: Set<String>) throws -> [AIDLToken] {
        var result: [AIDLToken] = []
        var stack: [String] = []
        while current.kind != .endOfFile {
            if stack.isEmpty && delimiters.contains(current.text) { break }
            if ["(", "[", "{"].contains(current.text) { stack.append(current.text) }
            if [")", "]", "}"].contains(current.text) {
                let pairs = [")": "(", "]": "[", "}": "{"]
                guard stack.last == pairs[current.text] else { throw failure("unmatched delimiter") }
                stack.removeLast()
            }
            result.append(current)
            index += 1
        }
        guard !result.isEmpty, stack.isEmpty else { throw failure("expected complete expression") }
        return result
    }

    private func transactionID(_ text: String) -> UInt32? {
        let value = text.hasSuffix("L") || text.hasSuffix("l") ? String(text.dropLast()) : text
        if value.hasPrefix("0x") || value.hasPrefix("0X") { return UInt32(value.dropFirst(2), radix: 16) }
        if value.hasPrefix("0b") || value.hasPrefix("0B") { return UInt32(value.dropFirst(2), radix: 2) }
        return UInt32(value)
    }
}
