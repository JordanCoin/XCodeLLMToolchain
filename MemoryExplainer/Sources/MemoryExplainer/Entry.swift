import Foundation
import MemoryExplainerCore

@main
struct MemoryExplainerCLI {
    static func main() async {
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

            // Extract codemap context if present
            let codemapContext: String
            if let codemap = json["codemap"] as? [String: Any],
               let codemapData = try? JSONSerialization.data(withJSONObject: codemap, options: .prettyPrinted) {
                codemapContext = String(data: codemapData, encoding: .utf8) ?? ""
            } else {
                codemapContext = ""
            }

            // Determine type and explain
            let engine = MemoryExplainerEngine()
            let explanation: String

            if json["crash"] != nil {
                print("Analyzing crash...")
                explanation = try await engine.explainCrash(json: jsonString, codemapContext: codemapContext)
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

    static func printUsage() {
        print("""
        memory-explainer - On-device LLM crash/memory analysis

        Usage:
            crash_explain --json | memory-explainer
            cat crash.json | memory-explainer

        Reads JSON from stdin, explains using Apple's Foundation Models.
        """)
    }
}
