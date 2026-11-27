// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "FrameworkClient",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(name: "swift-aidl", path: "../.."),
        .package(url: "https://github.com/PureSwift/Binder.git", exact: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "FrameworkClient",
            dependencies: [.product(name: "Binder", package: "Binder")],
            exclude: ["aidl-config.json"],
            plugins: [.plugin(name: "AIDLPlugin", package: "swift-aidl")]
        ),
    ]
)
