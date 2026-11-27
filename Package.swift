// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "swift-aidl",
    platforms: [.macOS(.v15), .iOS(.v18), .watchOS(.v11), .tvOS(.v18)],
    products: [
        .library(name: "AIDLCore", targets: ["AIDLCore"]),
        .executable(name: "aidl-swift", targets: ["aidl-swift"]),
        .plugin(name: "AIDLPlugin", targets: ["AIDLPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/PureSwift/Binder.git", exact: "0.2.1"),
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
        .testTarget(name: "AIDLCoreTests", dependencies: [
            "AIDLCore",
            .product(name: "Binder", package: "Binder"),
        ]),
    ]
)
