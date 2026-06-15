// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "UsageCore",
            path: "Sources/UsageCore"
        ),
        .executableTarget(
            name: "ClaudeUsageTracker",
            dependencies: ["UsageCore"],
            path: "Sources/ClaudeUsageTracker"
        ),
        // Assertion-based test runner (the CLT-only toolchain on the build machine
        // ships no XCTest/Swift Testing); run with `swift run UsageCoreTests`.
        .executableTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            path: "Tests/UsageCoreTests"
        ),
    ]
)
