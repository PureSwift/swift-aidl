/// Evaluates scalar byte, int and long constants and enum members in a source graph.
final class AIDLIntegerConstantAnalysis {
    private struct Definition {
        let file: AIDLFile
        let scope: [String]
        let width: Int
        let expression: [AIDLToken]?
        let predecessor: String?
    }

    private let resolver: AIDLTypeResolver
    private var definitions: [String: Definition] = [:]
    private var values: [String: AIDLInteger] = [:]
    private var evaluating: Set<String> = []

    init(resolver: AIDLTypeResolver) {
        self.resolver = resolver
    }

    func evaluate(in files: [AIDLFile]) throws -> [String: Int64] {
        for file in files {
            try collect(file.declarations, in: file, scope: [])
        }
        for name in definitions.keys.sorted() {
            _ = try evaluate(name)
        }
        return values.mapValues(\.value)
    }

    private func collect(_ declarations: [AIDLDeclaration], in file: AIDLFile, scope: [String]) throws {
        for declaration in declarations {
            let scope = scope + [declaration.name]
            let owner = (file.packageName + scope).joined(separator: ".")
            let constants: [AIDLConstant]
            switch declaration {
            case let .interface(value): constants = value.constants
            case let .parcelable(value): constants = value.constants
            case let .union(value): constants = value.constants
            case let .enumeration(value):
                let width = try backingWidth(value)
                var predecessor: String?
                for member in value.cases {
                    let name = owner + "." + member.name
                    try add(name, definition: Definition(
                        file: file, scope: scope, width: width, expression: member.value, predecessor: predecessor
                    ))
                    predecessor = name
                }
                continue
            }

            for constant in constants where constant.type.arrayDimensions == 0 {
                guard let width = width(of: constant.type.name) else { continue }
                try add(owner + "." + constant.name, definition: Definition(
                    file: file, scope: scope, width: width, expression: constant.value, predecessor: nil
                ))
            }
            try collect(declaration.nestedDeclarations, in: file, scope: scope)
        }
    }

    private func add(_ name: String, definition: Definition) throws {
        guard definitions[name] == nil else {
            throw failure("duplicate integer constant '\(name)'", for: definition)
        }
        definitions[name] = definition
    }

    private func evaluate(_ name: String) throws -> AIDLInteger? {
        if let value = values[name] { return value }
        guard let definition = definitions[name] else { return nil }
        guard evaluating.insert(name).inserted else {
            throw failure("cyclic integer constant reference to '\(name)'", for: definition)
        }
        defer { evaluating.remove(name) }

        let number: Int64
        if let expression = definition.expression {
            number = try AIDLConstantEvaluator().evaluateInteger(expression) { reference in
                try self.resolve(reference, from: definition)
            }.value
        } else if let predecessor = definition.predecessor, let previous = try evaluate(predecessor) {
            let next = previous.value.addingReportingOverflow(1)
            guard !next.overflow else { throw failure("enum value overflows for '\(name)'", for: definition) }
            number = next.partialValue
        } else {
            number = 0
        }

        guard AIDLInteger.fits(number, width: definition.width) else {
            throw failure("value \(number) for '\(name)' does not fit in \(definition.width) bits", for: definition)
        }
        let value = AIDLInteger(value: number, width: definition.width)
        values[name] = value
        return value
    }

    private func resolve(_ name: String, from definition: Definition) throws -> AIDLInteger? {
        if let separator = name.lastIndex(of: ".") {
            let owner = String(name[..<separator])
            let member = name[separator...]
            let qualified = try resolver.resolveName(owner, in: definition.file, scope: definition.scope)
            return try evaluate(qualified + member)
        }
        let package = definition.file.packageName
        let scope = definition.scope
        for depth in stride(from: scope.count, through: 1, by: -1) {
            let qualified = (package + scope.prefix(depth) + [name]).joined(separator: ".")
            if let value = try evaluate(qualified) { return value }
        }
        return nil
    }

    private func backingWidth(_ type: AIDLEnum) throws -> Int {
        guard let backing = type.annotations.first(where: { $0.name == "Backing" }) else { return 8 }
        let arguments = backing.arguments
        guard arguments.count == 3, arguments[0].text == "type", arguments[1].text == "=",
              arguments[2].kind == .stringLiteral,
              let width = width(of: String(arguments[2].text.dropFirst().dropLast())) else {
            throw AIDLConstantEvaluationError(
                message: "expected byte, int or long backing type for enum '\(type.name)'",
                location: arguments.first?.location
            )
        }
        return width
    }

    private func width(of type: String) -> Int? {
        switch type {
        case "byte": 8
        case "int": 32
        case "long": 64
        default: nil
        }
    }

    private func failure(_ message: String, for definition: Definition) -> AIDLConstantEvaluationError {
        AIDLConstantEvaluationError(message: message, location: definition.expression?.first?.location)
    }
}
