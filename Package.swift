// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ODoisMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ODoisMonitor",
            path: "Sources/ODoisMonitor",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
