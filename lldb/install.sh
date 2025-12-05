#!/bin/bash
# Install memory-explainer LLDB commands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLDBINIT="$HOME/.lldbinit-Xcode"
IMPORT_LINE="command script import $SCRIPT_DIR/crash_capture.py"

echo "Installing memory-explainer LLDB commands..."

# Check if already installed
if [ -f "$LLDBINIT" ] && grep -q "crash_capture.py" "$LLDBINIT"; then
    echo "Already installed in $LLDBINIT"
    exit 0
fi

# Append to .lldbinit-Xcode
echo "" >> "$LLDBINIT"
echo "# memory-explainer crash analysis" >> "$LLDBINIT"
echo "$IMPORT_LINE" >> "$LLDBINIT"

echo "Installed! Added to $LLDBINIT:"
echo "  $IMPORT_LINE"
echo ""
echo "Restart Xcode to use. In LLDB console:"
echo "  (lldb) crash_explain"
