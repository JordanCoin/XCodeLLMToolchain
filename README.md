# Memory Explainer

A macOS menu bar app that explains memory issues using Apple's on-device LLM. Detects Xcode debugging sessions, records Instruments data, and provides AI-powered memory analysis - all from your menu bar.

## Features

- **Auto-detect Xcode debugging** - Knows when you're debugging an app
- **Live memory stats** - Memory usage and thread count at a glance
- **Instruments integration** - Record 30s allocation traces via xctrace
- **AI explanations** - On-device Foundation Models explains your memory usage
- **Code context** - codemap integration shows how your code connects
- **Bundled LLDB tools** - Deep inspection commands when paused in debugger

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Memory Explainer.app                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │  Menu Bar UI │  │  CLI Tool    │  │  LLDB Scripts            │  │
│  │  (SwiftUI)   │  │  (for LLDB)  │  │  crash_explain           │  │
│  │              │  │              │  │  memory_explain          │  │
│  └──────┬───────┘  └──────┬───────┘  └────────────┬─────────────┘  │
│         │                 │                       │                 │
│         └─────────────────┴───────────────────────┘                 │
│                           │                                         │
│  ┌────────────────────────┴────────────────────────────────────┐   │
│  │                    Shared Core                               │   │
│  │  • Process detection (debugserver parent)                    │   │
│  │  • Memory analysis (footprint, xctrace)                      │   │
│  │  • Foundation Models LLM (on-device 3B)                      │   │
│  │  • codemap integration (code structure)                      │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Two Ways to Use

### 1. Menu Bar App (Live Monitoring)
Run the app, debug something in Xcode, click the chip icon:
- See memory/thread stats update live
- Click "Record 30s" to capture allocation data
- Click "Explain" for AI analysis

### 2. LLDB Commands (Deep Inspection)
When paused at a breakpoint or crash in Xcode:
```
(lldb) crash_explain     # Explain current crash
(lldb) memory_explain    # Analyze memory allocations
```

## Requirements

- **macOS 26 (Tahoe)** - For Foundation Models (on-device LLM)
- **Xcode 26** - For debugging and xctrace
- **Apple Silicon Mac** with Apple Intelligence enabled
- **codemap** (optional): `brew install jordancoin/tap/codemap`

## Installation

### From Release
1. Download `Memory Explainer.app` from Releases
2. Move to Applications
3. Launch - it'll offer to install LLDB commands

### From Source
```bash
git clone https://github.com/you/memory-explainer
cd memory-explainer
open MemoryExplainerApp.xcodeproj
# Build and run (Cmd+R)
```

## What It Explains

| You see... | Memory Explainer adds... |
|------------|-------------------------|
| `Malloc 32 Bytes: 15,000` | "Small allocations typical of string/dictionary operations, not concerning" |
| `30 MB memory usage` | "Moderate for a SwiftUI app with this thread count" |
| `EXC_BAD_ACCESS` | "Use-after-free: object freed when view dismissed but closure retained it" |

## Project Structure

```
memory-explainer/
├── MemoryExplainerApp/          # Menu bar app (SwiftUI)
│   ├── App.swift                # Main app, MenuBarExtra UI
│   └── ProcessMonitor.swift     # Detection, xctrace, LLM
├── MemoryExplainerApp.xcodeproj # Xcode project
├── lldb/                        # LLDB Python scripts
│   └── crash_capture.py         # crash_explain, memory_explain
└── docs/
    └── PLAN.md                  # Architecture & roadmap
```

## How It Works

1. **Process Detection**: Monitors `ps` for processes whose parent is `debugserver` (Xcode debugging)
2. **Memory Stats**: Uses `footprint` command to get accurate memory usage
3. **Allocation Recording**: Runs `xctrace record --template Allocations` for 30s
4. **Allocation Export**: Parses xctrace XML output for top allocation categories
5. **LLM Analysis**: Sends memory data + codemap context to Foundation Models
6. **Code Context**: Finds project in DerivedData, runs `codemap --deps` for structure

## Roadmap

- [x] Menu bar app with live process detection
- [x] Memory stats display (footprint)
- [x] xctrace Instruments integration
- [x] Foundation Models LLM explanations
- [x] codemap integration for code context
- [ ] Bundle LLDB scripts with first-launch install
- [ ] CLI tool for LLDB script callbacks
- [ ] Allocation trend graphs
- [ ] Export reports

## Why This Exists

Apple's xzone_malloc + MTE makes memory bugs **deterministic** - crashes happen reliably at the point of corruption, not randomly later. This means:

- Better crash data for AI to reason about
- codemap shows the "why" (code structure)
- LLDB/xctrace shows the "what" (runtime state)
- Foundation Models explains it in plain English

## License

MIT
