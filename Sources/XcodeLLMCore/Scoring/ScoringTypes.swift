import Foundation
import FoundationModels

// MARK: - Input Types (parsed from raw crash JSON)

/// Parsed frame from crash data for scoring
public struct CrashFrame: Codable, Sendable {
    public let index: Int
    public let function: String
    public let module: String?
    public let file: String?
    public let line: Int?
    public let isSystem: Bool
    public let variables: [CapturedVariable]?

    public init(index: Int, function: String, module: String?, file: String?, line: Int?, isSystem: Bool, variables: [CapturedVariable]?) {
        self.index = index
        self.function = function
        self.module = module
        self.file = file
        self.line = line
        self.isSystem = isSystem
        self.variables = variables
    }
}

/// Variable captured at a frame (for scoring pipeline)
public struct CapturedVariable: Codable, Sendable {
    public let name: String
    public let type: String?
    public let value: String?
    public let summary: String?

    public init(name: String, type: String?, value: String?, summary: String?) {
        self.name = name
        self.type = type
        self.value = value
        self.summary = summary
    }
}

/// Parsed crash data ready for scoring pipeline
public struct ParsedCrashData: Codable, Sendable {
    public let stopDescription: String
    public let stopReasonType: String
    public let crashType: String?
    public let faultAddress: String?
    public let frames: [CrashFrame]

    public init(stopDescription: String, stopReasonType: String, crashType: String?, faultAddress: String?, frames: [CrashFrame]) {
        self.stopDescription = stopDescription
        self.stopReasonType = stopReasonType
        self.crashType = crashType
        self.faultAddress = faultAddress
        self.frames = frames
    }

    /// Parse from raw JSON crash data
    public static func parse(from json: String) throws -> ParsedCrashData {
        guard let data = json.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScoringError.invalidJSON
        }

        let frames: [CrashFrame] = (dict["frames"] as? [[String: Any]] ?? []).compactMap { frameDict in
            guard let index = frameDict["index"] as? Int,
                  let function = frameDict["function"] as? String else { return nil }

            let variables: [CapturedVariable]? = (frameDict["variables"] as? [[String: Any]])?.compactMap { varDict in
                guard let name = varDict["name"] as? String else { return nil }
                return CapturedVariable(
                    name: name,
                    type: varDict["type"] as? String,
                    value: varDict["value"] as? String,
                    summary: varDict["summary"] as? String
                )
            }

            return CrashFrame(
                index: index,
                function: function,
                module: frameDict["module"] as? String,
                file: frameDict["file"] as? String,
                line: frameDict["line"] as? Int,
                isSystem: frameDict["is_system"] as? Bool ?? false,
                variables: variables
            )
        }

        return ParsedCrashData(
            stopDescription: dict["stop_description"] as? String ?? "",
            stopReasonType: dict["stop_reason_type"] as? String ?? "unknown",
            crashType: dict["crash_type"] as? String,
            faultAddress: dict["fault_address"] as? String,
            frames: frames
        )
    }
}

// MARK: - Scorer Output Types

/// Output from frame relevance scoring
@Generable
public struct FrameScore: Sendable {
    @Guide(description: "Index of the frame being scored")
    public var frameIndex: Int

    @Guide(description: "Relevance score from 0.0 (irrelevant) to 1.0 (definitely the crash site)")
    public var relevanceScore: Double

    @Guide(description: "Is this user code (true) or system/library code (false)")
    public var isUserCode: Bool

    @Guide(description: "Does this frame likely contain the bug origin")
    public var isBugOrigin: Bool

    @Guide(description: "Brief reason for the score, max 15 words")
    public var reasoning: String
}

/// Output from variable analysis scoring
@Generable
public struct VariableScore: Sendable {
    @Guide(description: "Name of the variable")
    public var variableName: String

    @Guide(description: "Frame index where this variable appears")
    public var frameIndex: Int

    @Guide(description: "Suspicion score from 0.0 (normal) to 1.0 (definitely problematic)")
    public var suspicionScore: Double

    @Guide(description: "Category of issue", .anyOf([
        "nil_optional", "dangling_pointer", "invalid_value", "uninitialized",
        "type_mismatch", "boundary_violation", "normal"
    ]))
    public var issueCategory: String

    @Guide(description: "What makes this variable suspicious, max 10 words")
    public var observation: String
}

/// Output from code context pattern scoring
@Generable
public struct ContextScore: Sendable {
    @Guide(description: "File path being analyzed")
    public var filePath: String

    @Guide(description: "Pattern detected in code", .anyOf([
        "force_unwrap", "unsafe_cast", "array_subscript", "unowned_reference",
        "implicit_unwrap", "try_force", "unchecked_arithmetic", "raw_pointer",
        "callback_retain_cycle", "none"
    ]))
    public var patternDetected: String

    @Guide(description: "Confidence this pattern relates to crash 0.0-1.0")
    public var patternConfidence: Double

    @Guide(description: "The specific code construct, e.g., 'value!' or 'array[index]'")
    public var codeConstruct: String?
}

/// Batch of frame scores (for parallel scoring efficiency)
@Generable
public struct FrameScoreBatch: Sendable {
    @Guide(description: "Scores for each analyzed frame")
    public var scores: [FrameScore]
}

/// Batch of variable scores
@Generable
public struct VariableScoreBatch: Sendable {
    @Guide(description: "Scores for each analyzed variable")
    public var scores: [VariableScore]
}

// MARK: - Synthesizer Types

/// Input to synthesizer - aggregates all scorer outputs
public struct ScorerOutputs: Sendable {
    public let crashData: ParsedCrashData
    public let frameScores: [FrameScore]
    public let variableScores: [VariableScore]
    public let contextScores: [ContextScore]
    public let codeSnippets: [String: String]  // filePath -> code

    public init(
        crashData: ParsedCrashData,
        frameScores: [FrameScore],
        variableScores: [VariableScore],
        contextScores: [ContextScore],
        codeSnippets: [String: String]
    ) {
        self.crashData = crashData
        self.frameScores = frameScores
        self.variableScores = variableScores
        self.contextScores = contextScores
        self.codeSnippets = codeSnippets
    }
}

/// Synthesized high-signal context for final analysis
@Generable
public struct SynthesizedContext: Sendable {
    @Guide(description: "Frame indices ordered by relevance, most important first, max 5")
    public var relevantFrameIndices: [Int]

    @Guide(description: "Variable names that are suspicious and should be investigated")
    public var suspiciousVariables: [String]

    @Guide(description: "Most likely crash pattern based on scorer evidence", .anyOf([
        "nil_dereference", "force_unwrap", "array_bounds", "type_cast",
        "memory_corruption", "use_after_free", "race_condition", "unknown"
    ]))
    public var likelyCrashPattern: String

    @Guide(description: "Preliminary hypothesis of what went wrong, 1-2 sentences max")
    public var preliminaryHypothesis: String

    @Guide(description: "Key evidence points that led to this hypothesis, max 3 items")
    public var keyEvidence: [String]

    @Guide(description: "Confidence in hypothesis 0.0-1.0")
    public var hypothesisConfidence: Double
}

// MARK: - Pipeline Configuration

/// Configuration for the scoring pipeline
public struct ScoringPipelineConfig: Sendable {
    /// Maximum frames to score (others filtered by heuristics)
    public let maxFramesToScore: Int

    /// Maximum variables to analyze per frame
    public let maxVariablesPerFrame: Int

    /// Minimum relevance score to include frame in synthesis
    public let frameRelevanceThreshold: Double

    /// Minimum suspicion score to include variable in synthesis
    public let variableSuspicionThreshold: Double

    /// Lines of code context to read around crash lines
    public let codeContextLines: Int

    public static let `default` = ScoringPipelineConfig(
        maxFramesToScore: 15,
        maxVariablesPerFrame: 10,
        frameRelevanceThreshold: 0.3,
        variableSuspicionThreshold: 0.4,
        codeContextLines: 10
    )

    public init(
        maxFramesToScore: Int = 15,
        maxVariablesPerFrame: Int = 10,
        frameRelevanceThreshold: Double = 0.3,
        variableSuspicionThreshold: Double = 0.4,
        codeContextLines: Int = 10
    ) {
        self.maxFramesToScore = maxFramesToScore
        self.maxVariablesPerFrame = maxVariablesPerFrame
        self.frameRelevanceThreshold = frameRelevanceThreshold
        self.variableSuspicionThreshold = variableSuspicionThreshold
        self.codeContextLines = codeContextLines
    }
}

// MARK: - Errors

public enum ScoringError: Error, LocalizedError {
    case invalidJSON
    case noFramesToScore
    case scoringFailed(String)
    case synthesisFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Failed to parse crash JSON"
        case .noFramesToScore: return "No frames available to score"
        case .scoringFailed(let msg): return "Scoring failed: \(msg)"
        case .synthesisFailed(let msg): return "Synthesis failed: \(msg)"
        }
    }
}
