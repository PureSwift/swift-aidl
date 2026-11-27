// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "swift-aidl",
    products: [
        .library(name: "AIDLCore", targets: ["AIDLCore"]),
        .executable(name: "aidl-swift", targets: ["aidl-swift"]),
        .plugin(name: "AIDLPlugin", targets: ["AIDLPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
    ],
    targets: [
        .target(name: "AIDLCore"),
        .executableTarget(name: "aidl-swift", dependencies: [
            "AIDLCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .plugin(
            name: "AIDLPlugin",
            capability: .buildTool(),
            dependencies: ["aidl-swift"]
        ),
        .testTarget(name: "AIDLCoreTests", dependencies: ["AIDLCore"]),
    ]
)
