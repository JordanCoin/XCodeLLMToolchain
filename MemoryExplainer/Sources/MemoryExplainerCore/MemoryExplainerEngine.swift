import Foundation
import FoundationModels

/// Core engine for memory/crash explanation using structured output.
public struct MemoryExplainerEngine {

    public init() {}

    /// Explain a crash with structured output - prevents hallucination via constrained decoding.
    public func explainCrashStructured(json: String, codemapContext: String = "") async throws -> CrashExplanation {
        let context = codemapContext.count > 600 ? String(codemapContext.prefix(600)) + "..." : codemapContext

        let prompt = """
        Analyze this iOS/macOS crash. Only reference functions/files shown in the data.

        CRASH DATA:
        \(json)
        \(context.isEmpty ? "" : "\nCODE CONTEXT:\n\(context)")
        """

        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt, generating: CrashExplanation.self)
        return response.content
    }

    /// Explain memory with structured output.
    public func explainMemoryStructured(json: String) async throws -> MemoryExplanation {
        let prompt = """
        Analyze this iOS/macOS memory data.

        \(json)
        """

        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt, generating: MemoryExplanation.self)
        return response.content
    }

    // MARK: - Legacy string-based methods (for CLI compatibility)

    /// Explain a crash (returns formatted string).
    public func explainCrash(json: String, codemapContext: String = "") async throws -> String {
        let result = try await explainCrashStructured(json: json, codemapContext: codemapContext)
        return formatCrashExplanation(result)
    }

    /// Explain memory (returns formatted string).
    public func explainMemory(json: String) async throws -> String {
        let result = try await explainMemoryStructured(json: json)
        return formatMemoryExplanation(result)
    }

    /// Generic explanation (still uses freeform for flexibility).
    public func explainGeneric(json: String, context: String = "") async throws -> String {
        let trimmedContext = context.count > 500 ? String(context.prefix(500)) + "..." : context

        let prompt = """
        Expert iOS/macOS developer. Analyze this data briefly.

        \(json)
        \(trimmedContext.isEmpty ? "" : "\nCONTEXT:\n\(trimmedContext)")
        """

        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }

    // MARK: - Formatting

    private func formatCrashExplanation(_ e: CrashExplanation) -> String {
        """
        **Crash Type:** \(e.crashType)
        **Faulty Function:** `\(e.faultyFunction)`
        **Root Cause:** \(e.rootCause)
        **Fix:** \(e.suggestedFix)
        **Confidence:** \(e.confidence.rawValue)
        """
    }

    private func formatMemoryExplanation(_ e: MemoryExplanation) -> String {
        """
        **Concerning:** \(e.isConcerning ? "Yes" : "No")
        **Severity:** \(e.severity.rawValue)
        **Issue:** \(e.biggestIssue)
        **Fix:** \(e.suggestedFix)
        """
    }
}
