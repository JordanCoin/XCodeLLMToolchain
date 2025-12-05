import Foundation
import Combine
import FoundationModels

@MainActor
class ProcessMonitor: ObservableObject {
    @Published var debuggedProcess: ProcessInfo?
    @Published var isDebugging = false

    private var timer: Timer?
    private var lastTraceFile: URL?

    init(startMonitoring: Bool = true) {
        if startMonitoring {
            self.startMonitoring()
        }
    }

    /// Preview-only initializer with mock data
    static func preview(process: ProcessInfo? = nil, isDebugging: Bool = false) -> ProcessMonitor {
        let monitor = ProcessMonitor(startMonitoring: false)
        monitor.debuggedProcess = process
        monitor.isDebugging = isDebugging
        return monitor
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
        // Find processes being debugged by Xcode
        // Debugged apps have debugserver as their parent process
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

            // Find debugserver PIDs (these are the parents of debugged apps)
            var debugserverPids: Set<Int32> = []
            for line in output.components(separatedBy: "\n") {
                if line.contains("debugserver") {
                    let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                    if let pid = Int32(parts.first ?? "") {
                        debugserverPids.insert(pid)
                    }
                }
            }

            // Find app whose parent is debugserver
            var foundProcess: ProcessInfo?

            for line in output.components(separatedBy: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                guard parts.count >= 3,
                      let pid = Int32(parts[0]),
                      let ppid = Int32(parts[1]) else { continue }

                let comm = parts[2...].joined(separator: " ")

                // Check if parent is debugserver - this means the app is being debugged
                if debugserverPids.contains(ppid) {
                    foundProcess = ProcessInfo(pid: pid, name: extractAppName(from: comm))
                    break
                }
            }

            if var process = foundProcess {
                // Get memory info
                process.memoryBytes = getMemoryUsage(pid: process.pid)
                process.threadCount = getThreadCount(pid: process.pid)
                // Preserve existing allocations if same process
                if let existing = self.debuggedProcess, existing.pid == process.pid {
                    process.topAllocations = existing.topAllocations
                }
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

            // Parse footprint output - looks like "Footprint: 29 MB"
            for line in output.components(separatedBy: "\n") {
                if line.contains("Footprint:") {
                    // Extract number and unit (e.g., "29 MB")
                    let pattern = #"Footprint:\s*(\d+)\s*(MB|KB|GB|B)"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                       let numRange = Range(match.range(at: 1), in: line),
                       let unitRange = Range(match.range(at: 2), in: line) {

                        let num = UInt64(line[numRange]) ?? 0
                        let unit = String(line[unitRange])

                        switch unit {
                        case "GB": return num * 1024 * 1024 * 1024
                        case "MB": return num * 1024 * 1024
                        case "KB": return num * 1024
                        default: return num
                        }
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

    func updateAllocationsFromTrace() async {
        guard let traceFile = lastTraceFile,
              var process = debuggedProcess,
              FileManager.default.fileExists(atPath: traceFile.path) else { return }

        do {
            let allocations = try await exportAllocations(from: traceFile)
            process.topAllocations = allocations.prefix(5).compactMap { dict -> AllocationInfo? in
                guard let name = dict["class"] as? String,
                      let count = dict["count"] as? Int,
                      let bytes = dict["bytes"] as? Int else { return nil }
                return AllocationInfo(name: name, count: count, bytes: UInt64(bytes))
            }
            self.debuggedProcess = process
        } catch {
            // Silently fail - allocations are optional
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

        // If we have a trace, export allocations (limit to top 5 for LLM)
        if let traceFile = lastTraceFile, FileManager.default.fileExists(atPath: traceFile.path) {
            let allocations = try await exportAllocations(from: traceFile)
            memoryData["allocations"] = Array(allocations.prefix(5))
        }

        // Get codemap context if we can find the project (limit size to avoid 4096 token limit)
        var codemapContext = await getCodemapContext(for: process)
        if codemapContext.count > 1000 {
            codemapContext = String(codemapContext.prefix(1000)) + "\n... (truncated)"
        }

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

                // Skip only the summary "All ..." categories
                if !category.hasPrefix("All ") && category != "destroyed event" {
                    allocations.append([
                        "class": category,
                        "bytes": bytes,
                        "count": count
                    ])
                }
            }
        }

        // Sort by bytes descending to get biggest allocations first
        return allocations.sorted {
            ($0["bytes"] as? Int ?? 0) > ($1["bytes"] as? Int ?? 0)
        }
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
