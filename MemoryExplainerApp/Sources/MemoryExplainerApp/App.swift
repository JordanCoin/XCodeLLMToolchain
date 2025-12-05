import SwiftUI
import Foundation
import FoundationModels

@main
struct MemoryExplainerApp: App {
    @StateObject private var monitor = ProcessMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            Label("Memory Explainer", systemImage: monitor.isDebugging ? "brain.head.profile.fill" : "brain.head.profile")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarView: View {
    @ObservedObject var monitor: ProcessMonitor
    @State private var isRecording = false
    @State private var explanation: String = ""
    @State private var isExplaining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile.fill")
                    .foregroundColor(.purple)
                Text("Memory Explainer")
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Debug status
            if let process = monitor.debuggedProcess {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "app.fill")
                            .foregroundColor(.green)
                        Text(process.name)
                            .fontWeight(.medium)
                        Text("(PID \(process.pid))")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }

                    // Memory stats
                    HStack(spacing: 16) {
                        StatView(label: "Memory", value: formatBytes(process.memoryBytes))
                        StatView(label: "Threads", value: "\(process.threadCount)")
                    }

                    if !process.topAllocations.isEmpty {
                        Divider()
                        Text("Top Allocations")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(process.topAllocations.prefix(3), id: \.name) { alloc in
                            HStack {
                                Text(alloc.name)
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text("\(alloc.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                // Action buttons
                HStack {
                    Button(action: { startRecording() }) {
                        Label(isRecording ? "Recording..." : "Record 30s",
                              systemImage: isRecording ? "record.circle.fill" : "record.circle")
                    }
                    .disabled(isRecording)

                    Button(action: { Task { await explain() } }) {
                        Label(isExplaining ? "Thinking..." : "Explain",
                              systemImage: "sparkles")
                    }
                    .disabled(isExplaining)
                }
                .buttonStyle(.borderedProminent)

            } else {
                HStack {
                    Image(systemName: "xcode")
                        .foregroundColor(.secondary)
                    Text("No app being debugged")
                        .foregroundColor(.secondary)
                }
                .padding()

                Text("Start debugging an app in Xcode to analyze memory")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Explanation area
            if !explanation.isEmpty {
                Divider()

                ScrollView {
                    Text(explanation)
                        .font(.system(.caption, design: .default))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 150)
                .padding(8)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
            }

            Divider()

            // Footer
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")

                Spacer()

                Text("codemap + Foundation Models")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 320)
    }

    func startRecording() {
        guard let process = monitor.debuggedProcess else { return }
        isRecording = true

        Task {
            do {
                try await monitor.recordTrace(pid: process.pid, duration: 30)
                isRecording = false
            } catch {
                isRecording = false
            }
        }
    }

    func explain() async {
        guard let process = monitor.debuggedProcess else { return }
        isExplaining = true

        do {
            explanation = try await monitor.explainMemory(for: process)
        } catch {
            explanation = "Error: \(error.localizedDescription)"
        }

        isExplaining = false
    }

    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct StatView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
        }
    }
}

struct AllocationInfo: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let bytes: UInt64
}

struct ProcessInfo {
    let pid: Int32
    let name: String
    var memoryBytes: UInt64 = 0
    var threadCount: Int = 0
    var topAllocations: [AllocationInfo] = []
}
