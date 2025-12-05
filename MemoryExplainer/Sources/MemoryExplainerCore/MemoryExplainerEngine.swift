import Foundation
import FoundationModels

/// Core engine for memory/crash explanation using structured output and tool calling.
/// Uses Instructions for consistent behavior, @Generable for type-safe output.
public struct MemoryExplainerEngine {
    private let tools: [any Tool]

    public init(enableTools: Bool = false) {
        self.tools = enableTools ? [ReadSourceTool(), CodeMapTool()] : []
    }

    // MARK: - Crash Analysis

    /// Explain a crash with structured output.
    /// Prompt is minimal - @Guide descriptions do the heavy lifting.
    public func explainCrashStructured(json: String, codemapContext: String = "") async throws -> CrashExplanation {
        let context = codemapContext.isEmpty ? "" : "\n\nCode context:\n\(String(codemapContext.prefix(600)))"

        let session = LanguageModelSession(instructions: makeCrashInstructions())
        let response = try await session.respond(
            to: "Analyze:\n\(json)\(context)",
            generating: CrashExplanation.self
        )
        return response.content
    }

    /// Explain a crash with tools - model can read source files.
    public func explainCrashWithTools(json: String, projectPath: String) async throws -> CrashExplanation {
        let session = LanguageModelSession(
            tools: [ReadSourceTool(), CodeMapTool()],
            instructions: makeCrashInstructionsWithTools()
        )
        let response = try await session.respond(
            to: "Analyze crash in project \(projectPath):\n\(json)",
            generating: CrashExplanation.self
        )
        return response.content
    }

    // MARK: - Memory Analysis

    /// Explain memory with structured output.
    public func explainMemoryStructured(json: String) async throws -> MemoryExplanation {
        let session = LanguageModelSession(instructions: makeMemoryInstructions())
        let response = try await session.respond(
            to: "Analyze:\n\(json)",
            generating: MemoryExplanation.self
        )
        return response.content
    }

    // MARK: - Generic Analysis

    /// Generic explanation with structured output.
    public func explainGenericStructured(json: String, context: String = "") async throws -> GenericExplanation {
        let ctx = context.isEmpty ? "" : "\n\nContext:\n\(String(context.prefix(500)))"

        let session = LanguageModelSession()
        let response = try await session.respond(
            to: "Analyze this iOS/macOS data:\n\(json)\(ctx)",
            generating: GenericExplanation.self
        )
        return response.content
    }

    // MARK: - Legacy String Methods (CLI compatibility)

    public func explainCrash(json: String, codemapContext: String = "") async throws -> String {
        let result = try await explainCrashStructured(json: json, codemapContext: codemapContext)
        return formatCrashExplanation(result)
    }

    public func explainMemory(json: String) async throws -> String {
        let result = try await explainMemoryStructured(json: json)
        return formatMemoryExplanation(result)
    }

    public func explainGeneric(json: String, context: String = "") async throws -> String {
        let result = try await explainGenericStructured(json: json, context: context)
        return formatGenericExplanation(result)
    }

    // MARK: - Crash Generation

    /// Generate a realistic crash scenario.
    public func generateCrash(scenario: String = "") async throws -> GeneratedCrash {
        let prompt = scenario.isEmpty
            ? "Generate a tricky iOS/macOS crash scenario."
            : "Generate crash scenario: \(scenario)"

        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt, generating: GeneratedCrash.self)
        return response.content
    }

    /// Generate and explain (model vs model).
    public func battleTest(scenario: String = "") async throws -> (crash: GeneratedCrash, explanation: CrashExplanation) {
        let crash = try await generateCrash(scenario: scenario)
        guard let jsonString = crash.toJSONString() else {
            throw NSError(domain: "MemoryExplainer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Serialization failed"])
        }
        let explanation = try await explainCrashStructured(json: jsonString)
        return (crash, explanation)
    }

    // MARK: - Formatting

    private func formatCrashExplanation(_ e: CrashExplanation) -> String {
        """
        **Crash Type:** \(e.crashType)
        **Faulty Function:** `\(e.faultyFunction)`
        **Root Cause:** \(e.rootCause)
        **Fix:** \(e.suggestedFix)
        **Confidence:** \(e.confidence)
        """
    }

    private func formatMemoryExplanation(_ e: MemoryExplanation) -> String {
        """
        **Concerning:** \(e.isConcerning ? "Yes" : "No")
        **Severity:** \(e.severity)
        **Issue:** \(e.biggestIssue)
        **Fix:** \(e.suggestedFix)
        """
    }

    private func formatGenericExplanation(_ e: GenericExplanation) -> String {
        var lines = ["**Summary:** \(e.summary)"]
        if let concern = e.concern { lines.append("**Concern:** \(concern)") }
        if let rec = e.recommendation { lines.append("**Recommendation:** \(rec)") }
        return lines.joined(separator: "\n")
    }
}
