// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Seashell",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "SeashellCore"),
        .executableTarget(name: "Seashell", dependencies: ["SeashellCore"]),
        .testTarget(name: "SeashellCoreTests", dependencies: ["SeashellCore"]),
    ]
)
