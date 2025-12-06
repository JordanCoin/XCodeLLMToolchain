import Foundation

/// CLI for generating Swift crash test cases
///
/// Usage:
///   swift-crash-generator [options]
///
/// Options:
///   --count N          Generate N random crashes (default: 1)
///   --primitive TYPE   Generate only this primitive type
///   --modifier MOD     Apply specific modifier (can repeat)
///   --complexity LEVEL simple|medium|hard (default: medium)
///   --all-simple       Generate all primitives without modifiers
///   --all-combos       Generate all primitive + single modifier combinations
///   --seed N           Use seed for reproducible generation
///   --json             Output as JSON (for pipeline integration)
///   --list             List available primitives and modifiers
///   --write-dir PATH   Write generated files to directory

func printUsage() {
    print("""
    Swift Crash Generator - Generate complex crash test cases

    USAGE:
      swift-crash-generator [options]

    OPTIONS:
      --count N          Generate N random crashes (default: 1)
      --primitive TYPE   Generate only this primitive type
      --modifier MOD     Apply specific modifier (can repeat)
      --complexity LEVEL simple|medium|hard (default: medium)
      --all-simple       Generate all primitives without modifiers
      --all-combos       Generate all primitive + single modifier combinations
      --seed N           Use seed for reproducible generation
      --json             Output as JSON (for pipeline integration)
      --list             List available primitives and modifiers
      --write-dir PATH   Write generated files to directory

    EXAMPLES:
      # Generate one random medium-complexity crash
      swift-crash-generator

      # Generate 10 hard crashes as JSON
      swift-crash-generator --count 10 --complexity hard --json

      # Generate specific primitive with modifier
      swift-crash-generator --primitive force_unwrap_nil --modifier async_await

      # Generate all combinations for evaluation
      swift-crash-generator --all-combos --json > crashes.json

      # Reproducible generation
      swift-crash-generator --count 5 --seed 42
    """)
}

func printList() {
    print("CRASH PRIMITIVES:")
    for primitive in CrashPrimitive.allCases {
        print("  \(primitive.rawValue.padding(toLength: 28, withPad: " ", startingAt: 0)) - \(primitive.description)")
    }

    print("\nCOMPLEXITY MODIFIERS:")
    for modifier in ComplexityModifier.allCases {
        print("  \(modifier.rawValue.padding(toLength: 28, withPad: " ", startingAt: 0)) - \(modifier.description) [score: \(modifier.complexityScore)]")
    }
}

struct CrashOutput: Encodable {
    let id: String
    let primitive: String
    let primitiveDescription: String
    let modifiers: [String]
    let complexityScore: Int
    let description: String
    let sourceCode: String

    init(from crash: GeneratedCrash) {
        self.id = crash.id
        self.primitive = crash.primitive.rawValue
        self.primitiveDescription = crash.primitive.description
        self.modifiers = crash.modifiers.map(\.rawValue)
        self.complexityScore = crash.complexityScore
        self.description = crash.description
        self.sourceCode = crash.sourceCode
    }
}

func outputCrashes(_ crashes: [GeneratedCrash], asJson: Bool, writeDir: String?) {
    if let dir = writeDir {
        // Write to files
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        for crash in crashes {
            let filename = "\(crash.id).swift"
            let path = (dir as NSString).appendingPathComponent(filename)
            try? crash.sourceCode.write(toFile: path, atomically: true, encoding: .utf8)

            // Also write metadata
            let metaFilename = "\(crash.id).json"
            let metaPath = (dir as NSString).appendingPathComponent(metaFilename)
            let output = CrashOutput(from: crash)
            if let data = try? JSONEncoder().encode(output) {
                try? data.write(to: URL(fileURLWithPath: metaPath))
            }
        }
        print("Wrote \(crashes.count) crash files to \(dir)")

    } else if asJson {
        // JSON output to stdout
        let outputs = crashes.map { CrashOutput(from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(outputs),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }

    } else {
        // Human-readable output
        for (i, crash) in crashes.enumerated() {
            if crashes.count > 1 {
                print("=== Crash \(i + 1)/\(crashes.count): \(crash.id) ===")
            }
            print("Primitive: \(crash.primitive.rawValue) (\(crash.primitive.description))")
            print("Modifiers: \(crash.modifiers.isEmpty ? "none" : crash.modifiers.map(\.rawValue).joined(separator: ", "))")
            print("Complexity: \(crash.complexityScore)")
            print("\n--- Source Code ---")
            print(crash.sourceCode)
            print("--- End ---\n")
        }
    }
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("--help") || args.contains("-h") {
    printUsage()
    exit(0)
}

if args.contains("--list") {
    printList()
    exit(0)
}

// Parse arguments
var count = 1
var primitiveArg: String?
var modifierArgs: [String] = []
var complexity = "medium"
var allSimple = false
var allCombos = false
var seed: UInt64?
var asJson = false
var writeDir: String?

var i = 0
while i < args.count {
    switch args[i] {
    case "--count":
        i += 1
        count = Int(args[i]) ?? 1
    case "--primitive":
        i += 1
        primitiveArg = args[i]
    case "--modifier":
        i += 1
        modifierArgs.append(args[i])
    case "--complexity":
        i += 1
        complexity = args[i]
    case "--all-simple":
        allSimple = true
    case "--all-combos":
        allCombos = true
    case "--seed":
        i += 1
        seed = UInt64(args[i])
    case "--json":
        asJson = true
    case "--write-dir":
        i += 1
        writeDir = args[i]
    default:
        break
    }
    i += 1
}

// Build config
let config: CrashGenerator.Config
switch complexity {
case "simple":
    config = .simple
case "hard":
    config = .hard
default:
    config = .medium
}

var generator = CrashGenerator(config: config, seed: seed)
var crashes: [GeneratedCrash] = []

if allSimple {
    crashes = generator.generateAllSimple()
} else if allCombos {
    crashes = generator.generateAllCombinations()
} else if let primStr = primitiveArg {
    guard let primitive = CrashPrimitive(rawValue: primStr) else {
        print("Unknown primitive: \(primStr)")
        print("Use --list to see available primitives")
        exit(1)
    }

    let modifiers: [ComplexityModifier] = modifierArgs.compactMap { modStr in
        guard let mod = ComplexityModifier(rawValue: modStr) else {
            print("Warning: Unknown modifier '\(modStr)', skipping")
            return nil
        }
        return mod
    }

    if modifiers.isEmpty && modifierArgs.isEmpty {
        crashes = [generator.generate(primitive: primitive)]
    } else {
        crashes = [generator.generate(primitive: primitive, modifiers: modifiers)]
    }
} else {
    crashes = generator.generateBatch(count: count)
}

outputCrashes(crashes, asJson: asJson, writeDir: writeDir)
