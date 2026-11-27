import Foundation
import PackagePlugin

@main
struct AIDLPlugin: BuildToolPlugin {
    private struct Configuration: Decodable {
        let sources: [String]
        let includePaths: [String]?
        let preprocessedPaths: [String]?
        let interfaceMetadata: [String: InterfaceMetadata]?
        let manualParcelables: [String]?
        let clientMethods: [String: [String]]?
    }

    private struct InterfaceMetadata: Decodable {
        let version: Int32?
        let hash: String?
    }

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let directory = target.directoryURL
        let configFile = directory.appendingPathComponent("aidl-config.json")
        guard FileManager.default.fileExists(atPath: configFile.path) else { return [] }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configFile))
        let metadata = config.interfaceMetadata ?? [:]
        if let unknownSource = metadata.keys.sorted().first(where: { !config.sources.contains($0) }) {
            throw PluginError("Interface metadata names an unconfigured source: \(unknownSource)")
        }
        let clients = config.clientMethods ?? [:]
        if let invalid = clients.keys.sorted().first(where: { !config.sources.contains($0) || clients[$0]?.isEmpty == true }) {
            throw PluginError("Client method selection requires a configured source and at least one method: \(invalid)")
        }
        let sources = config.sources.map { resolve($0, relativeTo: directory) }
        let includes = (config.includePaths ?? []).map { resolve($0, relativeTo: directory) }
        let preprocessed = (config.preprocessedPaths ?? []).map { resolve($0, relativeTo: directory) }
        let tool = try context.tool(named: "aidl-swift")
        let imported = try includes.flatMap(aidlFiles(in:))
        var outputs = Set<String>()
        return try zip(config.sources, sources).map { path, source in
            guard source.pathExtension == "aidl",
                  FileManager.default.isReadableFile(atPath: source.path) else {
                throw PluginError("Cannot read AIDL source at \(source.path)")
            }
            let filename = source.deletingPathExtension().lastPathComponent + ".aidl.swift"
            guard outputs.insert(filename).inserted else {
                throw PluginError("Multiple AIDL sources would generate \(filename)")
            }
            let output = context.pluginWorkDirectoryURL.appendingPathComponent(filename)
            var arguments = ["generate", "-o", output.path]
            arguments += includes.flatMap { ["-I", $0.path] }
            arguments += preprocessed.flatMap { ["-p", $0.path] }
            arguments += (config.manualParcelables ?? []).flatMap { ["--manual-parcelable", $0] }
            arguments += (clients[path] ?? []).flatMap { ["--client-method", $0] }
            if let version = metadata[path]?.version { arguments += ["--interface-version", String(version)] }
            if let hash = metadata[path]?.hash { arguments.append("--interface-hash=\(hash)") }
            arguments.append(source.path)
            let inputs = Set([configFile, source] + imported + preprocessed)
            return .buildCommand(
                displayName: "Generate Swift bindings for \(source.lastPathComponent)",
                executable: tool.url,
                arguments: arguments,
                inputFiles: inputs.sorted { $0.path < $1.path },
                outputFiles: [output]
            )
        }
    }

    private func resolve(_ path: String, relativeTo directory: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL
    }

    private func aidlFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".aidl") }
            .map { directory.appendingPathComponent($0) }
    }

    private struct PluginError: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }
}
