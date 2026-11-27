/// Errors produced by functionality that has not yet been implemented.
public enum AIDLCoreError: Error, Sendable {
    case notImplemented
}

/// Entry point for the AIDL compilation pipeline.
public struct AIDLCompiler: Sendable {
    public init() {}

    /// Loads and parses sources, then resolves their type references.
    /// This does not evaluate constants or validate wire compatibility.
    public func analyze(sourcePath: String, includePaths: [String] = []) throws -> AIDLSourceGraph {
        let graph = try AIDLSourceLoader(includePaths: includePaths).load(sourcePath: sourcePath)
        let resolver = try AIDLTypeResolver(graph: graph)
        try resolver.validateTypes(in: graph)
        return graph
    }

    /// Compiles an AIDL source file using the given ordered include paths.
    public func compile(sourcePath: String, includePaths: [String] = []) throws {
        throw AIDLCoreError.notImplemented
    }
}
