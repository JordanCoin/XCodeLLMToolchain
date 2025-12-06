# Contributing to XcodeLLMToolchain

Thanks for your interest in making crash debugging less painful for iOS/macOS engineers.

## Quick Start

```bash
git clone https://github.com/JordanCoin/XcodeLLMToolchain.git
cd XcodeLLMToolchain
swift build
swift test
```

## What We're Looking For

### High Impact
- **New crash type detection** - See `CrashExplanation.swift` for the current list
- **Better @Guide descriptions** - The LLM's accuracy depends on these
- **More LLDB commands** - Anything that helps during debugging
- **Tool calling improvements** - `CodeMapTool` and `ReadSourceTool` are just the start

### Always Welcome
- Bug fixes
- Documentation improvements
- Test coverage
- Performance optimizations

### Lower Priority
- UI/menu bar app (there's a separate closed-source app for that)
- Support for non-Apple LLMs (defeats the privacy point)

## How to Contribute

### 1. Find or Create an Issue

Check existing issues first. If you're adding something new, open an issue to discuss before writing code.

### 2. Fork & Branch

```bash
git checkout -b feature/your-feature-name
```

### 3. Make Changes

Follow the existing code style:
- Swift: Standard Swift conventions, use `@Generable` for any LLM output types
- Python: PEP 8, keep LLDB scripts simple
- Keep prompts/instructions minimal - let `@Guide` do the work

### 4. Test

```bash
# Unit tests
swift test

# Manual testing with crash suite
swift build
lldb .build/debug/swift-crash-suite -- force_unwrap
(lldb) run
(lldb) crash_explain --explain
```

### 5. Submit PR

- Clear title describing the change
- Reference any related issues
- Include before/after if it's a behavior change

## Code Organization

```
Sources/
├── MemoryExplainerCore/     # Library - this is where most work happens
│   ├── MemoryExplainerEngine.swift  # Main engine
│   ├── CrashExplanation.swift       # @Generable types + Instructions
│   ├── GeneratedCrash.swift         # For battle mode
│   ├── LLMClient.swift              # Protocol for future backends
│   └── Tools/                       # Tool calling
├── MemoryExplainer/         # CLI - thin wrapper
└── SwiftCrashSuite/         # Test crashes

lldb/
├── plugin.py                # LLDB entry point
├── install.sh               # One-liner installer
└── capture_lib/             # Python modules
    ├── commands.py          # crash_explain, memory_explain, explain_here
    ├── analysis.py          # Crash data extraction
    ├── formatting.py        # Output formatting + trimming
    ├── tools.py             # codemap integration
    └── utils.py             # LLDB helpers
```

## Adding a New Crash Type

1. Add to enum in `GeneratedCrash.swift`:
```swift
@Generable
public enum CrashType: String {
    // ... existing cases
    case yourNewType = "your_new_type"
}
```

2. Add to `anyOf` in `CrashExplanation.swift`:
```swift
@Guide(description: "Category of crash", .anyOf([
    // ... existing types
    "your_new_type"
]))
public var crashType: String
```

3. Add test case in `SwiftCrashSuite/main.swift`

4. Test it:
```bash
swift build
lldb .build/debug/swift-crash-suite -- your_new_type
(lldb) run
(lldb) crash_explain --explain
```

## Adding a New Tool

Tools let the LLM take actions during analysis (read files, query codemap, etc).

1. Create `Sources/MemoryExplainerCore/Tools/YourTool.swift`:
```swift
import Foundation
import FoundationModels

public final class YourTool: Tool {
    public let name = "your_tool_name"
    public let description = "What this tool does - be specific"

    @Generable
    public struct Arguments {
        @Guide(description: "What this argument is for")
        var someArg: String
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> String {
        // Your implementation
        return "Result for LLM to use"
    }
}
```

2. Add to engine in `MemoryExplainerEngine.swift`:
```swift
public init(enableTools: Bool = false) {
    self.tools = enableTools ? [ReadSourceTool(), CodeMapTool(), YourTool()] : []
}
```

## Adding a New LLDB Command

1. Add function in `lldb/capture_lib/commands.py`:
```python
def your_command(debugger, command, result, internal_dict):
    """
    LLDB command: your_command

    Does XYZ.

    Usage:
        your_command           - Basic usage
        your_command --json    - JSON output
    """
    # Implementation
```

2. Register in `lldb/plugin.py`:
```python
def __lldb_init_module(debugger, internal_dict):
    # ... existing commands
    debugger.HandleCommand(
        'command script add -f plugin.your_command your_command'
    )
```

## Style Guide

### Swift
- Use `@Generable` for any struct the LLM outputs
- Keep `@Guide` descriptions to one sentence
- Prefer structured output over free-form text
- Trim data to fit token limits

### Python
- Keep it simple - LLDB scripts should be fast
- Handle errors gracefully (don't crash the debugger)
- Use JSON for data exchange with Swift CLI

### Prompts/Instructions
- Less is more - the `@Guide` descriptions do most of the work
- Be specific about what NOT to do (e.g., "don't invent function names")
- Test with battle mode to catch hallucinations

## Questions?

Open an issue or reach out on Twitter/X.

---

Every contribution helps iOS/macOS engineers debug faster. Thanks for making that happen.
