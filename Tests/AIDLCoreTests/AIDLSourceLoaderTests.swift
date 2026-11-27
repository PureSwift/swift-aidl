import Foundation
import Testing
import AIDLCore

@Test func loadsImportsWithOverlayPrecedenceAndCycles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let overlay = root.appendingPathComponent("overlay")
    let upstream = root.appendingPathComponent("upstream")
    func write(_ path: String, _ contents: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
    try write("Root.aidl", "package demo; import demo.Item; interface Root { List<Item> getItems(); }")
    try write("overlay/demo/Item.aidl", "package demo; import demo.Other; parcelable Item { int value; }")
    try write("upstream/demo/Item.aidl", "package demo; parcelable Item;")
    try write("upstream/demo/Other.aidl", "package demo; import demo.Item; parcelable Other;")
    let graph = try AIDLSourceLoader(includePaths: [overlay.path, upstream.path])
        .load(sourcePath: root.appendingPathComponent("Root.aidl").path)
    #expect(graph.files.count == 3)
    guard case let .parcelable(item) = graph.files[1].declarations[0] else {
        Issue.record("Expected parcelable")
        return
    }
    #expect(!item.isOpaqueForwardDecl)
    #expect(item.fields.first?.name == "value")
    let source = root.appendingPathComponent("Root.aidl").path
    let compiler = AIDLCompiler()
    let analyzed = try compiler.analyze(sourcePath: source, includePaths: [overlay.path, upstream.path], manualParcelables: [])
    #expect(analyzed.files.count == 3)
    #expect(analyzed.referencedOpaqueParcelables.isEmpty)

    do {
        _ = try compiler.analyze(sourcePath: source, includePaths: [upstream.path], manualParcelables: [])
        Issue.record("Expected a missing parcelable layout")
    } catch let error as AIDLParcelableLayoutError {
        #expect(error.missingTypes == ["demo.Item"])
    }
    let registered = try compiler.analyze(sourcePath: source, includePaths: [upstream.path], manualParcelables: ["demo.Item"])
    #expect(registered.referencedOpaqueParcelables == ["demo.Item"])
}

@Test func reportsMissingAndMismatchedImports() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("demo"), withIntermediateDirectories: true)
    let source = root.appendingPathComponent("Root.aidl")
    try "import demo.Item; interface Root {}".write(to: source, atomically: true, encoding: .utf8)
    let loader = AIDLSourceLoader(includePaths: [root.path])
    #expect(throws: AIDLSourceLoaderError.self) { try loader.load(sourcePath: source.path) }
    try "package demo; parcelable Wrong;".write(to: root.appendingPathComponent("demo/Item.aidl"), atomically: true, encoding: .utf8)
    #expect(throws: AIDLSourceLoaderError.self) { try loader.load(sourcePath: source.path) }
}
