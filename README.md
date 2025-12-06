# XcodeLLMToolchain

Open source crash and memory analysis tools using Apple's Foundation Models. No cloud, no API keys - runs entirely on your Mac's Neural Engine.

## What's included

- **MemoryExplainerCore** - Swift library for LLM-powered crash analysis
- **memory-explainer** - CLI tool for crash explanation
- **LLDB scripts** - Debug commands for Xcode (`explain_here`, `crash_explain`, `memory_explain`)

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon Mac
- Xcode 26+

## Quick Start

### Install LLDB commands
```bash
echo 'command script import /path/to/XcodeLLMToolchain/lldb/plugin.py' >> ~/.lldbinit-Xcode
```

Or use the install script:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/JordanCoin/XcodeLLMToolchain/main/lldb/install.sh)"
```

### Build the CLI
```bash
cd XcodeLLMToolchain
swift build
```

### Use in Xcode
```
(lldb) explain_here            # Explain current breakpoint state
(lldb) crash_explain --explain # Analyze a crash with LLM
(lldb) memory_explain          # Analyze memory state
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    XCODE LLM TOOLCHAIN                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   LLDB Scripts ────────┐                                    │
│   (explain_here)       │                                    │
│   (crash_explain)      ▼                                    │
│                  ┌─────────────────────────────┐            │
│                  │   memory-explainer CLI      │            │
│                  └────────────┬────────────────┘            │
│                               ▼                             │
│                  ┌─────────────────────────────┐            │
│                  │   MemoryExplainerCore       │            │
│                  │  @Generable structured out  │            │
│                  │  + Tool calling             │            │
│                  └────────────┬────────────────┘            │
│                               ▼                             │
│                  ┌─────────────────────────────┐            │
│                  │ Apple Foundation Models     │            │
│                  │   On-device • Private       │            │
│                  └─────────────────────────────┘            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## LLDB Commands

| Command | Usage | Output |
|---------|-------|--------|
| `explain_here` | At any breakpoint | What's happening, variable observations, next steps |
| `crash_explain --explain` | When stopped at crash | Crash type, root cause, fix, confidence |
| `crash_explain --json` | When stopped at crash | Raw JSON for scripting |
| `memory_explain` | Any time | Memory overview and potential issues |

## Using the Library

Add MemoryExplainerCore as a dependency in your Swift package:

```swift
dependencies: [
    .package(path: "/path/to/XcodeLLMToolchain")
]
```

Then use it in your code:

```swift
import MemoryExplainerCore

let engine = MemoryExplainerEngine()
let explanation = try await engine.explainCrash(json: crashDataJSON)
print(explanation.rootCause)
print(explanation.suggestedFix)
```

## Example Workflow

### 1. Hit a crash in Xcode

```
(lldb) crash_explain --explain
```

**Output:**
```
Crash Type: force_unwrap_nil
Faulty Function: fetchUserProfile
Root Cause: Optional 'user' was nil when force-unwrapped after async network call
Fix: Use guard let or optional chaining instead of force unwrap
Confidence: high
```

### 2. Pause at a breakpoint you don't understand

```
(lldb) explain_here
```

**Output:**
```
Current Action: The code is submitting a quiz answer
Observations: Variable 'self' is nil (weak capture), 'isEnabled' is false
Watch For: The weak self capture may have been deallocated
Next Step: Check if the view controller is still in memory when this closure runs
```

## Repo Structure

```
XcodeLLMToolchain/
├── Package.swift
├── Sources/
│   ├── MemoryExplainer/        # CLI executable
│   ├── MemoryExplainerCore/    # Library (engine, @Generable types, tools)
│   └── SwiftCrashSuite/        # Test crash generator
├── Tests/
│   └── MemoryExplainerCoreTests/
├── lldb/
│   ├── plugin.py               # LLDB entry point
│   └── capture_lib/            # Analysis and formatting
└── repro/                      # Sample crash data
```

## How It Works

- **Structured output**: Uses `@Generable` macros so the model outputs valid crash types - no hallucinations
- **codemap integration**: Understands your codebase structure for better context
- **Token-aware**: Automatically trims data to fit Foundation Models' context window
- **Source reading**: Model can read your actual source files for deeper analysis

## Why This Exists

macOS 26 introduced two things that make this possible:

1. **xzone_malloc + MTE**: Memory bugs are now deterministic with clear "receipts"
2. **Foundation Models**: Apple's on-device 3B LLM - fast, private, no network required

Combine them with LLDB and you get AI-powered debugging that runs entirely on your Mac.

## License

MIT
