import Foundation
import FoundationModels

/// Smart synthesizer that combines scorer outputs into high-signal context.
/// Uses LLM to cross-reference evidence and form preliminary hypothesis.
public actor Synthesizer {
    private let config: ScoringPipelineConfig

    public init(config: ScoringPipelineConfig = .default) {
        self.config = config
    }

    /// Synthesize scorer outputs into condensed, high-signal context
    public func synthesize(outputs: ScorerOutputs) async throws -> SynthesizedContext {
        let session = LanguageModelSession(instructions: makeSynthesizerInstructions())

        let prompt = buildSynthesisPrompt(outputs: outputs)

        let response = try await session.respond(to: prompt, generating: SynthesizedContext.self)
        return response.content
    }

    /// Build the synthesis prompt with all evidence
    private func buildSynthesisPrompt(outputs: ScorerOutputs) -> String {
        var prompt = """
        Synthesize crash evidence into a focused hypothesis.

        CRASH: \(outputs.crashData.stopDescription)
        TYPE: \(outputs.crashData.crashType ?? outputs.crashData.stopReasonType)


        """

        // Add frame scores (sorted by relevance)
        let topFrames = outputs.frameScores
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(8)

        prompt += "=== FRAME RELEVANCE SCORES ===\n"
        for score in topFrames {
            let frame = outputs.crashData.frames.first { $0.index == score.frameIndex }
            let funcName = frame?.function ?? "frame \(score.frameIndex)"
            let marker = score.isBugOrigin ? " [BUG ORIGIN]" : ""
            prompt += String(format: "%.2f %@%@ - %@\n",
                           score.relevanceScore,
                           funcName,
                           marker,
                           score.reasoning)
        }
        prompt += "\n"

        // Add variable scores (only suspicious ones)
        let suspiciousVars = outputs.variableScores
            .filter { $0.suspicionScore >= config.variableSuspicionThreshold }
            .sorted { $0.suspicionScore > $1.suspicionScore }

        if !suspiciousVars.isEmpty {
            prompt += "=== SUSPICIOUS VARIABLES ===\n"
            for score in suspiciousVars.prefix(10) {
                prompt += String(format: "%.2f [%@] %@ in frame %d - %@\n",
                               score.suspicionScore,
                               score.issueCategory,
                               score.variableName,
                               score.frameIndex,
                               score.observation)
            }
            prompt += "\n"
        }

        // Add context scores (patterns found)
        let significantPatterns = outputs.contextScores
            .filter { $0.patternConfidence >= 0.3 && $0.patternDetected != "none" }
            .sorted { $0.patternConfidence > $1.patternConfidence }

        if !significantPatterns.isEmpty {
            prompt += "=== CODE PATTERNS ===\n"
            for score in significantPatterns.prefix(5) {
                let filename = (score.filePath as NSString).lastPathComponent
                let construct = score.codeConstruct ?? ""
                prompt += String(format: "%.2f [%@] in %@ - %@\n",
                               score.patternConfidence,
                               score.patternDetected,
                               filename,
                               construct)
            }
            prompt += "\n"
        }

        // Add relevant code snippets (condensed)
        if !outputs.codeSnippets.isEmpty {
            prompt += "=== CODE CONTEXT ===\n"
            for (file, code) in outputs.codeSnippets.prefix(3) {
                let filename = (file as NSString).lastPathComponent
                // Only include lines around the crash marker
                let relevantLines = extractRelevantLines(code)
                prompt += "[\(filename)]\n\(relevantLines)\n\n"
            }
        }

        prompt += """
        Based on all evidence:
        1. Select the most relevant frame indices (max 5)
        2. Identify variables worth investigating
        3. Determine the likely crash pattern
        4. Form a preliminary hypothesis
        5. List 1-3 key evidence points
        """

        return prompt
    }

    /// Extract only the most relevant lines from a code snippet
    private func extractRelevantLines(_ code: String) -> String {
        let lines = code.components(separatedBy: .newlines)

        // Find the crash line (marked with >>>)
        guard let crashLineIdx = lines.firstIndex(where: { $0.hasPrefix(">>>") }) else {
            // No marker, return first few lines
            return lines.prefix(5).joined(separator: "\n")
        }

        // Return crash line +/- 2 lines
        let start = max(0, crashLineIdx - 2)
        let end = min(lines.count - 1, crashLineIdx + 2)

        return lines[start...end].joined(separator: "\n")
    }
}

// MARK: - Instructions

private func makeSynthesizerInstructions() -> Instructions {
    Instructions {
        "You synthesize crash evidence into a focused hypothesis. Cross-reference all signals."
        "Frame scores show relevance. Variable scores show suspicious values. Context scores show code patterns."
        "Connect the dots: which frames have suspicious vars? Which code patterns match the crash type?"
        "Your hypothesis informs the final analysis - be specific but acknowledge uncertainty."
        "Select only frames with strong evidence. Don't include frames just because they're user code."
        "Key evidence should be concrete: 'nil value in self.data' not 'possible nil'."
    }
}

// MARK: - Formatted Output for Final Analysis

extension SynthesizedContext {
    /// Format synthesized context for the final analyzer
    public func formatForAnalysis(
        crashData: ParsedCrashData,
        codeSnippets: [String: String]
    ) -> String {
        var output = """
        === SYNTHESIZED CRASH CONTEXT ===

        STOP: \(crashData.stopDescription)
        PATTERN: \(likelyCrashPattern)
        CONFIDENCE: \(String(format: "%.0f%%", hypothesisConfidence * 100))

        HYPOTHESIS: \(preliminaryHypothesis)

        KEY EVIDENCE:

        """

        for (i, evidence) in keyEvidence.enumerated() {
            output += "\(i + 1). \(evidence)\n"
        }

        // Include relevant frames
        output += "\n=== RELEVANT FRAMES ===\n"
        for idx in relevantFrameIndices {
            if let frame = crashData.frames.first(where: { $0.index == idx }) {
                output += "[\(idx)] \(frame.function)"
                if let file = frame.file, let line = frame.line {
                    output += " at \((file as NSString).lastPathComponent):\(line)"
                }
                output += "\n"

                // Include suspicious variables from this frame
                let frameVars = suspiciousVariables.filter { varName in
                    frame.variables?.contains { $0.name == varName } ?? false
                }
                if !frameVars.isEmpty {
                    output += "    SUSPICIOUS: \(frameVars.joined(separator: ", "))\n"
                }
            }
        }

        // Include focused code snippets
        if !codeSnippets.isEmpty {
            output += "\n=== CODE ===\n"
            for idx in relevantFrameIndices.prefix(2) {
                if let frame = crashData.frames.first(where: { $0.index == idx }),
                   let file = frame.file,
                   let code = codeSnippets[file] {
                    let filename = (file as NSString).lastPathComponent
                    output += "[\(filename)]\n"
                    // Extract focused portion
                    let lines = code.components(separatedBy: .newlines)
                    if let crashLineIdx = lines.firstIndex(where: { $0.hasPrefix(">>>") }) {
                        let start = max(0, crashLineIdx - 3)
                        let end = min(lines.count - 1, crashLineIdx + 3)
                        output += lines[start...end].joined(separator: "\n")
                    } else {
                        output += String(code.prefix(500))
                    }
                    output += "\n\n"
                }
            }
        }

        return output
    }
}
