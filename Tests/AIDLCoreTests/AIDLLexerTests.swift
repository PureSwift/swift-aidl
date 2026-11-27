import Testing
import AIDLCore

@Test func tokenizesAIDLAndTracksLocations() throws {
    var lexer = AIDLLexer(source: """
        // header
        package android.os;
        /* comment */ @nullable String value = "a\\\"b";
        const int MASK = 0x10L << 0b10;
        """, file: "Example.aidl")
    let tokens = try lexer.tokenize()
    #expect(tokens.map(\.text) == ["package", "android", ".", "os", ";", "@", "nullable", "String", "value", "=", "\"a\\\"b\"", ";", "const", "int", "MASK", "=", "0x10L", "<<", "0b10", ";", ""])
    #expect(tokens[0].kind == .keyword)
    #expect(tokens[5].location.line == 3)
    #expect(tokens[5].location.column == 15)
    #expect(tokens[5].location.file == "Example.aidl")
    #expect(tokens.last?.kind == .endOfFile)
}

@Test func tokenizesNumbersAndCharacterLiterals() throws {
    var lexer = AIDLLexer(source: "1 1.5 .5 2e-3 3f 'x' '\\n'")
    let tokens = try lexer.tokenize()
    #expect(tokens.map(\.kind) == [.integerLiteral, .floatingPointLiteral, .floatingPointLiteral, .floatingPointLiteral, .floatingPointLiteral, .characterLiteral, .characterLiteral, .endOfFile])
}

@Test(arguments: ["/* unfinished", "\"unfinished", "0x", "0b102", "1e+"])
func rejectsMalformedInput(_ source: String) {
    var lexer = AIDLLexer(source: source)
    #expect(throws: AIDLLexerError.self) { try lexer.tokenize() }
}
