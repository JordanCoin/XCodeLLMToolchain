import Foundation

/// Core engine for memory/crash explanation. Token-conscious for Foundation Models (4096 limit).
public struct MemoryExplainerEngine {
    private let llm: LLMClient

    public init(llm: LLMClient = FoundationModelClient()) {
        self.llm = llm
    }

    /// Explain a crash. Codemap context is useful here for understanding what touches the crash site.
    public func explainCrash(json: String, codemapContext: String = "") async throws -> String {
        // Truncate context to stay under token limit
        let context = codemapContext.count > 800 ? String(codemapContext.prefix(800)) + "..." : codemapContext

        let prompt = """
        Expert iOS/macOS debugger. Analyze this crash concisely.

        CRASH:
        \(json)
        \(context.isEmpty ? "" : "\nCODE CONTEXT:\n\(context)")

        In 3-5 sentences: What happened, why, and how to fix it.
        """

        return try await llm.respond(to: prompt)
    }

    /// Explain memory usage. No codemap - allocation data is more valuable here.
    public func explainMemory(json: String) async throws -> String {
        let prompt = """
        Expert iOS/macOS memory debugger. Analyze this data concisely.

        \(json)

        In 2-4 sentences: Is this concerning? Biggest issue? One fix.
        """

        return try await llm.respond(to: prompt)
    }

    /// Generic explanation with optional context.
    public func explainGeneric(json: String, context: String = "") async throws -> String {
        let trimmedContext = context.count > 500 ? String(context.prefix(500)) + "..." : context

        let prompt = """
        Expert iOS/macOS developer. Analyze this data.

        \(json)
        \(trimmedContext.isEmpty ? "" : "\nCONTEXT:\n\(trimmedContext)")

        Brief explanation and recommendations.
        """

        return try await llm.respond(to: prompt)
    }
}
