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
///   --run              Compile, run, and capture crash as JSON (for pipeline)

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
      --run              Compile, run under lldb, capture crash as JSON
      --run-only         Just output the crash JSON (skip source code output)

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

      # Generate, run, and pipe to pipeline for analysis
      swift-crash-generator --primitive force_unwrap_nil --run-only | xcode-llm --pipeline
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

// MARK: - Crash Runner

struct CrashRunner {
    let sourceCode: String
    let primitive: CrashPrimitive
    let modifiers: [ComplexityModifier]

    struct CapturedCrash: Encodable {
        let stop_description: String
        let stop_reason_type: String
        let crash_type: String
        let frames: [[String: Any]]
        let ground_truth: GroundTruth

        struct GroundTruth: Encodable {
            let primitive: String
            let modifiers: [String]
            let complexity_score: Int
        }

        func encode(to encoder: Encoder) throws {
            // Custom encoding since frames contains Any
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(stop_description, forKey: .stop_description)
            try container.encode(stop_reason_type, forKey: .stop_reason_type)
            try container.encode(crash_type, forKey: .crash_type)
            try container.encode(ground_truth, forKey: .ground_truth)
            // frames handled separately via JSONSerialization
        }

        enum CodingKeys: String, CodingKey {
            case stop_description, stop_reason_type, crash_type, frames, ground_truth
        }

        func toJSONString() -> String? {
            var dict: [String: Any] = [
                "stop_description": stop_description,
                "stop_reason_type": stop_reason_type,
                "crash_type": crash_type,
                "frames": frames,
                "ground_truth": [
                    "primitive": ground_truth.primitive,
                    "modifiers": ground_truth.modifiers,
                    "complexity_score": ground_truth.complexity_score
                ]
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }
    }

    func run() -> CapturedCrash? {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceFile = tempDir.appendingPathComponent("crash_test_\(UUID().uuidString).swift")
        let binaryFile = tempDir.appendingPathComponent("crash_test_\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: sourceFile)
            try? FileManager.default.removeItem(at: binaryFile)
        }

        // Write source
        do {
            try sourceCode.write(to: sourceFile, atomically: true, encoding: .utf8)
        } catch {
            fputs("Error writing source: \(error)\n", stderr)
            return nil
        }

        // Compile
        let compileResult = shell("swiftc -g -o \(binaryFile.path) \(sourceFile.path) 2>&1")
        if compileResult.status != 0 {
            fputs("Compile error:\n\(compileResult.output)\n", stderr)
            return nil
        }

        // Run under lldb and capture crash
        let lldbScript = """
        run
        bt
        frame variable
        quit
        """

        let lldbScriptFile = tempDir.appendingPathComponent("lldb_script_\(UUID().uuidString).lldb")
        try? lldbScript.write(to: lldbScriptFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: lldbScriptFile) }

        let lldbResult = shell("lldb -b -s \(lldbScriptFile.path) \(binaryFile.path) 2>&1", timeout: 10)

        // Parse lldb output
        return parseLLDBOutput(lldbResult.output)
    }

    private func parseLLDBOutput(_ output: String) -> CapturedCrash? {
        let lines = output.components(separatedBy: "\n")

        // Find stop reason
        var stopDescription = "Unknown crash"
        var stopReasonType = "exception"

        for line in lines {
            if line.contains("Fatal error:") || line.contains("Unexpectedly found nil") {
                stopDescription = line.trimmingCharacters(in: .whitespaces)
                stopReasonType = "exception"
                break
            } else if line.contains("EXC_BAD_ACCESS") {
                stopDescription = "EXC_BAD_ACCESS"
                stopReasonType = "signal"
                break
            } else if line.contains("EXC_BAD_INSTRUCTION") {
                stopDescription = "EXC_BAD_INSTRUCTION"
                stopReasonType = "signal"
                break
            } else if line.contains("EXC_ARITHMETIC") {
                stopDescription = "EXC_ARITHMETIC (division by zero)"
                stopReasonType = "signal"
                break
            } else if line.contains("Stack overflow") || line.contains("stack overflow") {
                stopDescription = "Stack overflow"
                stopReasonType = "signal"
                break
            } else if line.contains("Precondition failed") {
                stopDescription = line.trimmingCharacters(in: .whitespaces)
                stopReasonType = "exception"
                break
            }
        }

        // Parse backtrace
        var frames: [[String: Any]] = []
        var inBacktrace = false
        var frameIndex = 0

        for line in lines {
            if line.contains("(lldb) bt") {
                inBacktrace = true
                continue
            }
            if inBacktrace && line.contains("(lldb)") {
                inBacktrace = false
                continue
            }

            if inBacktrace {
                // Parse frame like: "frame #0: 0x... crash_test`closure #1 in runAsync() at crash_test.swift:14"
                if line.contains("frame #") {
                    var frame: [String: Any] = ["index": frameIndex]

                    // Extract function name
                    if let backticksRange = line.range(of: "`"),
                       let atRange = line.range(of: " at ") {
                        let funcPart = String(line[backticksRange.upperBound..<atRange.lowerBound])
                        frame["function"] = funcPart.trimmingCharacters(in: .whitespaces)
                    } else if let backticksRange = line.range(of: "`") {
                        let rest = String(line[backticksRange.upperBound...])
                        let funcName = rest.components(separatedBy: " ").first ?? rest
                        frame["function"] = funcName
                    }

                    // Extract file and line
                    if let atRange = line.range(of: " at ") {
                        let filePart = String(line[atRange.upperBound...])
                        let components = filePart.components(separatedBy: ":")
                        if components.count >= 2 {
                            frame["file"] = components[0]
                            frame["line"] = Int(components[1].trimmingCharacters(in: .whitespaces)) ?? 0
                        }
                    }

                    // Mark system frames
                    let isSystem = line.contains("libswiftCore") ||
                                   line.contains("libdyld") ||
                                   line.contains("Foundation") ||
                                   line.contains("CoreFoundation") ||
                                   line.contains("libsystem")
                    frame["is_system"] = isSystem

                    frames.append(frame)
                    frameIndex += 1
                }
            }
        }

        // Map primitive to crash type
        let crashType: String
        switch primitive {
        case .forceUnwrapNil, .dictionaryKeyMissing:
            crashType = "force_unwrap_nil"
        case .arrayOutOfBounds, .stringIndexOutOfBounds:
            crashType = "array_out_of_bounds"
        case .failedTypeCast:
            crashType = "type_cast_failure"
        case .unownedAfterDealloc:
            crashType = "unowned_dealloc"
        case .integerOverflow:
            crashType = "integer_overflow"
        case .divisionByZero:
            crashType = "division_by_zero"
        case .preconditionFailure:
            crashType = "assertion_failure"
        case .fatalErrorCall:
            crashType = "assertion_failure"
        case .stackOverflow:
            crashType = "stack_overflow"
        }

        return CapturedCrash(
            stop_description: stopDescription,
            stop_reason_type: stopReasonType,
            crash_type: crashType,
            frames: frames,
            ground_truth: .init(
                primitive: primitive.rawValue,
                modifiers: modifiers.map(\.rawValue),
                complexity_score: modifiers.reduce(0) { $0 + $1.complexityScore }
            )
        )
    }

    private func shell(_ command: String, timeout: Int = 30) -> (output: String, status: Int32) {
        let process = Process()
        let pipe = Pipe()

        process.standardOutput = pipe
        process.standardError = pipe
        process.arguments = ["-c", command]
        process.executableURL = URL(fileURLWithPath: "/bin/bash")

        do {
            try process.run()

            // Timeout handling
            let deadline = Date().addingTimeInterval(TimeInterval(timeout))
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                process.terminate()
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return (output, process.terminationStatus)
        } catch {
            return ("Error: \(error)", 1)
        }
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
var runMode = false
var runOnly = false

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
    case "--run":
        runMode = true
    case "--run-only":
        runMode = true
        runOnly = true
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

// Handle run mode
if runMode {
    for crash in crashes {
        if !runOnly {
            fputs("Generating: \(crash.primitive.rawValue)", stderr)
            if !crash.modifiers.isEmpty {
                fputs(" + \(crash.modifiers.map(\.rawValue).joined(separator: ", "))", stderr)
            }
            fputs("\n", stderr)
            fputs("Compiling and running...\n", stderr)
        }

        let runner = CrashRunner(
            sourceCode: crash.sourceCode,
            primitive: crash.primitive,
            modifiers: crash.modifiers
        )

        if let captured = runner.run() {
            if let json = captured.toJSONString() {
                print(json)
            } else {
                fputs("Error: Failed to serialize crash\n", stderr)
                exit(1)
            }
        } else {
            fputs("Error: Failed to capture crash\n", stderr)
            exit(1)
        }
    }
} else {
    outputCrashes(crashes, asJson: asJson, writeDir: writeDir)
}
