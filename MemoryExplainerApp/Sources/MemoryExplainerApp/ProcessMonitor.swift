import Foundation
import Combine
import FoundationModels

@MainActor
class ProcessMonitor: ObservableObject {
    @Published var debuggedProcess: ProcessInfo?
    @Published var isDebugging = false

    private var timer: Timer?
    private var lastTraceFile: URL?

    init() {
        startMonitoring()
    }

    func startMonitoring() {
        // Poll every 2 seconds for debugged processes
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDebuggedProcess()
            }
        }
        updateDebuggedProcess()
    }

    func updateDebuggedProcess() {
        // Find processes being debugged by lldb
        // Look for lldb-rpc-server which indicates Xcode debugging
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "pid,ppid,comm"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Find lldb-rpc-server processes
            var lldbPids: Set<Int32> = []
            for line in output.components(separatedBy: "\n") {
                if line.contains("lldb-rpc-server") || line.contains("debugserver") {
                    let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                    if let pid = Int32(parts.first ?? "") {
                        lldbPids.insert(pid)
                    }
                }
            }

            // Find the debugged app (child of lldb or recently launched with debugger)
            // For simplicity, look for common app patterns
            var foundProcess: ProcessInfo?

            for line in output.components(separatedBy: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                guard parts.count >= 3,
                      let pid = Int32(parts[0]),
                      let ppid = Int32(parts[1]) else { continue }

                let comm = parts[2...].joined(separator: " ")

                // Skip system processes
                if comm.hasPrefix("/usr") || comm.hasPrefix("/System") || comm.contains("Xcode") {
                    continue
                }

                // Look for app-like processes with debugserver as parent
                // or processes in DerivedData (Xcode builds)
                if comm.contains("DerivedData") || comm.contains(".app/") {
                    foundProcess = ProcessInfo(pid: pid, name: extractAppName(from: comm))
                    break
                }
            }

            if var process = foundProcess {
                // Get memory info
                process.memoryBytes = getMemoryUsage(pid: process.pid)
                process.threadCount = getThreadCount(pid: process.pid)
                self.debuggedProcess = process
                self.isDebugging = true
            } else {
                self.debuggedProcess = nil
                self.isDebugging = false
            }

        } catch {
            self.debuggedProcess = nil
            self.isDebugging = false
        }
    }

    func extractAppName(from path: String) -> String {
        // Extract app name from path like ".../MyApp.app/Contents/MacOS/MyApp"
        if let appRange = path.range(of: ".app") {
            let beforeApp = path[..<appRange.lowerBound]
            return String(beforeApp.split(separator: "/").last ?? "Unknown")
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    func getMemoryUsage(pid: Int32) -> UInt64 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/footprint")
        task.arguments = ["\(pid)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse footprint output for memory
            for line in output.components(separatedBy: "\n") {
                if line.contains("Memory Used:") || line.contains("phys_footprint:") {
                    // Extract number
                    let numbers = line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                    if let bytes = UInt64(numbers) {
                        return bytes
                    }
                }
            }
        } catch {}

        // Fallback: use ps
        return getMemoryFromPS(pid: pid)
    }

    func getMemoryFromPS(pid: Int32) -> UInt64 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "rss=", "-p", "\(pid)"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if let kb = UInt64(output) {
                return kb * 1024  // Convert KB to bytes
            }
        } catch {}

        return 0
    }

    func getThreadCount(pid: Int32) -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-M", "-p", "\(pid)"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Count lines (minus header)
            return max(0, output.components(separatedBy: "\n").count - 2)
        } catch {}

        return 0
    }

    func recordTrace(pid: Int32, duration: Int) async throws {
        let traceFile = FileManager.default.temporaryDirectory.appendingPathComponent("memory-explainer-\(pid).trace")

        // Remove old trace if exists
        try? FileManager.default.removeItem(at: traceFile)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xctrace")
        task.arguments = [
            "record",
            "--template", "Allocations",
            "--time-limit", "\(duration)s",
            "--attach", "\(pid)",
            "--output", traceFile.path
        ]

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus == 0 {
            lastTraceFile = traceFile
        } else {
            throw NSError(domain: "MemoryExplainer", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to record trace"])
        }
    }

    func explainMemory(for process: ProcessInfo) async throws -> String {
        // Get memory data
        var memoryData: [String: Any] = [
            "process": process.name,
            "pid": process.pid,
            "memory_bytes": process.memoryBytes,
            "thread_count": process.threadCount
        ]

        // If we have a trace, export allocations
        if let traceFile = lastTraceFile, FileManager.default.fileExists(atPath: traceFile.path) {
            let allocations = try await exportAllocations(from: traceFile)
            memoryData["allocations"] = allocations
        }

        // Get codemap context if we can find the project
        let codemapContext = await getCodemapContext(for: process)

        // Build prompt
        let jsonData = try JSONSerialization.data(withJSONObject: memoryData, options: .prettyPrinted)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        let prompt = """
        You are an expert iOS/macOS performance engineer. Analyze this memory data and explain any issues.

        Keep your response concise (3-5 sentences max). Focus on:
        1. Is memory usage concerning?
        2. Any obvious issues in the allocations?
        3. One specific recommendation

        MEMORY DATA:
        \(jsonString)

        CODE CONTEXT:
        \(codemapContext.isEmpty ? "Not available" : codemapContext)

        Brief analysis:
        """

        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }

    func exportAllocations(from traceFile: URL) async throws -> [[String: Any]] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xctrace")
        task.arguments = [
            "export",
            "--input", traceFile.path,
            "--xpath", "/trace-toc/run[@number=\"1\"]/tracks/track[@name=\"Allocations\"]/details/detail[@name=\"Statistics\"]"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe

        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let xml = String(data: data, encoding: .utf8) ?? ""

        // Parse XML for top allocations
        var allocations: [[String: Any]] = []

        // Simple regex parsing for the row elements
        let pattern = #"category="([^"]+)".*?persistent-bytes="(\d+)".*?count-persistent="(\d+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))

        for match in matches.prefix(10) {
            if let categoryRange = Range(match.range(at: 1), in: xml),
               let bytesRange = Range(match.range(at: 2), in: xml),
               let countRange = Range(match.range(at: 3), in: xml) {

                let category = String(xml[categoryRange])
                let bytes = Int(xml[bytesRange]) ?? 0
                let count = Int(xml[countRange]) ?? 0

                // Skip meta categories
                if !category.hasPrefix("All ") && !category.hasPrefix("Malloc ") {
                    allocations.append([
                        "class": category,
                        "bytes": bytes,
                        "count": count
                    ])
                }
            }
        }

        return allocations
    }

    func getCodemapContext(for process: ProcessInfo) async -> String {
        // Try to find project directory from DerivedData
        let derivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: derivedData,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return "" }

        // Find most recently modified project matching our app name
        let sorted = contents
            .filter { $0.lastPathComponent.lowercased().contains(process.name.lowercased()) }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return aDate > bDate
            }

        guard let projectBuild = sorted.first else { return "" }

        // Try to find source root from info.plist
        let infoPlist = projectBuild.appendingPathComponent("info.plist")
        guard let plistData = try? Data(contentsOf: infoPlist),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let workspacePath = plist["WorkspacePath"] as? String else { return "" }

        let projectRoot = URL(fileURLWithPath: workspacePath).deletingLastPathComponent()

        // Run codemap
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/codemap")
        task.arguments = ["--deps", projectRoot.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
