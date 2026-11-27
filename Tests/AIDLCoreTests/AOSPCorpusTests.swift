import AIDLCore
import Foundation
import Testing

private let corpusRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../../.build/aosp-aidl")
    .standardizedFileURL

@Test(
    "Parse every fetched AOSP AIDL file",
    .enabled(if: FileManager.default.fileExists(atPath: corpusRoot.path),
             "Run Scripts/fetch-aosp-aidl.sh to fetch the AOSP corpus.")
)
func parsesAOSPCorpus() throws {
    for project in ["frameworks/base", "packages/modules/Wifi", "packages/modules/Bluetooth"] {
        let root = corpusRoot.appendingPathComponent(project, isDirectory: true)
        let entries = try #require(FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                Issue.record("Could not enumerate \(url.path): \(error)")
                return true
            }
        ))

        var parsedFiles = 0
        for case let file as URL in entries where file.pathExtension == "aidl" {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            parsedFiles += 1
            do {
                let source = try String(contentsOf: file, encoding: .utf8)
                var parser = try AIDLParser(source: source, sourcePath: file.path)
                _ = try parser.parse()
            } catch {
                Issue.record("Failed to parse \(file.path): \(error)")
            }
        }
        #expect(parsedFiles > 0, "No AIDL files found in \(project). Run Scripts/fetch-aosp-aidl.sh.")
    }
}
