// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MemoryExplainerApp",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "MemoryExplainerApp", targets: ["MemoryExplainerApp"]),
    ],
    targets: [
        .executableTarget(
            name: "MemoryExplainerApp",
            dependencies: []
        ),
    ]
)
