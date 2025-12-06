import Foundation
import FoundationModels

/// Orchestrates the multi-layer scoring pipeline.
///
/// Flow:
/// 1. Parse raw crash JSON
/// 2. Run scorers in parallel (frames, variables, context)
/// 3. Synthesize into high-signal context
/// 4. Final analysis with structured output
///
/// This reduces token usage while improving signal quality.
public actor ScoringPipeline {
    private let config: ScoringPipelineConfig
    private let frameScorer: FrameScorer
    private let variableScorer: VariableScorer
    private let contextScorer: ContextScorer
    private let synthesizer: Synthesizer

    /// Metrics from the last pipeline run
    public struct PipelineMetrics: Sendable {
        public let framesScored: Int
        public let variablesScored: Int
        public let patternsFound: Int
        public let synthesisConfidence: Double
        public let totalTokensEstimate: Int

        public var description: String {
            """
            Pipeline Metrics:
              Frames scored: \(framesScored)
              Variables analyzed: \(variablesScored)
              Patterns found: \(patternsFound)
              Synthesis confidence: \(String(format: "%.0f%%", synthesisConfidence * 100))
              Est. tokens used: ~\(totalTokensEstimate)
            """
        }
    }

    public init(config: ScoringPipelineConfig = .default) {
        self.config = config
        self.frameScorer = FrameScorer(config: config)
        self.variableScorer = VariableScorer(config: config)
        self.contextScorer = ContextScorer(config: config)
        self.synthesizer = Synthesizer(config: config)
    }

    /// Run the full scoring pipeline and return final analysis
    public func analyze(json: String) async throws -> (
        explanation: CrashExplanation,
        synthesis: SynthesizedContext,
        metrics: PipelineMetrics
    ) {
        // Step 1: Parse crash data
        let crashData = try ParsedCrashData.parse(from: json)
        let crashContext = "\(crashData.stopDescription) (\(crashData.crashType ?? crashData.stopReasonType))"

        // Step 2: Run scorers in parallel
        async let frameScoresTask = frameScorer.scoreFrames(
            frames: crashData.frames,
            crashContext: crashContext
        )

        // Frame scores needed for variable and context scoring - get them first
        let frameScores = try await frameScoresTask

        // Now run variable and context scoring in parallel
        async let variableScoresTask = variableScorer.scoreVariables(
            frames: crashData.frames,
            frameScores: frameScores,
            crashContext: crashContext
        )

        async let contextScoresTask = contextScorer.scoreContext(
            frames: crashData.frames,
            frameScores: frameScores,
            crashContext: crashContext
        )

        let variableScores = try await variableScoresTask
        let (contextScores, codeSnippets) = try await contextScoresTask

        // Step 3: Synthesize
        let scorerOutputs = ScorerOutputs(
            crashData: crashData,
            frameScores: frameScores,
            variableScores: variableScores,
            contextScores: contextScores,
            codeSnippets: codeSnippets
        )

        let synthesis = try await synthesizer.synthesize(outputs: scorerOutputs)

        // Step 4: Final analysis with synthesized context
        let explanation = try await finalAnalysis(
            synthesis: synthesis,
            crashData: crashData,
            codeSnippets: codeSnippets
        )

        // Compute metrics
        let metrics = PipelineMetrics(
            framesScored: frameScores.count,
            variablesScored: variableScores.count,
            patternsFound: contextScores.filter { $0.patternDetected != "none" }.count,
            synthesisConfidence: synthesis.hypothesisConfidence,
            totalTokensEstimate: estimateTokens(
                frameScores: frameScores.count,
                variableScores: variableScores.count,
                contextScores: contextScores.count
            )
        )

        return (explanation, synthesis, metrics)
    }

    /// Run only synthesis (for debugging/inspection)
    public func synthesizeOnly(json: String) async throws -> (
        synthesis: SynthesizedContext,
        outputs: ScorerOutputs
    ) {
        let crashData = try ParsedCrashData.parse(from: json)
        let crashContext = "\(crashData.stopDescription) (\(crashData.crashType ?? crashData.stopReasonType))"

        // Run all scorers
        let frameScores = try await frameScorer.scoreFrames(
            frames: crashData.frames,
            crashContext: crashContext
        )

        async let variableScoresTask = variableScorer.scoreVariables(
            frames: crashData.frames,
            frameScores: frameScores,
            crashContext: crashContext
        )

        async let contextScoresTask = contextScorer.scoreContext(
            frames: crashData.frames,
            frameScores: frameScores,
            crashContext: crashContext
        )

        let variableScores = try await variableScoresTask
        let (contextScores, codeSnippets) = try await contextScoresTask

        let outputs = ScorerOutputs(
            crashData: crashData,
            frameScores: frameScores,
            variableScores: variableScores,
            contextScores: contextScores,
            codeSnippets: codeSnippets
        )

        let synthesis = try await synthesizer.synthesize(outputs: outputs)

        return (synthesis, outputs)
    }

    /// Final analysis using synthesized context
    private func finalAnalysis(
        synthesis: SynthesizedContext,
        crashData: ParsedCrashData,
        codeSnippets: [String: String]
    ) async throws -> CrashExplanation {
        let session = LanguageModelSession(instructions: makeFinalAnalysisInstructions())

        // Format the synthesized context for analysis
        let context = synthesis.formatForAnalysis(crashData: crashData, codeSnippets: codeSnippets)

        let response = try await session.respond(
            to: "Analyze this pre-scored crash:\n\n\(context)",
            generating: CrashExplanation.self
        )

        return response.content
    }

    /// Estimate tokens used across pipeline
    private func estimateTokens(
        frameScores: Int,
        variableScores: Int,
        contextScores: Int
    ) -> Int {
        // Rough estimates based on typical prompt/response sizes
        let frameTokens = (frameScores / 3 + 1) * 800  // ~800 tokens per batch of 3
        let variableTokens = variableScores > 0 ? 1200 : 0  // ~1200 for variable batch
        let contextTokens = contextScores * 600  // ~600 per file analyzed
        let synthesisTokens = 2000  // ~2000 for synthesis
        let finalTokens = 1500  // ~1500 for final analysis (now smaller input!)

        return frameTokens + variableTokens + contextTokens + synthesisTokens + finalTokens
    }
}

// MARK: - Final Analysis Instructions

private func makeFinalAnalysisInstructions() -> Instructions {
    Instructions {
        "You receive pre-scored crash evidence with a preliminary hypothesis."
        "The hypothesis and evidence are from prior analysis - use them as strong signals."
        "Validate or refine the hypothesis based on the evidence."
        "Be precise: reference specific functions and variables from the data."
        "If evidence strongly supports the hypothesis, match your analysis to it."
        "If evidence contradicts the hypothesis, explain why and provide alternative."
    }
}

// MARK: - Convenience Extensions

extension ScoringPipeline {
    /// Analyze and return formatted string (for CLI compatibility)
    public func analyzeFormatted(json: String) async throws -> String {
        let (explanation, synthesis, metrics) = try await analyze(json: json)

        return """
        \(metrics.description)

        === SYNTHESIS ===
        Pattern: \(synthesis.likelyCrashPattern)
        Hypothesis: \(synthesis.preliminaryHypothesis)
        Confidence: \(String(format: "%.0f%%", synthesis.hypothesisConfidence * 100))

        Evidence:
        \(synthesis.keyEvidence.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

        === FINAL ANALYSIS ===
        **Crash Type:** \(explanation.crashType)
        **Faulty Function:** `\(explanation.faultyFunction)`
        **Root Cause:** \(explanation.rootCause)
        **Fix:** \(explanation.suggestedFix)
        **Confidence:** \(explanation.confidence)
        """
    }
}
