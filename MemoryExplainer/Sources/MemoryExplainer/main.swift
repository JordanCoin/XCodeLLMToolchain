import Foundation
import FoundationModels

/// Memory analysis and crash explanation using Apple's on-device LLM
@main
struct MemoryExplainer {
    static func main() async throws {
        let args = CommandLine.arguments

        if args.count < 2 || args[1] == "--help" || args[1] == "-h" {
            printUsage()
            return
        }

        // Detect mode from input JSON
        let inputJSON: String
        if args[1] == "-" {
            var input = ""
            while let line = readLine() {
                input += line + "\n"
            }
            inputJSON = input
        } else {
            inputJSON = try String(contentsOfFile: args[1], encoding: .utf8)
        }

        // Get codemap context if project path provided
        var codemapContext = ""
        if args.count > 2 {
            codemapContext = try await getCodemapContext(projectPath: args[2])
        }

        // Detect if this is crash or memory analysis
        if inputJSON.contains("\"crash\"") {
            let explanation = try await explainCrash(json: inputJSON, codemapContext: codemapContext)
            print(explanation)
        } else if inputJSON.contains("\"memory\"") {
            let explanation = try await explainMemory(json: inputJSON, codemapContext: codemapContext)
            print(explanation)
        } else {
            // Generic analysis
            let explanation = try await explainGeneric(json: inputJSON, codemapContext: codemapContext)
            print(explanation)
        }
    }

    static func printUsage() {
        print("""
        memory-explainer - Explain crashes and memory issues using Apple's on-device LLM

        Usage:
            memory-explainer <input.json> [project-path]
            crash_explain --json | memory-explainer - [project-path]
            memory_explain --json | memory-explainer - [project-path]

        Arguments:
            input.json    - JSON from crash_explain or memory_explain
            -             - Read JSON from stdin
            project-path  - Optional path for additional codemap context

        Examples:
            # Crash analysis
            (lldb) crash_explain --json > /tmp/crash.json
            memory-explainer /tmp/crash.json ~/Code/MyApp

            # Memory analysis
            (lldb) memory_explain --json > /tmp/memory.json
            memory-explainer /tmp/memory.json ~/Code/MyApp

            # Pipe directly
            (lldb) crash_explain --json | memory-explainer -
        """)
    }

    static func getCodemapContext(projectPath: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/codemap")
        process.arguments = ["--deps", projectPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func explainCrash(json: String, codemapContext: String) async throws -> String {
        let session = LanguageModelSession()

        let prompt = """
        You are an expert iOS/macOS debugger. Analyze this crash and explain it clearly.

        Focus on:
        1. What type of error occurred (EXC_BAD_ACCESS, SIGABRT, etc.)
        2. Where it happened (function, file, line)
        3. The likely root cause based on the stack trace
        4. Specific steps to fix it

        CRASH DATA:
        \(json)

        CODE CONTEXT (from codemap - shows file dependencies):
        \(codemapContext.isEmpty ? "Not available" : codemapContext)

        Provide a clear, actionable explanation:
        """

        let response = try await session.respond(to: prompt)
        return response.content
    }

    static func explainMemory(json: String, codemapContext: String) async throws -> String {
        let session = LanguageModelSession()

        let prompt = """
        You are an expert iOS/macOS performance engineer. Analyze this memory usage data.

        Focus on:
        1. Which classes/types are using the most memory
        2. Potential memory leaks or retention issues
        3. Classes with suspiciously high instance counts
        4. Specific recommendations to reduce memory usage

        MEMORY DATA:
        \(json)

        CODE CONTEXT (from codemap - shows file dependencies and structure):
        \(codemapContext.isEmpty ? "Not available" : codemapContext)

        If codemap context is available, explain:
        - Which files create these objects
        - Where they might be retained unexpectedly
        - Architectural issues that could cause accumulation

        Provide a clear analysis with specific recommendations:
        """

        let response = try await session.respond(to: prompt)
        return response.content
    }

    static func explainGeneric(json: String, codemapContext: String) async throws -> String {
        let session = LanguageModelSession()

        let prompt = """
        You are an expert iOS/macOS developer. Analyze this debugging data.

        DATA:
        \(json)

        CODE CONTEXT:
        \(codemapContext.isEmpty ? "Not available" : codemapContext)

        Explain what this shows and provide recommendations:
        """

        let response = try await session.respond(to: prompt)
        return response.content
    }
}
