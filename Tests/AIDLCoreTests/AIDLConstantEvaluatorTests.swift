import Testing
import AIDLCore

@Test func evaluatesIntegerExpressions() throws {
    var lexer = AIDLLexer(source: "(1 << 3) | (BASE + 0x2 * 3)")
    let tokens = try lexer.tokenize().dropLast()
    #expect(try AIDLConstantEvaluator().evaluate(Array(tokens), constants: ["BASE": 1]) == 15)
}

@Test(arguments: ["1 / 0", "1 << 64", "unknown", "1 +", "9223372036854775807 + 1"])
func rejectsInvalidConstantExpressions(_ source: String) throws {
    var lexer = AIDLLexer(source: source)
    let tokens = Array(try lexer.tokenize().dropLast())
    #expect(throws: AIDLConstantEvaluationError.self) { try AIDLConstantEvaluator().evaluate(tokens) }
}
