// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "XcodeLLM",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        // Library for other apps to consume
        .library(name: "XcodeLLMCore", targets: ["XcodeLLMCore"]),
        // CLI executable
        .executable(name: "xcode-llm", targets: ["XcodeLLM"]),
        // Test crash generator (curated cases)
        .executable(name: "swift-crash-suite", targets: ["SwiftCrashSuite"]),
        // Random crash generator (for LLM evaluation)
        .executable(name: "swift-crash-generator", targets: ["SwiftCrashGenerator"]),
    ],
    targets: [
        // Core library - the brains
        .target(
            name: "XcodeLLMCore",
            dependencies: []
        ),
        // CLI that uses the core
        .executableTarget(
            name: "XcodeLLM",
            dependencies: ["XcodeLLMCore"]
        ),
        // Test crash generator (curated cases)
        .executableTarget(
            name: "SwiftCrashSuite",
            dependencies: []
        ),
        // Random crash generator (for LLM evaluation)
        .executableTarget(
            name: "SwiftCrashGenerator",
            dependencies: []
        ),
        // Unit tests
        .testTarget(
            name: "XcodeLLMCoreTests",
            dependencies: ["XcodeLLMCore"]
        ),
    ]
)
