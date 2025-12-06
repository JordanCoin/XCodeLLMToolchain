import Foundation
import FoundationModels

/// Scores code context for dangerous patterns.
/// Reads source files around crash sites and identifies risky constructs.
public actor ContextScorer {
    private let config: ScoringPipelineConfig

    public init(config: ScoringPipelineConfig = .default) {
        self.config = config
    }

    /// Analyze code context from high-relevance frames
    public func scoreContext(
        frames: [CrashFrame],
        frameScores: [FrameScore],
        crashContext: String
    ) async throws -> (scores: [ContextScore], snippets: [String: String]) {
        // Get files from high-relevance frames
        let relevantFrames = frames.filter { frame in
            frameScores.first { $0.frameIndex == frame.index }?.relevanceScore ?? 0 >= config.frameRelevanceThreshold
        }

        // Collect unique file locations to analyze
        var fileLocations: [(file: String, line: Int)] = []
        var seen = Set<String>()

        for frame in relevantFrames {
            guard let file = frame.file, let line = frame.line else { continue }
            let key = "\(file):\(line)"
            if !seen.contains(key) {
                seen.insert(key)
                fileLocations.append((file, line))
            }
        }

        guard !fileLocations.isEmpty else {
            return ([], [:])
        }

        // Read code snippets in parallel
        var snippets: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for (file, line) in fileLocations {
                group.addTask {
                    let code = await self.readCodeSnippet(file: file, centerLine: line)
                    return (file, code)
                }
            }

            for await (file, code) in group {
                if let code = code {
                    snippets[file] = code
                }
            }
        }

        guard !snippets.isEmpty else {
            return ([], [:])
        }

        // Score patterns in code
        let scores = try await scoreCodePatterns(
            snippets: snippets,
            fileLocations: fileLocations,
            crashContext: crashContext
        )

        return (scores, snippets)
    }

    /// Read source code around a specific line
    private func readCodeSnippet(file: String, centerLine: Int) async -> String? {
        guard FileManager.default.fileExists(atPath: file) else {
            return nil
        }

        guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        let startLine = max(0, centerLine - config.codeContextLines - 1)
        let endLine = min(lines.count - 1, centerLine + config.codeContextLines - 1)

        guard startLine <= endLine && endLine < lines.count else {
            return nil
        }

        var result = ""
        for i in startLine...endLine {
            let marker = (i == centerLine - 1) ? ">>>" : "   "
            result += "\(marker) \(i + 1): \(lines[i])\n"
        }

        return result
    }

    /// Score code patterns using LLM
    private func scoreCodePatterns(
        snippets: [String: String],
        fileLocations: [(file: String, line: Int)],
        crashContext: String
    ) async throws -> [ContextScore] {
        let session = LanguageModelSession(instructions: makeContextScorerInstructions())

        let prompt = buildCodePrompt(snippets: snippets, fileLocations: fileLocations, crashContext: crashContext)

        // We need a batch type for multiple context scores
        @Generable
        struct ContextScoreBatch: Sendable {
            @Guide(description: "Pattern scores for each analyzed file")
            var scores: [ContextScore]
        }

        let response = try await session.respond(to: prompt, generating: ContextScoreBatch.self)
        return response.content.scores
    }

    /// Build prompt for code pattern analysis
    private func buildCodePrompt(
        snippets: [String: String],
        fileLocations: [(file: String, line: Int)],
        crashContext: String
    ) -> String {
        var prompt = "Crash: \(crashContext)\n\nAnalyze code patterns in these files:\n\n"

        for (file, line) in fileLocations {
            guard let code = snippets[file] else { continue }

            let filename = (file as NSString).lastPathComponent
            prompt += "=== \(filename) (crash line: \(line)) ===\n"
            prompt += code
            prompt += "\n\n"
        }

        prompt += "Identify dangerous patterns (force unwrap, unsafe cast, etc.) near crash lines."

        return prompt
    }
}

// MARK: - Instructions

private func makeContextScorerInstructions() -> Instructions {
    Instructions {
        "You identify dangerous code patterns near crash sites. Be specific."
        "Look for: force unwrap (!), try!, as!, unsafe pointers, array subscripts without bounds check."
        "Also: unowned references, implicit unwraps, unchecked arithmetic, closure retain cycles."
        "High confidence (0.8-1.0): pattern on or adjacent to crash line."
        "Medium (0.4-0.7): pattern nearby, plausibly related."
        "Low (0.0-0.3): pattern exists but unlikely cause."
        "Set codeConstruct to the exact problematic code like 'value!' or 'array[i]'."
    }
}
