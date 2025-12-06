# XcodeLLMToolchain

**AI-powered crash debugging that runs entirely on your Mac.**

Use Apple's Foundation Models to understand crashes, explain breakpoints, and analyze memory - all on-device, all private.

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)](https://developer.apple.com/macos/)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## Why This Exists

macOS 26 shipped two things that change debugging forever:

1. **Foundation Models** - Apple's 3B parameter LLM running on the Neural Engine
2. **xzone_malloc + MTE** - Memory bugs now come with receipts

This toolchain combines them. When your app crashes, you get an instant AI explanation - no uploading crash logs, no waiting for symbolication, no "what does this even mean?"

```
(lldb) crash_explain --explain

Crash Type: force_unwrap_nil
Faulty Function: fetchUserProfile
Root Cause: Optional 'user' was nil when force-unwrapped after async network call
Fix: Use guard let or optional chaining instead of force unwrap
Confidence: high
```

## Quick Start

### Option 1: One-liner install (LLDB commands only)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/JordanCoin/XcodeLLMToolchain/main/lldb/install.sh)"
```

### Option 2: Full install (CLI + library)

```bash
git clone https://github.com/JordanCoin/XcodeLLMToolchain.git
cd XcodeLLMToolchain
swift build

# Add LLDB commands
echo 'command script import ~/path/to/XcodeLLMToolchain/lldb/plugin.py' >> ~/.lldbinit-Xcode
```

## What You Get

### LLDB Commands

| Command | When to Use | What It Does |
|---------|-------------|--------------|
| `explain_here` | Any breakpoint | Explains current state, variables, what to look at next |
| `crash_explain --explain` | When crashed | Root cause analysis with fix suggestions |
| `crash_explain --json` | Scripting | Raw JSON for pipelines |
| `memory_explain` | Memory issues | Analyzes allocations and potential leaks |

### Swift Library

```swift
import MemoryExplainerCore

let engine = MemoryExplainerEngine()
let explanation = try await engine.explainCrash(json: crashJSON)

print(explanation.crashType)     // "force_unwrap_nil"
print(explanation.rootCause)     // "Optional 'user' was nil..."
print(explanation.suggestedFix)  // "Use guard let..."
print(explanation.confidence)    // "high"
```

### Battle Mode (LLM vs LLM)

```bash
# Generate a tricky crash, then explain it
.build/debug/memory-explainer --battle

# Watch the model try to fool itself
```

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                         YOUR APP CRASHES                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  LLDB captures: stack trace, variables, crash reason, etc.  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  codemap adds: dependency graph, related files, structure   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Foundation Models (on-device) analyzes with @Generable     │
│  Structured output = no hallucinated function names         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  You get: crash type, root cause, fix, confidence level     │
└─────────────────────────────────────────────────────────────┘
```

**Key insight**: The `@Generable` macro forces the model to output valid Swift types. It can't make up function names that don't exist in your crash data.

## Requirements

- **macOS 26** (Tahoe) or later
- **Apple Silicon** Mac (M1/M2/M3/M4)
- **Xcode 26+**

Optional but recommended:
- **codemap**: `brew install jordancoin/tap/codemap` - gives the LLM more context about your codebase

## Example Workflows

### 1. "Why did this crash?"

```
(lldb) crash_explain --explain
```

Output:
```
Crash Type: use_after_free
Faulty Function: handleNetworkResponse
Root Cause: Closure captured 'self' weakly but accessed 'dataSource' after deallocation
Fix: Add [weak dataSource] to closure capture list or check for nil before access
Confidence: high
```

### 2. "What's happening at this breakpoint?"

```
(lldb) explain_here
```

Output:
```
Current Action: The code is validating user input before submission
Observations: Variable 'email' is empty string, 'isValid' is false
Watch For: The validation will fail silently without user feedback
Next Step: Check if the email text field delegate is properly connected
```

### 3. "Is my memory usage okay?"

```
(lldb) memory_explain
```

Output:
```
Concerning: Yes
Severity: warning
Issue: 847 UIImage instances allocated - likely caching images without size limits
Fix: Implement NSCache with countLimit or use SDWebImage for automatic memory management
```

## Project Structure

```
XcodeLLMToolchain/
├── Sources/
│   ├── MemoryExplainerCore/    # The brain - @Generable types, tools, engine
│   │   ├── MemoryExplainerEngine.swift
│   │   ├── CrashExplanation.swift
│   │   └── Tools/
│   │       ├── CodeMapTool.swift
│   │       └── ReadSourceTool.swift
│   ├── MemoryExplainer/        # CLI entry point
│   └── SwiftCrashSuite/        # Test crashes (14 types)
├── lldb/
│   ├── plugin.py               # LLDB registration
│   ├── install.sh              # One-liner installer
│   └── capture_lib/            # Python crash capture
└── Tests/
```

## Extending It

### Add to your own app

```swift
// Package.swift
dependencies: [
    .package(path: "/path/to/XcodeLLMToolchain")
]

// Your code
import MemoryExplainerCore

struct CrashReporter {
    let engine = MemoryExplainerEngine(enableTools: true)

    func explain(_ crashData: [String: Any]) async throws -> CrashExplanation {
        let json = try JSONSerialization.data(withJSONObject: crashData)
        return try await engine.explainCrashStructured(
            json: String(data: json, encoding: .utf8)!
        )
    }
}
```

### Add a new tool

```swift
public final class MyTool: Tool {
    public let name = "my_tool"
    public let description = "What it does..."

    @Generable
    public struct Arguments {
        @Guide(description: "What this arg is for")
        var input: String
    }

    public func call(arguments: Arguments) async throws -> String {
        // Your logic here
    }
}
```

## Testing

```bash
# Run unit tests
swift test

# Test with real crashes
swift build
lldb .build/debug/swift-crash-suite -- force_unwrap
(lldb) run
(lldb) crash_explain --explain

# All 14 crash types:
# force_unwrap, array_bounds, implicit_unwrap, dict_unwrap,
# type_cast, precondition, assertion, fatal_error, overflow,
# unowned, range, recursion, div_zero, optional_chain
```

## Privacy

**Everything runs on-device.** Your crash data never leaves your Mac. Foundation Models runs on the Neural Engine - no network calls, no API keys, no telemetry.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). PRs welcome for:
- New crash type detection
- Better prompts/instructions
- Additional LLDB commands
- Documentation improvements

## License

MIT - do whatever you want with it.

---

**Built for iOS/macOS engineers who are tired of staring at crash logs.**

*If this saves you debugging time, star the repo.*
