import Foundation

public struct MemoryExplainerEngine {
    private let llm: LLMClient

    public init(llm: LLMClient = FoundationModelClient()) {
        self.llm = llm
    }

    public func explainCrash(json: String, codemapContext: String) async throws -> String {
        let prompt = """
        You are an expert iOS/macOS debugger. Analyze this crash and explain it clearly.

        Focus on:
        1. What type of error occurred (EXC_BAD_ACCESS, SIGABRT, etc.)
        2. Where it happened (function, file, line)
        3. The likely root cause based on the stack trace
        4. Specific steps to fix it

        CRASH DATA:
        \(json)

        CODE CONTEXT (from codemap - shows file dependencies):
        \(codemapContext.isEmpty ? "Not available" : codemapContext)

        Provide a clear, actionable explanation:
        """

        return try await llm.respond(to: prompt)
    }

    public func explainMemory(json: String, codemapContext: String) async throws -> String {
        let prompt = """
        You are an expert iOS/macOS performance engineer. Analyze this memory usage data.

        Focus on:
        1. Which classes/types are using the most memory
        2. Potential memory leaks or retention issues
        3. Classes with suspiciously high instance counts
        4. Specific recommendations to reduce memory usage

        MEMORY DATA:
        \(json)

        CODE CONTEXT (from codemap - shows file dependencies and structure):
        \(codemapContext.isEmpty ? "Not available" : codemapContext)

        If codemap context is available, explain:
        - Which files create these objects
        - Where they might be retained unexpectedly
        - Architectural issues that could cause accumulation

        Provide a clear analysis with specific recommendations:
        """

        return try await llm.respond(to: prompt)
    }

    public func explainGeneric(json: String, codemapContext: String) async throws -> String {
        let prompt = """
        You are an expert iOS/macOS developer. Analyze this debugging data.

        DATA:
        \(json)

        CODE CONTEXT:
        \(codemapContext.isEmpty ? "Not available" : codemapContext)

        Explain what this shows and provide recommendations:
        """

        return try await llm.respond(to: prompt)
    }
}
