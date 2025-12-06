#!/bin/bash
set -euo pipefail

REPO_RAW_URL=${XCODE_LLM_REPO:-"https://raw.githubusercontent.com/JordanCoin/XcodeLLMToolchain/main/lldb"}
TARGET_DIR="$HOME/Library/Application Support/XcodeLLMToolchain/lldb"
LLDBINIT="$HOME/.lldbinit-Xcode"
FILES=("plugin.py" "capture_lib/__init__.py" "capture_lib/analysis.py" "capture_lib/commands.py" "capture_lib/formatting.py" "capture_lib/tools.py" "capture_lib/utils.py")

banner() {
  cat <<'BANNER'

  ██╗  ██╗ ██████╗ ██████╗ ██████╗ ███████╗██╗     ██╗     ███╗   ███╗
  ╚██╗██╔╝██╔════╝██╔═══██╗██╔══██╗██╔════╝██║     ██║     ████╗ ████║
   ╚███╔╝ ██║     ██║   ██║██║  ██║█████╗  ██║     ██║     ██╔████╔██║
   ██╔██╗ ██║     ██║   ██║██║  ██║██╔══╝  ██║     ██║     ██║╚██╔╝██║
  ██╔╝ ██╗╚██████╗╚██████╔╝██████╔╝███████╗███████╗███████╗██║ ╚═╝ ██║
  ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚═╝     ╚═╝

  XcodeLLM installed successfully!

  Commands available in LLDB:
    explain_here   - Explain current breakpoint state
    crash_explain  - Analyze crashes (--explain for LLM)
    memory_explain - Analyze memory usage

  Next: Build the CLI for full LLM analysis:
    git clone https://github.com/JordanCoin/XcodeLLMToolchain.git
    cd XcodeLLMToolchain && swift build

BANNER
}

echo "Installing XcodeLLM LLDB scripts..."
echo ""

mkdir -p "$TARGET_DIR"
mkdir -p "$TARGET_DIR/capture_lib"

for file in "${FILES[@]}"; do
  echo "  Downloading $file"
  curl -fsSL "$REPO_RAW_URL/$file" -o "$TARGET_DIR/$file"
done

# Only add import for plugin.py (it imports the rest)
IMPORT_LINE="command script import \"$TARGET_DIR/plugin.py\""
if [ ! -f "$LLDBINIT" ]; then
  echo "# XcodeLLM" > "$LLDBINIT"
  echo "$IMPORT_LINE" >> "$LLDBINIT"
elif ! grep -Fq "XcodeLLMToolchain" "$LLDBINIT"; then
  echo "" >> "$LLDBINIT"
  echo "# XcodeLLM" >> "$LLDBINIT"
  echo "$IMPORT_LINE" >> "$LLDBINIT"
fi

echo ""
echo "Installed to: $TARGET_DIR"
echo "LLDB init:    $LLDBINIT"
echo ""
banner
