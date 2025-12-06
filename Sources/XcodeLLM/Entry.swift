import Foundation
import XcodeLLMCore

@main
struct XcodeLLMCLI {
    static func main() async {
        let args = CommandLine.arguments
        let useTools = args.contains("--tools")
        let usePipeline = args.contains("--pipeline")
        let synthesizeOnly = args.contains("--synthesize")

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
            await handleBattle(usePipeline: usePipeline)
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

            let engine = XcodeLLMEngine(enableTools: useTools)
            let explanation: String

            if json["crash"] != nil || json["frames"] != nil {
                // Crash analysis - choose mode
                if synthesizeOnly {
                    print("Running scoring pipeline (synthesis only)...")
                    let (synthesis, outputs) = try await engine.synthesizeOnly(json: jsonString)
                    explanation = formatSynthesis(synthesis, outputs: outputs)
                } else if usePipeline {
                    print("Analyzing crash with scoring pipeline...")
                    print("  → Scoring frames in parallel")
                    print("  → Analyzing variables")
                    print("  → Detecting code patterns")
                    print("  → Synthesizing evidence")
                    print("  → Final analysis")
                    let result = try await engine.explainCrashWithPipeline(json: jsonString)
                    explanation = result.formatted
                } else if useTools && !projectPath.isEmpty {
                    print("Analyzing crash with tools (can read source files)...")
                    let result = try await engine.explainCrashWithTools(json: jsonString, projectPath: projectPath)
                    explanation = formatCrashExplanation(result)
                } else {
                    print("Analyzing crash (use --pipeline for deeper analysis)...")
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

    static func formatSynthesis(_ synthesis: SynthesizedContext, outputs: ScorerOutputs) -> String {
        var result = """
        === SCORER OUTPUTS ===

        FRAME SCORES (\(outputs.frameScores.count) frames):

        """

        for score in outputs.frameScores.sorted(by: { $0.relevanceScore > $1.relevanceScore }).prefix(10) {
            let marker = score.isBugOrigin ? " [BUG ORIGIN]" : ""
            result += String(format: "  %.2f [%d] %@%@ - %@\n",
                           score.relevanceScore,
                           score.frameIndex,
                           score.isUserCode ? "user" : "system",
                           marker,
                           score.reasoning)
        }

        if !outputs.variableScores.isEmpty {
            result += "\nVARIABLE SCORES (\(outputs.variableScores.count) variables):\n"
            for score in outputs.variableScores.sorted(by: { $0.suspicionScore > $1.suspicionScore }).prefix(8) {
                result += String(format: "  %.2f [%@] %@ in frame %d - %@\n",
                               score.suspicionScore,
                               score.issueCategory,
                               score.variableName,
                               score.frameIndex,
                               score.observation)
            }
        }

        if !outputs.contextScores.isEmpty {
            result += "\nCODE PATTERNS (\(outputs.contextScores.count) files):\n"
            for score in outputs.contextScores.filter({ $0.patternDetected != "none" }) {
                let filename = (score.filePath as NSString).lastPathComponent
                result += String(format: "  %.2f [%@] in %@ - %@\n",
                               score.patternConfidence,
                               score.patternDetected,
                               filename,
                               score.codeConstruct ?? "")
            }
        }

        result += """

        === SYNTHESIS ===
        Pattern: \(synthesis.likelyCrashPattern)
        Hypothesis: \(synthesis.preliminaryHypothesis)
        Confidence: \(String(format: "%.0f%%", synthesis.hypothesisConfidence * 100))

        Key Evidence:

        """

        for (i, evidence) in synthesis.keyEvidence.enumerated() {
            result += "  \(i + 1). \(evidence)\n"
        }

        result += "\nRelevant Frames: \(synthesis.relevantFrameIndices.map(String.init).joined(separator: ", "))"
        result += "\nSuspicious Vars: \(synthesis.suspiciousVariables.joined(separator: ", "))"

        return result
    }

    // MARK: - Generate Mode

    static func handleGenerate() async {
        let engine = XcodeLLMEngine()
        print("Generating crash scenario...")

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

    static func handleBattle(usePipeline: Bool) async {
        let engine = XcodeLLMEngine()

        print("BATTLE MODE: Generate -> Explain\(usePipeline ? " (with Pipeline)" : "")")
        print("=" * 50)

        do {
            print("\nGenerating crash...")
            let crash = try await engine.generateCrash()

            print("\nGenerated Crash:")
            print("   Type: \(crash.crashType.rawValue)")
            print("   Error: \(crash.stopDescription)")
            print("   Frames:")
            for (i, frame) in crash.frames.enumerated() {
                print("     [\(i)] \(frame.function) @ \(frame.file):\(frame.line)")
            }

            guard let jsonString = crash.toJSONString() else {
                fputs("Error: Failed to serialize crash\n", stderr)
                exit(1)
            }

            if usePipeline {
                print("\nRunning scoring pipeline...")
                print("  → Scoring frames")
                print("  → Analyzing variables")
                print("  → Detecting patterns")
                print("  → Synthesizing")
                print("  → Final analysis")

                let result = try await engine.explainCrashWithPipeline(json: jsonString)

                print("\n" + "=" * 50)
                print("SYNTHESIS:")
                print("   Pattern: \(result.synthesis.likelyCrashPattern)")
                print("   Hypothesis: \(result.synthesis.preliminaryHypothesis)")
                print("   Confidence: \(String(format: "%.0f%%", result.synthesis.hypothesisConfidence * 100))")
                print("   Evidence:")
                for evidence in result.synthesis.keyEvidence {
                    print("     • \(evidence)")
                }

                print("\nFINAL ANALYSIS:")
                print("   Crash Type: \(result.explanation.crashType)")
                print("   Faulty Function: \(result.explanation.faultyFunction)")
                print("   Root Cause: \(result.explanation.rootCause)")
                print("   Fix: \(result.explanation.suggestedFix)")
                print("   Confidence: \(result.explanation.confidence)")

                print("\nMETRICS:")
                print("   Frames scored: \(result.metrics.framesScored)")
                print("   Variables analyzed: \(result.metrics.variablesScored)")
                print("   Patterns found: \(result.metrics.patternsFound)")
                print("   Est. tokens: ~\(result.metrics.totalTokensEstimate)")
            } else {
                print("\nExplaining (direct mode)...")
                let explanation = try await engine.explainCrashStructured(json: jsonString)

                print("\nExplanation:")
                print("   Crash Type: \(explanation.crashType)")
                print("   Faulty Function: \(explanation.faultyFunction)")
                print("   Root Cause: \(explanation.rootCause)")
                print("   Fix: \(explanation.suggestedFix)")
                print("   Confidence: \(explanation.confidence)")
            }

            print("\n" + "=" * 50)
            print("Does the explanation match the generated crash?")

        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func printUsage() {
        print("Usage: crash_explain --json | xcode-llm [--tools]")
        print("Try 'xcode-llm --help' for more information.")
    }

    static func printHelp() {
        print("""
        xcode-llm - On-device LLM crash/memory analysis

        ┌─────────────────────────────────────────────────────────────────┐
        │                      XCODE LLM TOOLCHAIN                        │
        ├─────────────────────────────────────────────────────────────────┤
        │                                                                 │
        │   LLDB Scripts ───────┐                                         │
        │   (crash_explain)     │                                         │
        │   (explain_here)      ▼                                         │
        │              ┌─────────────────────────────────┐                │
        │              │       xcode-llm CLI             │                │
        │              └───────────────┬─────────────────┘                │
        │                              ▼                                  │
        │   ┌───────────────────────────────────────────────────────┐     │
        │   │              SCORING PIPELINE (--pipeline)            │     │
        │   │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐      │     │
        │   │  │FrameScorer  │ │VariableScr │ │ContextScorer│      │     │
        │   │  │  (parallel) │ │  (parallel) │ │  (parallel) │      │     │
        │   │  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘      │     │
        │   │         └───────────────┼───────────────┘             │     │
        │   │                         ▼                             │     │
        │   │              ┌─────────────────────┐                  │     │
        │   │              │    Synthesizer      │                  │     │
        │   │              │ (cross-references)  │                  │     │
        │   │              └──────────┬──────────┘                  │     │
        │   └─────────────────────────┼─────────────────────────────┘     │
        │                             ▼                                   │
        │              ┌─────────────────────────────────┐                │
        │              │        Final Analyzer           │                │
        │              │  (high-signal, low-token input) │                │
        │              └───────────────┬─────────────────┘                │
        │                              ▼                                  │
        │              ┌─────────────────────────────────┐                │
        │              │  Apple Foundation Models (3B)   │                │
        │              │      On-device, private         │                │
        │              └─────────────────────────────────┘                │
        └─────────────────────────────────────────────────────────────────┘

        USAGE:
            crash_explain --json | xcode-llm [OPTIONS]
            cat crash.json | xcode-llm [OPTIONS]
            xcode-llm --generate
            xcode-llm --battle [--pipeline]

        OPTIONS:
            --help, -h    Show this help message
            --pipeline    Use multi-layer scoring pipeline (recommended for complex crashes)
            --synthesize  Debug: run scorers + synthesizer only, skip final analysis
            --tools       Enable tool calling (model can read source files)
            --generate    Generate a random crash scenario (outputs JSON)
            --battle      Generate crash then explain it (model vs model test)

        ANALYSIS MODES:

        1. DIRECT (default):
           Single model call. Fast but may miss subtle issues.
           cat crash.json | xcode-llm

        2. PIPELINE (--pipeline):
           Multi-layer analysis with parallel scoring.
           - FrameScorer: scores each stack frame for relevance
           - VariableScorer: detects nil, dangling pointers, invalid values
           - ContextScorer: finds dangerous code patterns (!, as!, try!)
           - Synthesizer: cross-references evidence, forms hypothesis
           - Final Analyzer: uses high-signal, condensed input

           cat crash.json | xcode-llm --pipeline

        WORKFLOW:

        1. Quick crash check:
           (lldb) crash_explain --json | xcode-llm

        2. Deep analysis with scoring pipeline:
           (lldb) crash_explain --json | xcode-llm --pipeline

        3. Debug the scoring layers:
           cat crash.json | xcode-llm --synthesize

        4. Battle test with pipeline:
           xcode-llm --battle --pipeline

        WHAT --pipeline ADDS:
            - Parallel frame relevance scoring
            - Variable suspicion detection
            - Code pattern analysis
            - Cross-referenced synthesis
            - Preliminary hypothesis before final analysis
            - Metrics (frames scored, patterns found, token estimate)

        EXAMPLES:
            # Quick crash diagnosis
            echo '{"frames":[{"function":"foo","index":0}]}' | xcode-llm

            # Deep analysis with scoring pipeline
            cat complex_crash.json | xcode-llm --pipeline

            # See what the scorers find
            cat crash.json | xcode-llm --synthesize

            # Battle test: generate crash, analyze with pipeline
            xcode-llm --battle --pipeline

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
