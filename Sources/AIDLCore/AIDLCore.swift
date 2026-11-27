public struct AIDLParcelableLayoutError: Error, Sendable, CustomStringConvertible {
    public let missingTypes: [String]

    public var description: String {
        "Missing parcelable layouts for \(missingTypes.joined(separator: ", ")). Provide structured AIDL overrides or manual implementations."
    }
}

/// Entry point for the AIDL compilation pipeline.
public struct AIDLCompiler: Sendable {
    public init() {}

    /// Loads sources, resolves type references and evaluates scalar integer constants and enum values.
    /// Pass an empty or populated manual parcelable registry to require a layout for every referenced type.
    public func analyze(
        sourcePath: String,
        includePaths: [String] = [],
        preprocessedPaths: [String] = [],
        manualParcelables: Set<String>? = nil
    ) throws -> AIDLSourceGraph {
        var graph = try AIDLSourceLoader(includePaths: includePaths).load(sourcePath: sourcePath, preprocessedPaths: preprocessedPaths)
        let resolver = try AIDLTypeResolver(graph: graph)
        graph.referencedOpaqueParcelables = try resolver.validateTypeReferences(in: graph)
        graph.integerConstants = try AIDLIntegerConstantAnalysis(resolver: resolver).evaluate(in: graph.files)
        if let manualParcelables {
            let missing = graph.referencedOpaqueParcelables.subtracting(manualParcelables)
            guard missing.isEmpty else { throw AIDLParcelableLayoutError(missingTypes: missing.sorted()) }
        }
        return graph
    }

    /// Emits Swift bindings for the root interface, structured parcelable, or enum.
    public func compile(
        sourcePath: String,
        includePaths: [String] = [],
        preprocessedPaths: [String] = []
    ) throws -> String {
        let graph = try analyze(sourcePath: sourcePath, includePaths: includePaths, preprocessedPaths: preprocessedPaths)
        return try AIDLSwiftGenerator(
            file: graph.files[0], resolver: AIDLTypeResolver(graph: graph), integerConstants: graph.integerConstants
        ).generate()
    }
}
