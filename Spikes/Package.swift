// swift-tools-version: 6.0
// Throwaway test app that proves the risky parts of Seashell before the real build.
import PackageDescription

let package = Package(
    name: "SeashellSpike",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "SeashellSpike", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
