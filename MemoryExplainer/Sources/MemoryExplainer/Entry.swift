import Foundation
import MemoryExplainerCore

@main
struct MemoryExplainerCLI {
    static func main() async {
        let args = CommandLine.arguments
        let useTools = args.contains("--tools")

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
        **Confidence:** \(e.confidence.rawValue)
        """
    }

    static func printUsage() {
        print("""
        memory-explainer - On-device LLM crash/memory analysis

        Usage:
            crash_explain --json | memory-explainer [--tools]
            cat crash.json | memory-explainer [--tools]

        Options:
            --tools    Enable tool calling (model can read source files)

        Reads JSON from stdin, explains using Apple's Foundation Models.
        Include "project_path" in JSON to enable source reading with --tools.
        """)
    }
}
