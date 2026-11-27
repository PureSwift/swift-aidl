import Testing
import AIDLCore

@Test func resolvesBuiltinsImportsAndNestedTypes() throws {
    var parser = try AIDLParser(source: """
        package demo;
        import other.Thing;
        parcelable Outer {
            parcelable Inner { int number; }
            List<Inner> nested;
            Thing external;
            Outer.Inner qualified;
        }
        """)
    var importedParser = try AIDLParser(source: "package other; parcelable Thing;")
    let file = try parser.parse()
    let imported = try importedParser.parse()
    let resolver = try AIDLTypeResolver(graph: AIDLSourceGraph(files: [file, imported]))
    try resolver.validateTypes(in: AIDLSourceGraph(files: [file, imported]))
    guard case let .parcelable(outer) = try #require(file.declarations.first) else {
        Issue.record("Expected parcelable")
        return
    }
    let nested = try resolver.resolve(outer.fields[0].type, in: file, scope: ["Outer"])
    #expect(nested.target == .builtin("List"))
    #expect(nested.typeArguments[0].target == .declaration("demo.Outer.Inner"))
    #expect(try resolver.resolve(outer.fields[1].type, in: file, scope: ["Outer"]).target == .declaration("other.Thing"))
    #expect(try resolver.resolve(outer.fields[2].type, in: file, scope: ["Outer"]).target == .declaration("demo.Outer.Inner"))
}

@Test func rejectsUnresolvedAndDuplicateTypes() throws {
    var parser = try AIDLParser(source: "parcelable Foo { Missing value; }")
    let file = try parser.parse()
    let resolver = try AIDLTypeResolver(graph: AIDLSourceGraph(files: [file]))
    guard case let .parcelable(foo) = try #require(file.declarations.first) else { return }
    #expect(throws: AIDLTypeResolutionError.self) { try resolver.resolve(foo.fields[0].type, in: file) }
    #expect(throws: AIDLTypeResolutionError.self) { try resolver.validateTypes(in: AIDLSourceGraph(files: [file])) }
    #expect(throws: AIDLTypeResolutionError.self) { try AIDLTypeResolver(graph: AIDLSourceGraph(files: [file, file])) }
}

@Test func validatesMethodAndNestedDeclarationTypes() throws {
    var parser = try AIDLParser(source: """
        interface Service {
            parcelable Nested { Missing value; }
            void call(in Nested value);
        }
        """)
    let graph = AIDLSourceGraph(files: [try parser.parse()])
    let resolver = try AIDLTypeResolver(graph: graph)
    #expect(throws: AIDLTypeResolutionError.self) { try resolver.validateTypes(in: graph) }
}
