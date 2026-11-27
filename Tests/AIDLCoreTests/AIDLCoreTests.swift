import AIDLCore
import Foundation
import Testing

@Test(arguments: [
    "interface Example { int first(int value) = 7; void second(); }",
    "interface Example { void first() = 7; void second() = 7; }",
    "interface Example { void first() = 16777115; }",
    "interface Example { int[] first(); }",
    "interface Example { void first(out int value); }",
    "oneway interface Example { int first(); }",
])
func rejectsUnsupportedSwiftGeneration(_ source: String) throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aidl")
    try source.write(to: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path) }
    #expect(throws: AIDLSwiftGenerationError.self) {
        try AIDLCompiler().compile(sourcePath: path.path)
    }
}
