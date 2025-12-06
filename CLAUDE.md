# CLAUDE.md - XcodeLLMToolchain

This file provides guidance to Claude Code (or any AI assistant) working on this codebase.

## CRITICAL: Always Use codemap First

**Before making ANY code changes, run codemap to understand the codebase structure:**

```bash
codemap --deps --json .
```

Or for specific file context:
```bash
codemap --deps --json . | jq '.files[] | select(.path | contains("FileName"))'
```

This project is built around codemap integration - the LLM tools use it internally. You should too.

## Project Overview

XcodeLLMToolchain is an open-source crash and memory analysis toolkit using Apple's Foundation Models (macOS 26+). It runs entirely on-device via the Neural Engine - no cloud, no API keys.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    XCODE LLM TOOLCHAIN                      │
├─────────────────────────────────────────────────────────────┤
│   LLDB Scripts (Python)      CLI (Swift)                    │
│   ├── explain_here           └── memory-explainer           │
│   ├── crash_explain                    │                    │
│   └── memory_explain                   ▼                    │
│              │              ┌─────────────────────────────┐ │
│              └────────────► │   MemoryExplainerCore       │ │
│                             │   @Generable types          │ │
│                             │   Tool calling (codemap)    │ │
│                             └────────────┬────────────────┘ │
│                                          ▼                  │
│                             ┌─────────────────────────────┐ │
│                             │ Apple Foundation Models     │ │
│                             │   On-device • Private       │ │
│                             └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Key Files

| Path | Purpose |
|------|---------|
| `Sources/MemoryExplainerCore/MemoryExplainerEngine.swift` | Core LLM engine with structured output |
| `Sources/MemoryExplainerCore/CrashExplanation.swift` | @Generable types and Instructions |
| `Sources/MemoryExplainerCore/Tools/CodeMapTool.swift` | Tool for LLM to query codemap |
| `Sources/MemoryExplainerCore/Tools/ReadSourceTool.swift` | Tool for LLM to read source files |
| `Sources/MemoryExplainer/Entry.swift` | CLI entry point |
| `lldb/plugin.py` | LLDB command registration |
| `lldb/capture_lib/commands.py` | crash_explain, memory_explain, explain_here |
| `lldb/capture_lib/analysis.py` | Crash data extraction from LLDB |

## Build Commands

```bash
# Build everything
swift build

# Build release
swift build -c release

# Run tests
swift test

# Run CLI
.build/debug/memory-explainer --help

# Test with crash suite
.build/debug/swift-crash-suite force_unwrap
```

## Key Technologies

- **Foundation Models** (macOS 26): Apple's on-device 3B LLM
- **@Generable macro**: Structured output - model must return valid types
- **@Guide descriptions**: Tell the model what each field means
- **Tool calling**: Model can invoke codemap and read source files
- **Instructions**: System prompts for consistent behavior

## Code Patterns

### Structured Output
```swift
@Generable
public struct CrashExplanation {
    @Guide(description: "Category of crash", .anyOf(["null_pointer", "force_unwrap_nil", ...]))
    public var crashType: String
}
```

### Tool Definition
```swift
public final class CodeMapTool: Tool {
    public let name = "get_dependencies"
    public let description = "Get dependency info for a file..."

    @Generable
    public struct Arguments {
        @Guide(description: "Path to project root")
        var projectPath: String
    }

    public func call(arguments: Arguments) async throws -> String { ... }
}
```

### LLM Session
```swift
let session = LanguageModelSession(
    tools: [ReadSourceTool(), CodeMapTool()],
    instructions: makeCrashInstructions()
)
let response = try await session.respond(
    to: "Analyze crash...",
    generating: CrashExplanation.self
)
```

## LLDB Integration

The Python scripts in `lldb/` capture crash context and pipe JSON to the Swift CLI:

```
LLDB → capture crash data → JSON → memory-explainer CLI → Foundation Models → structured explanation
```

## Common Tasks

### Adding a new crash type
1. Add to `CrashType` enum in `GeneratedCrash.swift`
2. Add to `crashType` anyOf list in `CrashExplanation.swift`
3. Add test case in `SwiftCrashSuite/main.swift`

### Adding a new tool
1. Create `Sources/MemoryExplainerCore/Tools/NewTool.swift`
2. Implement `Tool` protocol with `@Generable` Arguments
3. Add to tools array in `MemoryExplainerEngine.init()`

### Adding a new LLDB command
1. Add function in `lldb/capture_lib/commands.py`
2. Register in `lldb/plugin.py` `__lldb_init_module`

## Testing

```bash
# Unit tests
swift test

# Manual testing with crash suite
lldb .build/debug/swift-crash-suite -- force_unwrap
(lldb) run
(lldb) crash_explain --explain

# Battle mode (generate crash, then explain)
.build/debug/memory-explainer --battle
```

## Dependencies

- macOS 26 (Tahoe) or later
- Apple Silicon Mac
- Xcode 26+
- codemap (optional but recommended): `brew install jordancoin/tap/codemap`

## Style Guidelines

- Keep prompts minimal - let @Guide descriptions do the work
- One sentence per @Guide description
- Prefer structured output over free-form text
- Trim data to fit token limits (Foundation Models has ~32k context)
- User code frames are more valuable than system frames
