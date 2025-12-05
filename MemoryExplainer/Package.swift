// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MemoryExplainer",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .executable(name: "memory-explainer", targets: ["MemoryExplainer"]),
    ],
    targets: [
        .executableTarget(
            name: "MemoryExplainer",
            dependencies: []
        ),
    ]
)
