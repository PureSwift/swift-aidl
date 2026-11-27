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

    public init(files: [AIDLFile]) {
        self.files = files
    }
}

/// Loads a root AIDL file and its imports, searching include paths in order.
public struct AIDLSourceLoader: Sendable {
    public let includePaths: [String]

    public init(includePaths: [String] = []) {
        self.includePaths = includePaths
    }

    public func load(sourcePath: String) throws -> AIDLSourceGraph {
        var files: [AIDLFile] = []
        var visited: Set<URL> = []
        try loadFile(at: URL(fileURLWithPath: sourcePath), expectedImport: nil, visited: &visited, files: &files)
        return AIDLSourceGraph(files: files)
    }

    private func loadFile(
        at url: URL,
        expectedImport: [String]?,
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
        let source = try String(contentsOf: canonicalURL, encoding: .utf8)
        var parser = try AIDLParser(source: source, sourcePath: canonicalURL.path)
        let file = try parser.parse()
        if let expectedImport { try validate(expectedImport, in: file) }
        visited.insert(canonicalURL)
        files.append(file)

        for importedName in file.imports {
            let relativePath = importedName.joined(separator: "/") + ".aidl"
            let resolved = includePaths.lazy
                .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(relativePath) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            guard let resolved else {
                throw AIDLSourceLoaderError.importNotFound(
                    name: importedName.joined(separator: "."), importedBy: canonicalURL.path, includePaths: includePaths
                )
            }
            try loadFile(at: resolved, expectedImport: importedName, visited: &visited, files: &files)
        }
    }

    private func validate(_ importedName: [String], in file: AIDLFile) throws {
        let declarationNames = file.declarations.map { declaration in
            switch declaration {
            case let .interface(value): value.name
            case let .parcelable(value): value.name
            case let .enumeration(value): value.name
            case let .union(value): value.name
            }
        }
        guard Array(importedName.dropLast()) == file.packageName,
              let name = importedName.last, declarationNames.contains(name) else {
            throw AIDLSourceLoaderError.declarationMismatch(name: importedName.joined(separator: "."), path: file.sourcePath)
        }
    }
}
