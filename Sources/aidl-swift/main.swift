import AIDLCore
import ArgumentParser

@main
struct AIDLSwift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aidl-swift",
        abstract: "Tools for working with AIDL source files.",
        subcommands: [Check.self]
    )
}

extension AIDLSwift {
    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Parse an AIDL file and resolve its type references."
        )

        @Option(name: .customShort("I"), help: "Search this directory for imports, in the order specified.")
        var includePaths: [String] = []

        @Argument(help: "The root AIDL source file.")
        var sourcePath: String

        func run() throws {
            let graph = try AIDLCompiler().analyze(sourcePath: sourcePath, includePaths: includePaths)
            print("Parsed and resolved type references in \(graph.files.count) AIDL file(s).")
        }
    }
}
