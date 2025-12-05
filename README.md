# memory-explainer-tools

> I'm Jordan — rogue iOS engineer, creator of codemap, and the guy who ships unhackable tools in a weekend. Memory Explainer is my latest gremlin: a macOS menu-bar app that lets Apple's on-device 3B LLM roast your leaks while you debug.

## Hybrid open-source drop
- **Open now:** LLDB command scripts + the **MemoryExplainerCore** Swift package that talks to xctrace, codemap, and the Foundation Model. Drop it into your own tooling or keep it CLI-only.
- **Closed for now:** The polished menu bar UI + signing/distribution bits live in a private Xcode repo. You'll get signed binaries so you can ship today while I keep the sauce hot.
- **Why:** I want you to steal the debugger magic, fork it, and bend it. The UX is staying closed so I can keep shipping chaos without babysitting forks. Call it source-available with a free-range attitude.

## Why this exists in 2025
- xzone_malloc + MTE means memory crimes are finally **deterministic** — the blast radius is obvious instead of random segfault roulette.
- Apple Intelligence ships a 3B LLM on-device. It's sitting there bored. Let it narrate your memory sins in English while you work offline.
- codemap stitches your code graph to the crash site, so the LLM knows which module is the clown.
- LLDB + xctrace feed it receipts. Your retain cycles can't hide. Bro, we're so back.

## One-click install (LLDB commands)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/you/memory-explainer-tools/main/lldb/install.sh)"
```
- Drops the scripts into `~/Library/Application Support/MemoryExplainer/lldb/`
- Appends `command script import` lines to `~/.lldbinit-Xcode`
- Prints an ASCII banner so you know it's real

## Pulling the LLM bits out of Xcode
- Use `MemoryExplainerCore` (Swift package) as the boundary between the public tooling and the private menu bar app.
- The Xcode project can stay private; point it at this package via SwiftPM and swap in your own `LLMClient` if you want a different backend.
- The CLI target `memory-explainer` is now just a thin wrapper around the core so you can script it without touching Xcode.

## Real outputs (no cherry-pick)
### `crash_explain` roasting a UAF
```
(lldb) crash_explain
🚨 xzone_malloc/MTE flagged a use-after-free.
Last owner: Capture in AuthViewModel.deinit → Task { [weak self] }
Freed on dismiss, closure ran anyway. Bro, you're writing ghost objects. Fix the retain rules or add a cancel bag.
```

### `memory_explain` calling out String storms
```
(lldb) memory_explain
Allocations: 38k small (String.init/UTF8), 420 medium (Data→String bridging)
Footprint: 1.2 GB with 7x growth in 30s trace.
English translation: You're JSON-deserializing the same payload in a loop. Cache the damn string or move parsing off the hot path. Fam, NSLog era is over.
```

## How it fits together
- **Process detection:** Watches for debugserver children so it knows when you're in Xcode.
- **xctrace dance:** Captures 30s allocation traces, parses top offenders, and tags them with codemap context.
- **Foundation Models:** On-device LLM turns raw allocations into roasts. No cloud, no privacy lawyers.
- **Menu bar brain:** Swift core coordinates Instruments, LLDB, and codemap so the UI can stay pretty (and closed-source for now).

## Repo layout
```
memory-explainer-tools/
├── MemoryExplainer/            # Core Swift logic (Instruments, codemap, LLM bridge)
├── lldb/                       # LLDB Python scripts + installer
├── docs/                       # Launch thread, notes, whatever
└── README.md                   # You're here
```

## License
MIT. Hack it, fork it, make it worse. Just don't blame me when your leaks start talking back.
