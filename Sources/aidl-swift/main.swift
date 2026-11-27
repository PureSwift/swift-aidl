import AIDLCore
import ArgumentParser
import Foundation

@main
struct AIDLSwift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aidl-swift",
        abstract: "Tools for working with AIDL source files.",
        subcommands: [Check.self, Parse.self]
    )
}

extension AIDLSwift {
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
