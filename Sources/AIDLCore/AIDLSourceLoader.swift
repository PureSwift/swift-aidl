import Foundation

public enum AIDLSourceLoaderError: Error, Sendable, CustomStringConvertible {
    case importNotFound(name: String, importedBy: String, includePaths: [String])
    case declarationMismatch(name: String, path: String)

    public var description: String {
        switch self {
        case let .importNotFound(name, importedBy, includePaths):
            return "\(importedBy): import '\(name)' not found in include paths: \(includePaths.joined(separator: ", "))"
        case let .declarationMismatch(name, path):
            return "\(path): imported file does not declare '\(name)'"
        }
    }
}

/// Parsed source files in depth-first discovery order, beginning with the root file.
public struct AIDLSourceGraph: Sendable {
    public let files: [AIDLFile]
    public let preprocessedFiles: [AIDLFile]
    /// Scalar integer constants and enum values keyed by their fully qualified names.
    public internal(set) var integerConstants: [String: Int64] = [:]
    /// Fully qualified opaque parcelable names referenced by analyzed declarations.
    public internal(set) var referencedOpaqueParcelables: Set<String> = []

    public init(files: [AIDLFile], preprocessedFiles: [AIDLFile] = []) {
        self.files = files
        self.preprocessedFiles = preprocessedFiles
    }
}

/// Loads a root AIDL file and its imports, searching include paths in order.
public struct AIDLSourceLoader: Sendable {
    public let includePaths: [String]

    public init(includePaths: [String] = []) {
        self.includePaths = includePaths
    }

    public func load(sourcePath: String, preprocessedPaths: [String] = []) throws -> AIDLSourceGraph {
        let preprocessedFiles = try preprocessedPaths.map { try parse(URL(fileURLWithPath: $0)) }
        var files: [AIDLFile] = []
        var visited: Set<URL> = []
        try loadFile(at: URL(fileURLWithPath: sourcePath), expectedImport: nil, preprocessedFiles: preprocessedFiles, visited: &visited, files: &files)
        return AIDLSourceGraph(files: files, preprocessedFiles: preprocessedFiles)
    }

    private func loadFile(
        at url: URL,
        expectedImport: [String]?,
        preprocessedFiles: [AIDLFile],
        visited: inout Set<URL>,
        files: inout [AIDLFile]
    ) throws {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        if visited.contains(canonicalURL) {
            if let expectedImport, let existing = files.first(where: { $0.sourcePath == canonicalURL.path }) {
                try validate(expectedImport, in: existing)
            }
            return
        }
        let file = try parse(canonicalURL)
        if let expectedImport { try validate(expectedImport, in: file) }
        visited.insert(canonicalURL)
        files.append(file)

        for importedName in file.imports {
            let name = importedName.joined(separator: ".")
            if AIDLTypeResolver.builtinName(name) != nil || declares(name, in: file) {
                continue
            }
            guard let resolved = resolveImport(importedName) else {
                if preprocessedFiles.contains(where: { declares(name, in: $0, allowEnclosingName: false) }) {
                    continue
                }
                throw AIDLSourceLoaderError.importNotFound(
                    name: name, importedBy: canonicalURL.path, includePaths: includePaths
                )
            }
            try loadFile(at: resolved, expectedImport: importedName, preprocessedFiles: preprocessedFiles, visited: &visited, files: &files)
        }
    }

    private func parse(_ url: URL) throws -> AIDLFile {
        let source = try String(contentsOf: url, encoding: .utf8)
        var parser = try AIDLParser(source: source, sourcePath: url.path)
        return try parser.parse()
    }

    private func resolveImport(_ name: [String]) -> URL? {
        // Nested types may be declared in the enclosing type's file.
        for length in stride(from: name.count, through: 1, by: -1) {
            let relativePath = name.prefix(length).joined(separator: "/") + ".aidl"
            for path in includePaths {
                let candidate = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(relativePath)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    private func validate(_ importedName: [String], in file: AIDLFile) throws {
        let name = importedName.joined(separator: ".")
        guard declares(name, in: file) else {
            throw AIDLSourceLoaderError.declarationMismatch(name: name, path: file.sourcePath)
        }
    }

    private func declares(_ name: String, in file: AIDLFile, allowEnclosingName: Bool = true) -> Bool {
        let package = file.packageName.joined(separator: ".")
        guard package.isEmpty || name.hasPrefix(package + ".") else { return false }

        func contains(_ declarations: [AIDLDeclaration], prefix: [String]) -> Bool {
            declarations.contains { declaration in
                let path = prefix + [declaration.name]
                let qualifiedName = path.joined(separator: ".")
                return qualifiedName == name || (allowEnclosingName && qualifiedName.hasPrefix(name + "."))
                    || contains(declaration.nestedDeclarations, prefix: path)
            }
        }
        return contains(file.declarations, prefix: file.packageName)
    }
}
