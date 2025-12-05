#!/bin/bash
set -euo pipefail

REPO_RAW_URL=${MEMORY_EXPLAINER_REPO:-"https://raw.githubusercontent.com/you/memory-explainer-tools/main/lldb"}
TARGET_DIR="$HOME/Library/Application Support/MemoryExplainer/lldb"
LLDBINIT="$HOME/.lldbinit-Xcode"
FILES=("crash_capture.py")

banner() {
  cat <<'BANNER'
 __  __                                      ______            _             
|  \/  | ___ _ __ ___  _ __ ___  _   _ _ __ |  ____|          | |            
| |\/| |/ _ \ '__/ _ \| '_ ` _ \| | | | '_ \| |__ ___  ___  __| |_ __  _   _ 
| |  | |  __/ | | (_) | | | | | | |_| | | | |  __/ _ \/ _ \/ _` | '_ \| | | |
|_|  |_|\___|_|  \___/|_| |_| |_|\__,_|_| |_|_|  \___/\___/\__,_| .__/ \__, |
                                                             | |     __/ |
                                                             |_|    |___/ 
Memory Explainer LLDB scripts installed. We're so back, fam.
BANNER
}

mkdir -p "$TARGET_DIR"

for file in "${FILES[@]}"; do
  echo "Downloading $file → $TARGET_DIR"
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
