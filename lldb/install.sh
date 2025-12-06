#!/bin/bash
set -euo pipefail

REPO_RAW_URL=${XCODE_LLM_REPO:-"https://raw.githubusercontent.com/JordanCoin/XcodeLLMToolchain/main/lldb"}
TARGET_DIR="$HOME/Library/Application Support/XcodeLLMToolchain/lldb"
LLDBINIT="$HOME/.lldbinit-Xcode"
FILES=("plugin.py" "capture_lib/__init__.py" "capture_lib/analysis.py" "capture_lib/commands.py" "capture_lib/formatting.py" "capture_lib/tools.py" "capture_lib/utils.py")

banner() {
  cat <<'BANNER'
 __  __         _        _    _    __  __ _____         _     _           _
 \ \/ /__ ___  | |_ ___ | |  | |  |  \/  |_   _|__  ___| |___| |__   __ _(_)_ __
  \  // _/ _ \ | __/ _ \| |  | |  | |\/| | | |/ _ \/ _ \ / __| '_ \ / _` | | '_ \
  /  \ (_| (_) || || (_) | |__| |__| |  | | | | (_) | (_) | (__| | | | (_| | | | | |
 /_/\_\___\___/ \__\___/|____|____|_|  |_| |_|\___/ \___/\___|_| |_|\__,_|_|_| |_|

XcodeLLMToolchain installed successfully.
BANNER
}

mkdir -p "$TARGET_DIR"
mkdir -p "$TARGET_DIR/capture_lib"

for file in "${FILES[@]}"; do
  echo "Downloading $file → $TARGET_DIR/$file"
  curl -fsSL "$REPO_RAW_URL/$file" -o "$TARGET_DIR/$file"
  chmod +x "$TARGET_DIR/$file" || true
  IMPORT_LINE="command script import $TARGET_DIR/$file"
  if [ ! -f "$LLDBINIT" ] || ! grep -Fq "$IMPORT_LINE" "$LLDBINIT"; then
    {
      echo "# memory-explainer-tools"
      echo "$IMPORT_LINE"
    } >> "$LLDBINIT"
  fi
  echo "Ensured $LLDBINIT imports $file"
  echo "(lldb) crash_explain    # explain current crash"
  echo "(lldb) memory_explain   # explain current memory story"
  echo ""

done

echo "Installed scripts in: $TARGET_DIR"
echo "LLDB init: $LLDBINIT"
banner
