import Foundation
import FoundationModels

/// Structured crash explanation - constrained decoding prevents hallucination
@Generable
public struct CrashExplanation {
    @Guide(description: "One sentence: what type of crash occurred (e.g., null pointer, use-after-free, force unwrap nil)")
    public var crashType: String

    @Guide(description: "The specific function name from the crash frames where the bug likely originated. Must be from the provided data.")
    public var faultyFunction: String

    @Guide(description: "One sentence explaining why this crash happened")
    public var rootCause: String

    @Guide(description: "One concrete action to fix the bug")
    public var suggestedFix: String

    @Guide(description: "Confidence in diagnosis: low, medium, or high")
    public var confidence: Confidence
}

@Generable
public enum Confidence: String {
    case low
    case medium
    case high
}

/// Structured memory analysis
@Generable
public struct MemoryExplanation {
    @Guide(description: "Is this memory usage concerning? yes or no")
    public var isConcerning: Bool

    @Guide(description: "The biggest memory issue identified, in one sentence")
    public var biggestIssue: String

    @Guide(description: "One concrete action to reduce memory usage")
    public var suggestedFix: String

    @Guide(description: "Memory health: healthy, warning, or critical")
    public var severity: MemorySeverity
}

@Generable
public enum MemorySeverity: String {
    case healthy
    case warning
    case critical
}
