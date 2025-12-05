# XcodeLLMToolchain

On-device crash and memory analysis using Apple's Foundation Models. No cloud, no API keys - runs entirely on your Mac's Neural Engine.

## What it does

- **Crash analysis**: Feed it crash data, get back structured explanations (crash type, root cause, suggested fix)
- **Breakpoint debugging**: Ask "what's happening here?" at any breakpoint
- **Memory inspection**: Analyze memory state and potential issues
- **Works offline**: Uses Apple's on-device 3B LLM via Foundation Models framework

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon Mac
- Xcode 26+

## Quick Start

### Install LLDB commands
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/JordanCoin/XcodeLLMToolchain/main/lldb/install.sh)"
```

### Use in Xcode
```
(lldb) explain_here            # Explain current breakpoint state
(lldb) crash_explain --explain # Analyze a crash with LLM
(lldb) memory_explain          # Analyze memory state
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      XCODE LLM TOOLCHAIN                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   LLDB Scripts ──┐                        ┌── Menu Bar App      │
│   (explain_here)  │                       │   (coming soon)     │
│                   ▼                       ▼                     │
│              ┌─────────────────────────────────────┐            │
│              │     memory-explainer CLI            │            │
│              └───────────────┬─────────────────────┘            │
│                              ▼                                  │
│              ┌─────────────────────────────────────┐            │
│              │    MemoryExplainerCore              │            │
│              │  @Generable structured output       │            │
│              │  + Tool calling (source reading)    │            │
│              └───────────────┬─────────────────────┘            │
│                              ▼                                  │
│              ┌─────────────────────────────────────┐            │
│              │  Apple Foundation Models (3B LLM)   │            │
│              │      On-device • Private • Fast     │            │
│              └─────────────────────────────────────┘            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Tools

| Command | Usage | Output |
|---------|-------|--------|
| `explain_here` | At any breakpoint | What's happening, variable observations, next steps |
| `crash_explain --explain` | When stopped at crash | Crash type, root cause, fix, confidence |
| `crash_explain --json` | When stopped at crash | Raw JSON for scripting |
| `memory_explain` | Any time | Memory overview and potential issues |
| `memory-explainer --battle` | CLI | Model vs model test (generates crash, then explains it) |

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

### 3. Test the model's reasoning

```bash
memory-explainer --battle
```

Generates a random crash, then tries to explain it. Useful for validating the model actually understands crash patterns.

## How it works

- **Structured output**: Uses `@Generable` macros so the model can only output valid crash types and fields - no hallucinated function names
- **codemap integration**: Understands your codebase structure for better context
- **Token-aware**: Automatically trims data to fit Foundation Models' context window
- **Source reading**: With `--tools` flag, the model can read your actual source files

## Repo structure

```
XcodeLLMToolchain/
├── MemoryExplainer/
│   └── Sources/
│       ├── MemoryExplainer/        # CLI
│       └── MemoryExplainerCore/    # Engine, @Generable types, tools
├── MemoryExplainerApp/             # Menu bar app (coming soon)
├── lldb/                           # LLDB Python scripts
│   ├── plugin.py                   # Entry point
│   └── capture_lib/                # Analysis, formatting, utilities
└── repro/                          # Test crash suites
```

## Why this exists

macOS 26 introduced two things that make this possible:

1. **xzone_malloc + MTE**: Memory bugs are now deterministic. Crashes have clear "receipts" instead of random corruption.
2. **Foundation Models**: Apple's on-device 3B LLM. Fast, private, no network required.

Combine them with LLDB and you get AI-powered debugging that runs entirely on your Mac.

## License

MIT
