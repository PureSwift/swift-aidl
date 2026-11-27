import AIDLCore
import Foundation
import Testing

@Test func selectedClientMethodsPreserveOriginalTransactionCodes() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aidl")
    try """
        package demo;
        interface Example {
            void unsupported(out int[] output);
            int supported();
            int unused();
        }
        """.write(to: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path) }
    let compiler = AIDLCompiler()
    let swift = try compiler.compile(sourcePath: path.path, clientMethods: ["supported"])
    #expect(swift.contains("public static let `supported`: UInt32 = 2"))
    #expect(!swift.contains("ExampleStub"))
    #expect(!swift.contains("unsupported"))
    #expect(!swift.contains("unused"))
    #expect(throws: AIDLSwiftGenerationError.self) {
        try compiler.compile(sourcePath: path.path, clientMethods: ["missing"])
    }
}

@Test(arguments: [
    "interface Example { int first(int value) = 7; void second(); }",
    "interface Example { void first() = 7; void second() = 7; }",
    "interface Example { void first() = 16777115; }",
    "interface Example { int[][] first(); }",
    "interface Example { void first(out int value); }",
    "oneway interface Example { void first(inout int[] values); }",
    "interface Example { void first(inout @nullable String[] values); }",
    "oneway interface Example { int first(); }",
    "interface Example { @nullable int first(); }",
    #"interface Example { @EnforcePermission("INTERNET") void first(); }"#,
    "interface Example { @utf8InCpp int first(); }",
    "interface Example { @nullable void first(); }",
    "parcelable Example { byte value = 128; }",
    "parcelable Example { @nullable Example child; }",
    "union Example { int zero; @nullable Example child; }",
])
func rejectsUnsupportedSwiftGeneration(_ source: String) throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aidl")
    try source.write(to: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path) }
    #expect(throws: AIDLSwiftGenerationError.self) {
        try AIDLCompiler().compile(sourcePath: path.path)
    }
}

@Test(arguments: [
    #"const String A = B; const String B = A;"#,
    #"const String A = "invalid\n";"#,
    #"const String A = "x" + 7;"#,
])
func rejectsInvalidStringConstants(_ members: String) throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aidl")
    try "interface Example { \(members) }".write(to: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path) }
    #expect(throws: AIDLConstantEvaluationError.self) {
        try AIDLCompiler().compile(sourcePath: path.path)
    }
}
