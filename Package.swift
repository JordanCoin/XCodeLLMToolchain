// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MemoryExplainer",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        // Library for other apps to consume (like your menu bar app)
        .library(name: "MemoryExplainerCore", targets: ["MemoryExplainerCore"]),
        // CLI executable
        .executable(name: "memory-explainer", targets: ["MemoryExplainer"]),
        // Test crash generator (for testing the explainer)
        .executable(name: "swift-crash-suite", targets: ["SwiftCrashSuite"]),
    ],
    targets: [
        // Core library - the brains
        .target(
            name: "MemoryExplainerCore",
            dependencies: []
        ),
        // CLI that uses the core
        .executableTarget(
            name: "MemoryExplainer",
            dependencies: ["MemoryExplainerCore"]
        ),
        // Test crash generator
        .executableTarget(
            name: "SwiftCrashSuite",
            dependencies: []
        ),
        // Unit tests
        .testTarget(
            name: "MemoryExplainerCoreTests",
            dependencies: ["MemoryExplainerCore"]
        ),
    ]
)
