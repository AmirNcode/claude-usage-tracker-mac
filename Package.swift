// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "UsageCore",
            path: "Sources/UsageCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ClaudeUsageTracker",
            dependencies: ["UsageCore"],
            path: "Sources/ClaudeUsageTracker",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Assertion-based test runner (the CLT-only toolchain on this machine has
        // no XCTest/Swift Testing); run with `swift run UsageCoreTests` or `make test`.
        .executableTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            path: "Tests/UsageCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
