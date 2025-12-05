#!/bin/bash
# Model vs Model: Generate a crash, then explain it
set -euo pipefail

cd "$(dirname "$0")"

echo "🎲 Generating adversarial crash..."
CRASH=$(swift generate_crash.swift 2>/dev/null | sed -n '/^{/,/^}/p')

if [ -z "$CRASH" ]; then
    echo "Failed to generate crash JSON"
    exit 1
fi

echo "📋 Generated crash:"
echo "$CRASH" | head -20
echo ""

echo "🧠 Asking explainer to diagnose..."
echo ""
echo "$CRASH" | ../MemoryExplainer/.build/debug/memory-explainer

echo ""
echo "---"
echo "🤔 Did it get it right? The crash was self-generated - check if explanation makes sense!"
