import AIDLCore
import ArgumentParser
import Foundation

@main
struct AIDLSwift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aidl-swift",
        abstract: "Tools for working with AIDL source files.",
        subcommands: [Check.self, Parse.self, Generate.self]
    )
}

extension AIDLSwift {
    struct Generate: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate Swift Binder bindings for a scalar AIDL interface."
        )

        @Option(name: .customShort("I"), help: "Search this directory for imports, in the order specified.")
        var includePaths: [String] = []

        @Option(name: .customShort("p"), help: "Read type declarations from a preprocessed AIDL file.")
        var preprocessedPaths: [String] = []

        @Option(name: .shortAndLong, help: "Write the Swift source to this file. Defaults to standard output.")
        var output: String?

        @Argument(help: "The root AIDL source file.")
        var sourcePath: String

        func run() throws {
            let source = try AIDLCompiler().compile(
                sourcePath: sourcePath, includePaths: includePaths, preprocessedPaths: preprocessedPaths
            )
            if let output {
                try source.write(toFile: output, atomically: true, encoding: .utf8)
            } else {
                print(source, terminator: "")
            }
        }
    }

    struct Parse: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Parse AIDL source files independently."
        )

        @Argument(help: "AIDL source files to parse.")
        var sourcePaths: [String]

        func run() throws {
            var failures = 0
            for path in sourcePaths {
                do {
                    let source = try String(contentsOfFile: path, encoding: .utf8)
                    var parser = try AIDLParser(source: source, sourcePath: path)
                    _ = try parser.parse()
                } catch {
                    failures += 1
                    let diagnostic = error is AIDLLexerError || error is AIDLParserError
                        ? String(describing: error) : "\(path): \(error)"
                    FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
                }
            }
            print("Parsed \(sourcePaths.count - failures)/\(sourcePaths.count) AIDL file(s).")
            if failures > 0 { throw ExitCode.failure }
        }
    }

    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Analyze AIDL imports, type references, and integer constants."
        )

        @Option(name: .customShort("I"), help: "Search this directory for imports, in the order specified.")
        var includePaths: [String] = []

        @Option(name: .customShort("p"), help: "Read type declarations from a preprocessed AIDL file.")
        var preprocessedPaths: [String] = []

        @Argument(help: "The root AIDL source file.")
        var sourcePath: String

        func run() throws {
            let graph = try AIDLCompiler().analyze(sourcePath: sourcePath, includePaths: includePaths, preprocessedPaths: preprocessedPaths)
            print("Analyzed \(graph.files.count) AIDL file(s) and evaluated \(graph.integerConstants.count) integer constant(s).")
        }
    }
}
