# Memory Explainer - Architecture & Roadmap

## Vision
A single macOS menu bar app that bundles everything a developer needs for memory debugging:
- Live monitoring while app runs
- Deep inspection when paused in debugger
- AI-powered explanations using on-device LLM

## Current Status (v0.1)

### Working
- [x] Menu bar app with SwiftUI MenuBarExtra
- [x] Auto-detect Xcode debugging (debugserver parent process)
- [x] Live memory stats via `footprint` command
- [x] Thread count monitoring
- [x] xctrace integration for 30s Instruments recordings
- [x] Allocation parsing from xctrace XML export
- [x] Foundation Models LLM integration (4096 token limit)
- [x] codemap integration for code context (truncated to fit tokens)
- [x] SwiftUI previews for development

### LLDB Scripts (Separate)
- [x] `crash_explain` - Captures crash context
- [x] `memory_explain` - Shows top allocations
- [ ] Not yet bundled with app

## Next Phase: Bundled Distribution

### Goal
Single `.app` download that:
1. Provides menu bar monitoring out of the box
2. Offers to install LLDB commands on first launch
3. LLDB commands call back to bundled CLI for LLM access

### Bundle Structure
```
Memory Explainer.app/
├── Contents/
│   ├── MacOS/
│   │   ├── MemoryExplainerApp      # Main menu bar app
│   │   └── memory-explainer-cli    # CLI for LLDB callbacks
│   ├── Resources/
│   │   └── lldb/
│   │       ├── crash_capture.py    # LLDB Python scripts
│   │       └── install.sh          # Installer script
│   └── Info.plist
```

### First Launch Flow
```
┌─────────────────────────────────────────────┐
│  Welcome to Memory Explainer!               │
│                                             │
│  Would you like to install LLDB commands?   │
│                                             │
│  This will add crash_explain and            │
│  memory_explain to your Xcode debugger.     │
│                                             │
│  [Skip]                    [Install]        │
└─────────────────────────────────────────────┘
```

### Install Action
1. Copy `crash_capture.py` to `~/.lldb/memory-explainer/`
2. Add to `~/.lldbinit`:
   ```
   command script import ~/.lldb/memory-explainer/crash_capture.py
   ```
3. Update scripts to call bundled CLI:
   ```python
   CLI_PATH = "/Applications/Memory Explainer.app/Contents/MacOS/memory-explainer-cli"
   ```

## Implementation Tasks

### Phase 1: CLI Target
- [ ] Add CLI target to Xcode project
- [ ] Share core code between app and CLI
- [ ] CLI accepts JSON input, outputs explanation
- [ ] Test CLI independently

### Phase 2: Bundle Scripts
- [ ] Add Resources/lldb folder to bundle
- [ ] Update Python scripts to find bundled CLI
- [ ] Add install.sh that handles ~/.lldbinit safely
- [ ] Test full LLDB workflow

### Phase 3: First Launch UI
- [ ] Detect if LLDB scripts installed (check ~/.lldbinit)
- [ ] Show install prompt on first launch
- [ ] Handle install success/failure
- [ ] Add "Reinstall LLDB Commands" to Settings

### Phase 4: Polish
- [ ] App icon
- [ ] Code signing for distribution
- [ ] Notarization
- [ ] GitHub releases with DMG
- [ ] Homebrew cask formula

## Technical Notes

### Foundation Models Limits
- **4096 tokens** combined input/output
- codemap context truncated to 1000 chars
- Top 5 allocations sent to LLM
- Keep prompts concise

### Process Detection
```swift
// Find processes whose parent is debugserver
ps -eo pid,ppid,comm | grep debugserver  // Find debugserver PIDs
// Then find processes with those PPIDs
```

### xctrace Integration
```bash
# Record
xctrace record --template Allocations --time-limit 30s --attach PID --output file.trace

# Export
xctrace export --input file.trace --xpath '/trace-toc/run[@number="1"]/tracks/track[@name="Allocations"]/details/detail[@name="Statistics"]'
```

### Memory Reading
```bash
# Accurate memory footprint
footprint PID
# Output: "Footprint: 29 MB"

# Fallback
ps -o rss= -p PID  # Returns KB
```

## Research Links
- [Foundation Models](https://developer.apple.com/documentation/FoundationModels)
- [LLDB Python](https://github.com/DerekSelander/LLDB)
- [xzone_malloc](https://github.com/apple-oss-distributions/libmalloc/blob/main/doc/xzone_malloc.md)
- [Memory Integrity Enforcement](https://security.apple.com/blog/memory-integrity-enforcement)

## Future Ideas
- Allocation trend graphs over time
- Memory diff between recordings
- Export shareable reports
- Slack/Discord integration for team debugging
- Watch for memory spikes and auto-explain
