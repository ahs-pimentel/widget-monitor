// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LLMMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LLMMonitor",
            path: "Sources/LLMMonitor",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
