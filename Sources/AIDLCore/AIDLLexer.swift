/// A location in an AIDL source file. Lines and columns are one-based.
public struct AIDLSourceLocation: Equatable, Sendable {
    public let file: String
    public let line: Int
    public let column: Int
}

public struct AIDLToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case identifier, keyword, integerLiteral, floatingPointLiteral
        case stringLiteral, characterLiteral, symbol, endOfFile
    }

    public let kind: Kind
    /// The original source spelling, including quotes for literals.
    public let text: String
    public let location: AIDLSourceLocation
}

public struct AIDLLexerError: Error, Equatable, Sendable, CustomStringConvertible {
    public let location: AIDLSourceLocation
    public let message: String

    public var description: String {
        "\(location.file):\(location.line):\(location.column): \(message)"
    }
}

/// Tokenizes AIDL source while preserving source spellings and locations.
public struct AIDLLexer {
    private static let keywords: Set<String> = [
        "package", "import", "interface", "parcelable", "enum", "union", "const",
        "oneway", "in", "out", "inout", "void", "boolean", "byte", "char", "int",
        "long", "float", "double", "String", "CharSequence", "IBinder", "FileDescriptor",
        "ParcelFileDescriptor", "List", "Map", "true", "false", "null"
    ]
    private let characters: [Character]
    private let file: String
    private var index = 0
    private var line = 1
    private var column = 1

    public init(source: String, file: String = "<input>") {
        self.characters = Array(source)
        self.file = file
    }

    public mutating func tokenize() throws -> [AIDLToken] {
        var tokens: [AIDLToken] = []
        while true {
            try skipTrivia()
            let start = location
            guard let character = peek() else {
                tokens.append(AIDLToken(kind: .endOfFile, text: "", location: start))
                return tokens
            }
            let beginning = index
            let kind: AIDLToken.Kind
            if isIdentifierStart(character) {
                advance()
                while let next = peek(), isIdentifierContinue(next) { advance() }
                kind = Self.keywords.contains(spelling(from: beginning)) ? .keyword : .identifier
            } else if isDigit(character) || (character == "." && peek(1).map(isDigit) == true) {
                kind = try consumeNumber(start: start)
            } else if character == "\"" || character == "'" {
                try consumeQuoted(character, start: start)
                kind = character == "\"" ? .stringLiteral : .characterLiteral
            } else if "{}()[]<>;,=.?:+-*/%|&^~@".contains(character) {
                advance()
                if (character == "<" || character == ">") && peek() == character { advance() }
                kind = .symbol
            } else {
                throw error("unexpected character '\(character)'", at: start)
            }
            tokens.append(AIDLToken(kind: kind, text: spelling(from: beginning), location: start))
        }
    }

    private var location: AIDLSourceLocation {
        AIDLSourceLocation(file: file, line: line, column: column)
    }

    private func peek(_ offset: Int = 0) -> Character? {
        index + offset < characters.count ? characters[index + offset] : nil
    }

    private mutating func advance() {
        guard let character = peek() else { return }
        index += 1
        if character == "\n" || character == "\r\n" || character == "\r" {
            line += 1
            column = 1
        } else {
            column += 1
        }
    }

    private func spelling(from start: Int) -> String { String(characters[start..<index]) }
    private func error(_ message: String, at location: AIDLSourceLocation) -> AIDLLexerError {
        AIDLLexerError(location: location, message: message)
    }
    private func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
    private func isIdentifierStart(_ c: Character) -> Bool {
        c == "_" || c == "$" || c.isLetter
    }
    private func isIdentifierContinue(_ c: Character) -> Bool { isIdentifierStart(c) || isDigit(c) }

    private mutating func skipTrivia() throws {
        while let c = peek() {
            if c.isWhitespace {
                advance()
            } else if c == "/" && peek(1) == "/" {
                advance(); advance()
                while let next = peek(), next != "\n" && next != "\r" && next != "\r\n" { advance() }
            } else if c == "/" && peek(1) == "*" {
                let start = location
                advance(); advance()
                while peek() != nil && !(peek() == "*" && peek(1) == "/") { advance() }
                guard peek() != nil else { throw error("unterminated block comment", at: start) }
                advance(); advance()
            } else {
                return
            }
        }
    }

    private mutating func consumeQuoted(_ quote: Character, start: AIDLSourceLocation) throws {
        advance()
        while let c = peek() {
            if c == quote { advance(); return }
            if c == "\n" || c == "\r" || c == "\r\n" { break }
            advance()
            if c == "\\" {
                guard let escaped = peek(), escaped != "\n", escaped != "\r", escaped != "\r\n" else { break }
                advance()
            }
        }
        throw error("unterminated literal", at: start)
    }

    private mutating func consumeNumber(start: AIDLSourceLocation) throws -> AIDLToken.Kind {
        if peek() == "0", let prefix = peek(1), "xXbB".contains(prefix) {
            advance(); advance()
            let digitsStart = index
            while let c = peek(), c == "_" || ("bB".contains(prefix) ? (c == "0" || c == "1") : (isDigit(c) || "abcdefABCDEF".contains(c))) { advance() }
            guard index > digitsStart else { throw error("expected digits after numeric prefix", at: start) }
            if "bB".contains(prefix), let c = peek(), isDigit(c) { throw error("invalid binary digit", at: location) }
            consumeIntegerSuffix()
            return .integerLiteral
        }
        var floating = false
        while let c = peek(), isDigit(c) || c == "_" { advance() }
        if peek() == "." {
            floating = true; advance()
            while let c = peek(), isDigit(c) { advance() }
        }
        if let c = peek(), "eE".contains(c) {
            floating = true; advance()
            if let sign = peek(), sign == "+" || sign == "-" { advance() }
            let digitsStart = index
            while let digit = peek(), isDigit(digit) { advance() }
            guard index > digitsStart else { throw error("expected exponent digits", at: start) }
        }
        if let suffix = peek(), "fFdD".contains(suffix) { floating = true; advance() }
        else if !floating { consumeIntegerSuffix() }
        return floating ? .floatingPointLiteral : .integerLiteral
    }

    private mutating func consumeIntegerSuffix() {
        for suffix in ["u32", "u64", "u8", "l", "L"] {
            if suffix.enumerated().allSatisfy({ peek($0.offset) == $0.element }) {
                for _ in suffix { advance() }
                return
            }
        }
    }
}
