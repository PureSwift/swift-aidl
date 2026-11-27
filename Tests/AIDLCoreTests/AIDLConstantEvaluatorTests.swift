import Foundation
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

@Test func evaluatesIntegerConstantsAndEnumMembersDuringAnalysis() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let package = directory.appendingPathComponent("demo")
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let dependency = package.appendingPathComponent("Masks.aidl")
    try """
        package demo;
        interface Masks { const int HIGH = 1 << 31; }
        """.write(to: dependency, atomically: true, encoding: .utf8)
    let root = package.appendingPathComponent("Root.aidl")
    try """
        package demo;
        import demo.Masks;
        interface Root {
            const int MASK = Masks.HIGH | LATER;
            const int LATER = 1_005 % 4;
            const long WIDE = 1L << 40;
            const int HEX = 0xffffffff;
            const byte BYTE_MASK = 0xffu8;
            @Backing(type="int")
            enum Mode { FIRST, SECOND, THIRD = SECOND + 2, FOURTH }
        }
        """.write(to: root, atomically: true, encoding: .utf8)

    let graph = try AIDLCompiler().analyze(sourcePath: root.path, includePaths: [directory.path])
    #expect(graph.integerConstants == [
        "demo.Masks.HIGH": -2_147_483_648,
        "demo.Root.MASK": -2_147_483_647,
        "demo.Root.LATER": 1,
        "demo.Root.WIDE": 1_099_511_627_776,
        "demo.Root.HEX": -1,
        "demo.Root.BYTE_MASK": -1,
        "demo.Root.Mode.FIRST": 0,
        "demo.Root.Mode.SECOND": 1,
        "demo.Root.Mode.THIRD": 3,
        "demo.Root.Mode.FOURTH": 4,
    ])
}

@Test(arguments: [
    "const int A = B; const int B = A;",
    "const byte A = 128;",
    "const long A = 2147483647 + 1;",
    "const long A = 1 << 32;",
    "enum Mode { LAST = 127, OVERFLOW }",
])
func rejectsInvalidIntegerConstantsDuringAnalysis(_ members: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appendingPathComponent("Root.aidl")
    try "interface Root { \(members) }".write(to: root, atomically: true, encoding: .utf8)
    #expect(throws: AIDLConstantEvaluationError.self) { try AIDLCompiler().analyze(sourcePath: root.path) }
}
