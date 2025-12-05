#!/usr/bin/env swift
/**
 * Crash Generator - Uses Foundation Models to create adversarial crash scenarios
 *
 * Usage: swift generate_crash.swift | memory-explainer
 */

import Foundation
import FoundationModels

let prompt = """
Generate a tricky iOS crash JSON. Pick: race condition, delayed UAF, or nil from unexpected source.

Output ONLY JSON:
{"crash":{"stop_description":"msg","frames":[{"function":"f","file":"X.swift","line":1,"variables":[{"name":"x","value":"v"}]}]}}

Use realistic Swift/UIKit names. Make root cause non-obvious.
"""

func run() async {
    do {
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        print(response.content)
    } catch {
        fputs("Error generating crash: \(error)\n", stderr)
    }
}

// Run async
let semaphore = DispatchSemaphore(value: 0)
Task {
    await run()
    semaphore.signal()
}
semaphore.wait()
