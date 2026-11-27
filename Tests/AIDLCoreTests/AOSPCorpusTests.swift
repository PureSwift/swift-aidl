import AIDLCore
import Foundation
import Testing

private let corpusRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../../.build/aosp-aidl")
    .standardizedFileURL

private let includePaths = [
    "frameworks/base/core/java",
    "frameworks/libs/modules-utils/java",
    "packages/modules/Wifi/framework/java",
    "packages/modules/Wifi/framework/aidl-export",
    "packages/modules/Bluetooth/service/aidl",
    "packages/modules/Bluetooth/android/app/aidl",
    "packages/modules/Bluetooth/framework/aidl-export",
    "packages/modules/Connectivity/framework/aidl-export",
].map { corpusRoot.appendingPathComponent($0).path }

private let frameworkAIDL = corpusRoot.appendingPathComponent("prebuilts/sdk/current/public/framework.aidl").path

@Test(
    "Parse every fetched AOSP AIDL file",
    .enabled(if: FileManager.default.fileExists(atPath: corpusRoot.path),
             "Run Scripts/fetch-aosp-aidl.sh to fetch the AOSP corpus.")
)
func parsesAOSPCorpus() throws {
    for project in [
        "frameworks/base",
        "frameworks/libs/modules-utils",
        "packages/modules/Wifi",
        "packages/modules/Bluetooth",
        "packages/modules/Connectivity",
        "prebuilts/sdk",
    ] {
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

@Test(
    "Resolve Wi-Fi and Bluetooth AIDL interfaces",
    .enabled(if: FileManager.default.fileExists(atPath: corpusRoot.path),
             "Run Scripts/fetch-aosp-aidl.sh to fetch the AOSP corpus."),
    arguments: [
        "packages/modules/Wifi/framework/java/android/net/wifi/IWifiManager.aidl",
        "packages/modules/Bluetooth/service/aidl/android/bluetooth/IBluetoothManager.aidl",
        "packages/modules/Bluetooth/android/app/aidl/android/bluetooth/IBluetooth.aidl",
    ]
)
func resolvesAOSPInterfaces(source: String) throws {
    let graph = try AIDLCompiler().analyze(
        sourcePath: corpusRoot.appendingPathComponent(source).path,
        includePaths: includePaths,
        preprocessedPaths: [frameworkAIDL]
    )
    #expect(graph.files.count > 1)
}

#if os(macOS) || os(Linux)
private let aospCompilerPath = ProcessInfo.processInfo.environment["AOSP_AIDL"]

@Test(
    "Compare framework client transaction IDs with the AOSP compiler",
    .enabled(if: aospCompilerPath != nil, "Set AOSP_AIDL to the path of the AOSP aidl compiler.")
)
func comparesAOSPClientTransactions() throws {
    let executable = try #require(aospCompilerPath)
    try #require(FileManager.default.isExecutableFile(atPath: executable), "AOSP_AIDL must point to an executable.")
    try #require(FileManager.default.fileExists(atPath: frameworkAIDL), "Run Scripts/fetch-aosp-aidl.sh first.")
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: output) }

    let cases = [
        (
            "packages/modules/Wifi/framework/java/android/net/wifi/IWifiManager.aidl",
            "android/net/wifi/IWifiManager.java",
            "getWifiEnabledState"
        ),
        (
            "packages/modules/Bluetooth/service/aidl/android/bluetooth/IBluetoothManager.aidl",
            "android/bluetooth/IBluetoothManager.java",
            "getState"
        ),
    ]

    for (input, javaFile, method) in cases {
        let source = corpusRoot.appendingPathComponent(input).path
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: executable)
        compiler.arguments = ["--lang=java", "--omit_invocation", "-p", frameworkAIDL, "-o", output.path]
            + includePaths.flatMap { ["-I", $0] } + [source]
        let diagnostics = Pipe()
        compiler.standardError = diagnostics
        compiler.standardOutput = diagnostics
        try compiler.run()
        let compilerOutput = diagnostics.fileHandleForReading.readDataToEndOfFile()
        compiler.waitUntilExit()
        try #require(compiler.terminationStatus == 0, Comment(rawValue: String(decoding: compilerOutput, as: UTF8.self)))

        let java = try String(contentsOf: output.appendingPathComponent(javaFile), encoding: .utf8)
        let swift = try AIDLCompiler().compile(
            sourcePath: source, includePaths: includePaths, preprocessedPaths: [frameworkAIDL], clientMethods: [method]
        )
        let offset = try numericCapture(in: java, pattern: #"TRANSACTION_"# + method + #"\s*=\s*\(android\.os\.IBinder\.FIRST_CALL_TRANSACTION\s*\+\s*(\d+)\)"#)
        let transactionCode = try numericCapture(in: swift, pattern: "let `\(method)`: UInt32 = " + #"(\d+)"#)
        #expect(transactionCode == offset + 1, "Expected the AOSP transaction code for \(method).")
    }
}

private func numericCapture(in source: String, pattern: String) throws -> UInt32 {
    let regex = try NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex..., in: source)
    let match = try #require(regex.firstMatch(in: source, range: range), "No match for \(pattern).")
    let value = try #require(Range(match.range(at: 1), in: source))
    return try #require(UInt32(source[value]))
}
#endif
