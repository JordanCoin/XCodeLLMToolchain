import Foundation
import FoundationModels

/// Scores variables for suspicious values that might indicate crash cause.
/// Looks for nil optionals, dangling pointers, invalid values, etc.
public actor VariableScorer {
    private let config: ScoringPipelineConfig

    public init(config: ScoringPipelineConfig = .default) {
        self.config = config
    }

    /// Score all variables across relevant frames
    public func scoreVariables(
        frames: [CrashFrame],
        frameScores: [FrameScore],
        crashContext: String
    ) async throws -> [VariableScore] {
        // Only analyze variables from high-relevance frames
        let relevantFrameIndices = Set(
            frameScores
                .filter { $0.relevanceScore >= config.frameRelevanceThreshold }
                .map { $0.frameIndex }
        )

        // Collect variables from relevant frames
        var variablesToScore: [(frameIndex: Int, variable: FrameVariable)] = []

        for frame in frames where relevantFrameIndices.contains(frame.index) {
            guard let vars = frame.variables else { continue }

            // Pre-filter: prioritize suspicious-looking variables
            let prioritized = prioritizeVariables(vars)
            for v in prioritized.prefix(config.maxVariablesPerFrame) {
                variablesToScore.append((frame.index, v))
            }
        }

        guard !variablesToScore.isEmpty else {
            return []  // No variables to score is valid
        }

        // Batch score all variables together (they need cross-referencing)
        return try await scoreVariableBatch(variablesToScore, crashContext: crashContext)
    }

    /// Pre-filter and prioritize variables by suspiciousness heuristics
    private func prioritizeVariables(_ variables: [FrameVariable]) -> [FrameVariable] {
        // Score by heuristics first, then let LLM do deep analysis
        let scored = variables.map { v -> (variable: FrameVariable, priority: Int) in
            var priority = 0

            // Nil/None indicators
            if let value = v.value?.lowercased() {
                if value.contains("nil") || value == "none" || value == "null" {
                    priority += 10
                }
                if value.contains("0x0") || value == "0" {
                    priority += 5
                }
                if value.contains("invalid") || value.contains("corrupt") {
                    priority += 8
                }
            }

            if let summary = v.summary?.lowercased() {
                if summary.contains("nil") || summary.contains("none") {
                    priority += 10
                }
                if summary.contains("invalid") {
                    priority += 5
                }
            }

            // Type-based suspicion
            if let type = v.type?.lowercased() {
                if type.contains("optional") || type.contains("?") {
                    priority += 3
                }
                if type.contains("unsafe") || type.contains("pointer") {
                    priority += 4
                }
                if type.contains("unowned") || type.contains("weak") {
                    priority += 3
                }
            }

            // Name-based hints
            let name = v.name.lowercased()
            if name.contains("self") || name.contains("this") {
                priority += 2
            }
            if name.contains("result") || name.contains("value") {
                priority += 1
            }

            return (v, priority)
        }

        return scored
            .sorted { $0.priority > $1.priority }
            .map { $0.variable }
    }

    /// Score a batch of variables using LLM
    private func scoreVariableBatch(
        _ variables: [(frameIndex: Int, variable: FrameVariable)],
        crashContext: String
    ) async throws -> [VariableScore] {
        let session = LanguageModelSession(instructions: makeVariableScorerInstructions())

        let prompt = buildVariablePrompt(variables: variables, crashContext: crashContext)

        let response = try await session.respond(to: prompt, generating: VariableScoreBatch.self)
        return response.content.scores
    }

    /// Build prompt for variable scoring
    private func buildVariablePrompt(
        variables: [(frameIndex: Int, variable: FrameVariable)],
        crashContext: String
    ) -> String {
        var prompt = "Crash: \(crashContext)\n\nAnalyze these variables for suspicious values:\n\n"

        for (frameIdx, v) in variables {
            prompt += "[\(v.name)] in frame \(frameIdx)\n"
            prompt += "  type: \(v.type ?? "unknown")\n"
            prompt += "  value: \(v.value ?? "?")\n"
            if let summary = v.summary {
                prompt += "  summary: \(summary)\n"
            }
            prompt += "\n"
        }

        return prompt
    }
}

// MARK: - Instructions

private func makeVariableScorerInstructions() -> Instructions {
    Instructions {
        "You analyze variable values for crash-related issues. Be precise."
        "High suspicion (0.8-1.0): nil where non-nil expected, dangling pointers, corrupt data."
        "Medium suspicion (0.4-0.7): edge values, potential type issues, uninitialized."
        "Low suspicion (0.0-0.3): normal values unlikely to cause crash."
        "Categorize each issue type accurately. Keep observation under 10 words."
    }
}
