import Foundation
import FoundationModels

// MARK: - Crash Explanation (Output)

/// Structured crash explanation - constrained decoding prevents hallucination.
/// Property order: independent fields first, summaries/analysis last.
@Generable
public struct CrashExplanation {
    @Guide(description: "The function name from the crash frames where the bug originated")
    public var faultyFunction: String

    @Guide(description: "Category of crash", .anyOf([
        "null_pointer", "force_unwrap_nil", "use_after_free", "array_out_of_bounds",
        "type_cast_failure", "unowned_dealloc", "race_condition", "stack_overflow",
        "assertion_failure", "memory_corruption", "division_by_zero", "other"
    ]))
    public var crashType: String

    @Guide(description: "Confidence in diagnosis", .anyOf(["low", "medium", "high"]))
    public var confidence: String

    // Summaries/analysis last (depend on above fields)
    @Guide(description: "One sentence explaining why this crash happened")
    public var rootCause: String

    @Guide(description: "One concrete action to fix the bug")
    public var suggestedFix: String
}

// MARK: - Memory Explanation (Output)

/// Structured memory analysis with constrained severity levels.
@Generable
public struct MemoryExplanation {
    @Guide(description: "Is this memory usage concerning?")
    public var isConcerning: Bool

    @Guide(description: "Memory health assessment", .anyOf(["healthy", "warning", "critical"]))
    public var severity: String

    // Analysis last
    @Guide(description: "The biggest memory issue identified, in one sentence")
    public var biggestIssue: String

    @Guide(description: "One concrete action to reduce memory usage")
    public var suggestedFix: String
}

// MARK: - Generic Explanation (Output)

/// For non-specific analysis requests.
@Generable
public struct GenericExplanation {
    @Guide(description: "Brief summary of what the data shows")
    public var summary: String

    @Guide(description: "Key concern or notable finding, if any")
    public var concern: String?

    @Guide(description: "Recommended action, if any")
    public var recommendation: String?
}

// MARK: - Instructions (functions to avoid Sendable issues)

/// Creates instructions for crash analysis sessions.
public func makeCrashInstructions() -> Instructions {
    Instructions {
        "You are an expert iOS/macOS crash debugger. Analyze crash data precisely."
        "Only reference functions, files, and variables that appear in the provided data."
        "Be concise. One sentence per field."
    }
}

/// Creates instructions for crash analysis with tools.
public func makeCrashInstructionsWithTools() -> Instructions {
    Instructions {
        "You are an expert iOS/macOS crash debugger with access to tools."
        "Use read_source to examine code around crash lines when file paths are provided."
        "Use get_dependencies to understand how files connect."
        "Only reference actual data - never invent function or file names."
    }
}

/// Creates instructions for memory analysis.
public func makeMemoryInstructions() -> Instructions {
    Instructions {
        "You are an expert iOS/macOS memory debugger."
        "Focus on allocation counts, sizes, and potential leaks."
        "Be concise and actionable."
    }
}
