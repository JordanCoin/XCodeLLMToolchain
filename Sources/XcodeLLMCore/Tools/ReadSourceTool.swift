import Foundation
import FoundationModels

/// Tool that lets the model read source code around a crash site
public final class ReadSourceTool: Tool {
    public let name = "read_source"
    public let description = "Read source code lines from a file around a specific line number. Use this to understand the code context of a crash."

    @Generable
    public struct Arguments {
        @Guide(description: "The file path to read from")
        var filePath: String

        @Guide(description: "The line number to center on")
        var lineNumber: Int

        @Guide(description: "Number of lines to read before and after (1-20)")
        var contextLines: Int
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> String {
        let path = arguments.filePath
        let targetLine = arguments.lineNumber
        let context = min(20, max(1, arguments.contextLines))

        // Try to read the file
        guard FileManager.default.fileExists(atPath: path) else {
            return "File not found: \(path)"
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "Could not read file: \(path)"
        }

        let lines = content.components(separatedBy: .newlines)
        let startLine = max(0, targetLine - context - 1)
        let endLine = min(lines.count - 1, targetLine + context - 1)

        var result = "Source from \(path) (lines \(startLine + 1)-\(endLine + 1)):\n"
        for i in startLine...endLine {
            let marker = (i == targetLine - 1) ? ">>>" : "   "
            result += "\(marker) \(i + 1): \(lines[i])\n"
        }

        return result
    }
}
