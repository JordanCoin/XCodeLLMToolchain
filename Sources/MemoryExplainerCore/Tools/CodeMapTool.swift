import Foundation
import FoundationModels

/// Tool that lets the model query codemap for dependency information
public final class CodeMapTool: Tool {
    public let name = "get_dependencies"
    public let description = "Get dependency information for a file - what imports it and what it imports. Use this to understand how a crashed file connects to the rest of the codebase."

    @Generable
    public struct Arguments {
        @Guide(description: "Path to the project root directory")
        var projectPath: String

        @Guide(description: "The specific file to get dependencies for (relative path)")
        var filePath: String
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> String {
        let codemapPath = "/opt/homebrew/bin/codemap"

        guard FileManager.default.fileExists(atPath: codemapPath) else {
            return "codemap not installed"
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: codemapPath)
        task.arguments = ["--deps", "--json", arguments.projectPath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return "Could not parse codemap output"
            }

            // Filter to relevant file info
            if let jsonData = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                let fileName = URL(fileURLWithPath: arguments.filePath).lastPathComponent
                var relevant: [String: Any] = ["file": fileName]

                // Find imports and importers for this file
                if let files = json["files"] as? [[String: Any]] {
                    for file in files {
                        if let path = file["path"] as? String, path.contains(fileName) {
                            relevant["imports"] = file["imports"] ?? []
                            relevant["importedBy"] = file["importedBy"] ?? []
                            break
                        }
                    }
                }

                if let resultData = try? JSONSerialization.data(withJSONObject: relevant, options: .prettyPrinted),
                   let resultString = String(data: resultData, encoding: .utf8) {
                    return "Dependencies for \(fileName):\n\(resultString)"
                }
            }

            // Fallback: return truncated raw output
            let truncated = output.count > 500 ? String(output.prefix(500)) + "..." : output
            return truncated

        } catch {
            return "Error running codemap: \(error.localizedDescription)"
        }
    }
}
