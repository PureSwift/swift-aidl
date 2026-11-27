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
        try evaluateInteger(tokens, aidlWidths: false) { name in
            constants[name].map { AIDLInteger(value: $0, width: 64) }
        }.value
    }

    func evaluateInteger(
        _ tokens: [AIDLToken],
        aidlWidths: Bool = true,
        resolve: (String) throws -> AIDLInteger?
    ) throws -> AIDLInteger {
        var parser = ExpressionParser(tokens: tokens, aidlWidths: aidlWidths)
        let value = try parser.parse(minimumPrecedence: 0, resolve: resolve)
        guard parser.index == tokens.count else { throw parser.error("unexpected token") }
        return value
    }
}

struct AIDLInteger {
    let value: Int64
    let width: Int

    static func fits(_ value: Int64, width: Int) -> Bool {
        switch width {
        case 8: Int8(exactly: value) != nil
        case 32: Int32(exactly: value) != nil
        default: true
        }
    }
}

private struct ExpressionParser {
    let tokens: [AIDLToken]
    let aidlWidths: Bool
    var index = 0

    func error(_ message: String, at token: AIDLToken? = nil) -> AIDLConstantEvaluationError {
        let location = token?.location ?? (index < tokens.count ? tokens[index].location : tokens.last?.location)
        return AIDLConstantEvaluationError(message: message, location: location)
    }

    mutating func parse(
        minimumPrecedence: Int,
        resolve: (String) throws -> AIDLInteger?
    ) throws -> AIDLInteger {
        var lhs = try unary(resolve: resolve)
        while index < tokens.count, let precedence = precedence(tokens[index].text), precedence >= minimumPrecedence {
            let operation = tokens[index]
            index += 1
            let rhs = try parse(minimumPrecedence: precedence + 1, resolve: resolve)
            lhs = try apply(operation, lhs, rhs)
        }
        return lhs
    }

    private func apply(_ operation: AIDLToken, _ lhs: AIDLInteger, _ rhs: AIDLInteger) throws -> AIDLInteger {
        let width = max(32, lhs.width, rhs.width)
        let left = lhs.value
        let right = rhs.value
        let result: Int64
        switch operation.text {
        case "+", "-", "*":
            let arithmetic: (partialValue: Int64, overflow: Bool)
            switch operation.text {
            case "+": arithmetic = left.addingReportingOverflow(right)
            case "-": arithmetic = left.subtractingReportingOverflow(right)
            default: arithmetic = left.multipliedReportingOverflow(by: right)
            }
            guard !arithmetic.overflow else { throw error("integer overflow", at: operation) }
            result = arithmetic.partialValue
        case "/", "%":
            let minimum = width == 32 ? Int64(Int32.min) : Int64.min
            guard right != 0, !(left == minimum && right == -1) else {
                throw error("invalid division or remainder", at: operation)
            }
            result = operation.text == "/" ? left / right : left % right
        case "|": result = left | right
        case "&": result = left & right
        case "^": result = left ^ right
        case "<<", ">>":
            let count = right.magnitude
            guard count < width, aidlWidths || right >= 0 else {
                throw error("invalid shift count", at: operation)
            }
            let shiftsLeft = (operation.text == "<<") == (right >= 0)
            if aidlWidths {
                guard left >= 0, !shiftsLeft || count <= left.leadingZeroBitCount - (64 - width) else {
                    throw error("invalid shift operand", at: operation)
                }
            }
            result = if shiftsLeft && width == 32 {
                Int64(Int32(truncatingIfNeeded: left) &<< count)
            } else if shiftsLeft {
                left &<< count
            } else {
                left >> count
            }
        default: throw error("unsupported operator", at: operation)
        }
        guard AIDLInteger.fits(result, width: width) else { throw error("integer overflow", at: operation) }
        return AIDLInteger(value: result, width: width)
    }

    mutating func unary(resolve: (String) throws -> AIDLInteger?) throws -> AIDLInteger {
        guard index < tokens.count else { throw error("expected expression") }
        let token = tokens[index]
        index += 1
        switch token.text {
        case "+": return try unary(resolve: resolve)
        case "-":
            if aidlWidths, index < tokens.count, tokens[index].kind == .integerLiteral,
               let negative = try? literal("-" + tokens[index].text, at: tokens[index]) {
                index += 1
                return negative
            }
            let operand = try unary(resolve: resolve)
            let result = Int64.zero.subtractingReportingOverflow(operand.value)
            guard !result.overflow, AIDLInteger.fits(result.partialValue, width: operand.width) else {
                throw error("integer overflow", at: token)
            }
            return AIDLInteger(value: result.partialValue, width: operand.width)
        case "~":
            let operand = try unary(resolve: resolve)
            return AIDLInteger(value: ~operand.value, width: operand.width)
        case "(":
            let value = try parse(minimumPrecedence: 0, resolve: resolve)
            guard index < tokens.count, tokens[index].text == ")" else { throw error("expected ')'") }
            index += 1
            return value
        default:
            if token.kind == .integerLiteral { return try literal(token.text, at: token) }
            guard token.kind == .identifier else { throw error("expected integer expression", at: token) }
            var name = token.text
            while index + 1 < tokens.count, tokens[index].text == ".", tokens[index + 1].kind == .identifier {
                name += "." + tokens[index + 1].text
                index += 2
            }
            guard let value = try resolve(name) else { throw error("unknown integer constant '\(name)'", at: token) }
            return value
        }
    }

    private func literal(_ spelling: String, at token: AIDLToken) throws -> AIDLInteger {
        var digits = spelling
        var suffix: String?
        for candidate in ["u32", "u64", "u8", "l", "L"] where digits.hasSuffix(candidate) {
            suffix = candidate
            digits.removeLast(candidate.count)
            break
        }
        let radix: Int
        if digits.hasPrefix("0x") || digits.hasPrefix("0X") { radix = 16; digits.removeFirst(2) }
        else if digits.hasPrefix("0b") || digits.hasPrefix("0B") { radix = 2; digits.removeFirst(2) }
        else { radix = 10 }
        let failure = error("integer literal out of range", at: token)
        guard !digits.hasPrefix("_"), !digits.hasSuffix("_"), !digits.contains("__") else { throw failure }
        digits.removeAll { $0 == "_" }

        if aidlWidths, radix != 10 || suffix?.hasPrefix("u") == true {
            guard let raw = UInt64(digits, radix: radix) else { throw failure }
            switch suffix {
            case "u8":
                guard let byte = UInt8(exactly: raw) else { throw failure }
                return AIDLInteger(value: Int64(Int8(bitPattern: byte)), width: 8)
            case "u32":
                guard let word = UInt32(exactly: raw) else { throw failure }
                return AIDLInteger(value: Int64(Int32(bitPattern: word)), width: 32)
            case "l", "L", "u64":
                return AIDLInteger(value: Int64(bitPattern: raw), width: 64)
            default:
                if let word = UInt32(exactly: raw) {
                    return AIDLInteger(value: Int64(Int32(bitPattern: word)), width: 32)
                }
                return AIDLInteger(value: Int64(bitPattern: raw), width: 64)
            }
        }

        guard let value = Int64(digits, radix: radix) else { throw failure }
        let width = if !aidlWidths || suffix != nil || Int32(exactly: value) == nil {
            64
        } else if Int8(exactly: value) == nil {
            32
        } else {
            8
        }
        return AIDLInteger(value: value, width: width)
    }

    private func precedence(_ op: String) -> Int? {
        switch op {
        case "|": 0
        case "^": 1
        case "&": 2
        case "<<", ">>": 3
        case "+", "-": 4
        case "*", "/", "%": 5
        default: nil
        }
    }
}
