import Foundation
import FoundationModels

/// Scores stack frames for relevance to crash origin.
/// Runs in parallel - each frame (or small batch) scored independently.
public actor FrameScorer {
    private let config: ScoringPipelineConfig

    public init(config: ScoringPipelineConfig = .default) {
        self.config = config
    }

    /// Score all frames in parallel, returning relevance scores
    public func scoreFrames(
        frames: [CrashFrame],
        crashContext: String
    ) async throws -> [FrameScore] {
        // Pre-filter: prioritize user frames, limit total
        let framesToScore = filterFramesForScoring(frames)

        guard !framesToScore.isEmpty else {
            throw ScoringError.noFramesToScore
        }

        // Score frames in parallel batches for efficiency
        // Group into batches of ~3 frames each to balance parallelism vs token efficiency
        let batchSize = 3
        let batches = stride(from: 0, to: framesToScore.count, by: batchSize).map { startIdx in
            Array(framesToScore[startIdx..<min(startIdx + batchSize, framesToScore.count)])
        }

        // Run batches in parallel
        return try await withThrowingTaskGroup(of: [FrameScore].self) { group in
            for batch in batches {
                group.addTask {
                    try await self.scoreBatch(batch, crashContext: crashContext)
                }
            }

            var allScores: [FrameScore] = []
            for try await batchScores in group {
                allScores.append(contentsOf: batchScores)
            }

            // Sort by frame index for consistent ordering
            return allScores.sorted { $0.frameIndex < $1.frameIndex }
        }
    }

    /// Pre-filter frames to reduce scoring load
    private func filterFramesForScoring(_ frames: [CrashFrame]) -> [CrashFrame] {
        // Always include first N frames (closest to crash)
        let nearCrashCount = min(5, config.maxFramesToScore)
        let nearCrash = frames.prefix(nearCrashCount)

        // Include non-system frames up to our limit
        let remainingSlots = max(0, config.maxFramesToScore - nearCrashCount)
        let userFrames = frames.dropFirst(nearCrashCount).filter { !$0.isSystem }

        // Combine and limit
        let combined = Array(nearCrash) + Array(userFrames.prefix(remainingSlots))
        return Array(combined.prefix(config.maxFramesToScore))
    }

    /// Score a batch of frames
    private func scoreBatch(
        _ frames: [CrashFrame],
        crashContext: String
    ) async throws -> [FrameScore] {
        let session = LanguageModelSession(instructions: makeFrameScorerInstructions())

        let prompt = buildBatchPrompt(frames: frames, crashContext: crashContext)

        let response = try await session.respond(to: prompt, generating: FrameScoreBatch.self)
        return response.content.scores
    }

    /// Build prompt for batch scoring
    private func buildBatchPrompt(frames: [CrashFrame], crashContext: String) -> String {
        var prompt = "Crash context: \(crashContext)\n\nScore these stack frames for crash relevance:\n\n"

        for frame in frames {
            prompt += "Frame \(frame.index): \(frame.function)"
            if let module = frame.module {
                prompt += " [\(module)]"
            }
            if let file = frame.file, let line = frame.line {
                prompt += " at \(file):\(line)"
            }
            if frame.isSystem {
                prompt += " (system)"
            }
            prompt += "\n"

            // Include variables summary if present
            if let vars = frame.variables, !vars.isEmpty {
                let varSummary = vars.prefix(5).map { v in
                    "\(v.name): \(v.value ?? v.summary ?? "?")"
                }.joined(separator: ", ")
                prompt += "  vars: \(varSummary)\n"
            }
        }

        return prompt
    }
}

// MARK: - Instructions

/// Instructions for frame scoring - focused and minimal
private func makeFrameScorerInstructions() -> Instructions {
    Instructions {
        "You score stack frames for crash relevance. Be precise and fast."
        "Higher scores for: user code, frames near crash, functions with unsafe operations."
        "Lower scores for: system libraries, runtime internals, generic wrappers."
        "Set isBugOrigin=true only for the frame most likely containing the actual bug."
        "Keep reasoning under 15 words."
    }
}
