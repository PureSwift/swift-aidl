public struct AIDLConstantEvaluationError: Error, Sendable, CustomStringConvertible {
    public let message: String
    public let location: AIDLSourceLocation?

    public var description: String {
        guard let location else { return message }
        return "\(location.file):\(location.line):\(location.column): \(message)"
    }
}

/// Evaluates integer constant expressions using checked 64-bit arithmetic.
public struct AIDLConstantEvaluator: Sendable {
    public init() {}

    public func evaluate(_ tokens: [AIDLToken], constants: [String: Int64] = [:]) throws -> Int64 {
        var parser = ExpressionParser(tokens: tokens, constants: constants)
        let value = try parser.parse(minimumPrecedence: 0)
        guard parser.index == tokens.count else { throw parser.error("unexpected token") }
        return value
    }
}

private struct ExpressionParser {
    let tokens: [AIDLToken]
    let constants: [String: Int64]
    var index = 0

    func error(_ message: String) -> AIDLConstantEvaluationError {
        AIDLConstantEvaluationError(message: message, location: index < tokens.count ? tokens[index].location : tokens.last?.location)
    }

    mutating func parse(minimumPrecedence: Int) throws -> Int64 {
        var lhs = try unary()
        while index < tokens.count, let precedence = precedence(tokens[index].text), precedence >= minimumPrecedence {
            let op = tokens[index].text
            index += 1
            let rhs = try parse(minimumPrecedence: precedence + 1)
            switch op {
            case "+": let r = lhs.addingReportingOverflow(rhs); guard !r.overflow else { throw error("integer overflow") }; lhs = r.partialValue
            case "-": let r = lhs.subtractingReportingOverflow(rhs); guard !r.overflow else { throw error("integer overflow") }; lhs = r.partialValue
            case "*": let r = lhs.multipliedReportingOverflow(by: rhs); guard !r.overflow else { throw error("integer overflow") }; lhs = r.partialValue
            case "/": guard rhs != 0, !(lhs == .min && rhs == -1) else { throw error("invalid division") }; lhs /= rhs
            case "|": lhs |= rhs
            case "&": lhs &= rhs
            case "^": lhs ^= rhs
            case "<<", ">>":
                guard rhs >= 0, rhs < 64 else { throw error("invalid shift count") }
                if op == "<<" { lhs = lhs &<< rhs } else { lhs = lhs >> rhs }
            default: throw error("unsupported operator")
            }
        }
        return lhs
    }

    mutating func unary() throws -> Int64 {
        guard index < tokens.count else { throw error("expected expression") }
        let token = tokens[index]
        index += 1
        switch token.text {
        case "+": return try unary()
        case "-":
            let value = try unary()
            let result = Int64.zero.subtractingReportingOverflow(value)
            guard !result.overflow else { throw error("integer overflow") }
            return result.partialValue
        case "~": return try ~unary()
        case "(":
            let value = try parse(minimumPrecedence: 0)
            guard index < tokens.count, tokens[index].text == ")" else { throw error("expected ')'") }
            index += 1
            return value
        default:
            if token.kind == .integerLiteral {
                var text = token.text
                if text.hasSuffix("l") || text.hasSuffix("L") { text.removeLast() }
                let radix: Int
                if text.hasPrefix("0x") || text.hasPrefix("0X") { radix = 16; text.removeFirst(2) }
                else if text.hasPrefix("0b") || text.hasPrefix("0B") { radix = 2; text.removeFirst(2) }
                else { radix = 10 }
                guard let value = Int64(text, radix: radix) else { throw error("integer literal out of range") }
                return value
            }
            if let value = constants[token.text] { return value }
            throw AIDLConstantEvaluationError(message: "unknown integer constant '\(token.text)'", location: token.location)
        }
    }

    private func precedence(_ op: String) -> Int? {
        switch op {
        case "|": 0
        case "^": 1
        case "&": 2
        case "<<", ">>": 3
        case "+", "-": 4
        case "*", "/": 5
        default: nil
        }
    }
}
