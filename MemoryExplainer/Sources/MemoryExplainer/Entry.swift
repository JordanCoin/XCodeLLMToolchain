import Foundation
import MemoryExplainerCore

@main
struct MemoryExplainerCLI {
    static func main() async {
        let args = CommandLine.arguments
        let useTools = args.contains("--tools")

        // Handle special modes
        if args.contains("--help") || args.contains("-h") {
            printHelp()
            return
        }

        if args.contains("--generate") {
            await handleGenerate()
            return
        }

        if args.contains("--battle") {
            await handleBattle()
            return
        }

        // Read JSON from stdin (piped from lldb crash_explain --json)
        let data = FileHandle.standardInput.readDataToEndOfFile()

        guard !data.isEmpty else {
            printUsage()
            exit(1)
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                fputs("Error: Invalid JSON\n", stderr)
                exit(1)
            }

            // Re-serialize to string for the engine
            let jsonString = String(data: try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted), encoding: .utf8) ?? "{}"

            // Extract project path for tools
            let projectPath = json["project_path"] as? String ?? ""

            // Extract codemap context if present
            let codemapContext: String
            if let codemap = json["codemap"] as? [String: Any],
               let codemapData = try? JSONSerialization.data(withJSONObject: codemap, options: .prettyPrinted) {
                codemapContext = String(data: codemapData, encoding: .utf8) ?? ""
            } else {
                codemapContext = ""
            }

            let engine = MemoryExplainerEngine(enableTools: useTools)
            let explanation: String

            if json["crash"] != nil {
                if useTools && !projectPath.isEmpty {
                    print("Analyzing crash with tools (can read source files)...")
                    let result = try await engine.explainCrashWithTools(json: jsonString, projectPath: projectPath)
                    explanation = formatCrashExplanation(result)
                } else {
                    print("Analyzing crash...")
                    explanation = try await engine.explainCrash(json: jsonString, codemapContext: codemapContext)
                }
            } else if json["breakpoint"] != nil {
                print("Analyzing breakpoint state...")
                explanation = try await engine.explainBreakpoint(json: jsonString)
            } else if json["memory"] != nil || json["allocations"] != nil {
                print("Analyzing memory...")
                explanation = try await engine.explainMemory(json: jsonString)
            } else {
                print("Analyzing...")
                explanation = try await engine.explainGeneric(json: jsonString, context: codemapContext)
            }

            print("\n" + explanation)

        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func formatCrashExplanation(_ e: CrashExplanation) -> String {
        """
        **Crash Type:** \(e.crashType)
        **Faulty Function:** `\(e.faultyFunction)`
        **Root Cause:** \(e.rootCause)
        **Fix:** \(e.suggestedFix)
        **Confidence:** \(e.confidence)
        """
    }

    // MARK: - Generate Mode

    static func handleGenerate() async {
        let engine = MemoryExplainerEngine()
        print("🎲 Generating crash scenario...")

        do {
            let crash = try await engine.generateCrash()
            if let json = crash.toJSONString() {
                print(json)
            } else {
                fputs("Error: Failed to serialize crash\n", stderr)
                exit(1)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    // MARK: - Battle Mode

    static func handleBattle() async {
        let engine = MemoryExplainerEngine()

        print("⚔️  BATTLE MODE: Generate → Explain")
        print("=" * 50)

        do {
            print("\n🎲 Generating crash...")
            let (crash, explanation) = try await engine.battleTest()

            print("\n📋 Generated Crash:")
            print("   Type: \(crash.crashType.rawValue)")
            print("   Error: \(crash.stopDescription)")
            print("   Frames:")
            for (i, frame) in crash.frames.enumerated() {
                print("     [\(i)] \(frame.function) @ \(frame.file):\(frame.line)")
            }

            print("\n🧠 Explanation:")
            print("   Crash Type: \(explanation.crashType)")
            print("   Faulty Function: \(explanation.faultyFunction)")
            print("   Root Cause: \(explanation.rootCause)")
            print("   Fix: \(explanation.suggestedFix)")
            print("   Confidence: \(explanation.confidence)")

            print("\n" + "=" * 50)
            print("🤔 Does the explanation match the generated crash?")

        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func printUsage() {
        print("Usage: crash_explain --json | memory-explainer [--tools]")
        print("Try 'memory-explainer --help' for more information.")
    }

    static func printHelp() {
        print("""
        memory-explainer - On-device LLM crash/memory analysis

        ┌─────────────────────────────────────────────────────────────────┐
        │                    MEMORY EXPLAINER TOOLKIT                     │
        ├─────────────────────────────────────────────────────────────────┤
        │                                                                 │
        │   LLDB Scripts ──┐                        ┌── Menu Bar App      │
        │   (crash_explain) │                       │  (UI coming soon)   │
        │                   ▼                       ▼                     │
        │              ┌─────────────────────────────────┐                │
        │              │     memory-explainer CLI        │                │
        │              │   (this tool you're running)    │                │
        │              └───────────────┬─────────────────┘                │
        │                              ▼                                  │
        │              ┌─────────────────────────────────┐                │
        │              │    MemoryExplainerCore          │                │
        │              │  @Generable structured output   │                │
        │              └───────────────┬─────────────────┘                │
        │                              ▼                                  │
        │              ┌─────────────────────────────────┐                │
        │              │  Apple Foundation Models (3B)   │                │
        │              │      On-device, private         │                │
        │              └─────────────────────────────────┘                │
        │                                                                 │
        └─────────────────────────────────────────────────────────────────┘

        USAGE:
            crash_explain --json | memory-explainer [OPTIONS]
            cat crash.json | memory-explainer [OPTIONS]
            memory-explainer --generate
            memory-explainer --battle

        OPTIONS:
            --help, -h  Show this help message
            --tools     Enable tool calling (model can read source files)
            --generate  Generate a random crash scenario (outputs JSON)
            --battle    Generate crash then explain it (model vs model test)

        WORKFLOW FOR iOS ENGINEERS:

        1. Hit a crash in Xcode debugger:
           (lldb) crash_explain --json | memory-explainer

        2. Analyze a saved crash JSON:
           cat ~/crashes/mysterious_nil.json | memory-explainer

        3. Let model read your source code for better diagnosis:
           cat crash.json | memory-explainer --tools

        4. Test the model's reasoning (adversarial):
           memory-explainer --battle

        JSON FORMAT:
            {
              "crash": {
                "stop_description": "EXC_BAD_ACCESS (code=1, address=0x0)",
                "frames": [
                  {"function": "viewDidLoad", "file": "ViewController.swift", "line": 42}
                ]
              },
              "project_path": "/path/to/your/project"  // enables --tools
            }

        WHAT YOU GET:
            - Crash Type:      e.g., "force_unwrap_nil", "use_after_free"
            - Faulty Function: The function where the bug originated
            - Root Cause:      One sentence explaining WHY it crashed
            - Suggested Fix:   Concrete action to fix it
            - Confidence:      low/medium/high

        EXAMPLES:
            # Quick crash diagnosis
            echo '{"crash":{"stop_description":"Fatal error: nil"}}' | memory-explainer

            # Full analysis with source reading
            cat real_crash.json | memory-explainer --tools

            # Watch the model argue with itself
            memory-explainer --battle

        All analysis runs on-device using Apple's Foundation Models.
        No data leaves your Mac. Your crashes stay private.
        """)
    }
}

// Helper
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}
