// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MemoryExplainer",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(name: "MemoryExplainerCore", targets: ["MemoryExplainerCore"]),
        .executable(name: "memory-explainer", targets: ["MemoryExplainer"]),
    ],
    targets: [
        .target(
            name: "MemoryExplainerCore",
            dependencies: []
        ),
        .executableTarget(
            name: "MemoryExplainer",
            dependencies: ["MemoryExplainerCore"]
        ),
    ]
)
