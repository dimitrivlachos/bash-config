#!/bin/bash
set -euo pipefail

DEFAULT_TARGET="$HOME/.bashrc"
TARGET_BASHRC="${1:-$DEFAULT_TARGET}"
TARGET_LINK="$HOME/.bashrc_core"

echo "[INFO] Uninstalling bash-config from $TARGET_BASHRC"

# Validate target file exists
if [[ ! -f "$TARGET_BASHRC" ]]; then
  echo "[ERROR] Target file $TARGET_BASHRC does not exist."
  exit 1
fi

# 1. Remove ~/.bashrc_core symlink if it points to anything
if [[ -L "$TARGET_LINK" ]]; then
  echo "[INFO] Removing symlink: $TARGET_LINK"
  rm "$TARGET_LINK"
else
  echo "[INFO] No symlink found at $TARGET_LINK (skipped)"
fi

# 2. Remove managed block from target bashrc
if grep -q "# >>> bash-config initialize >>>" "$TARGET_BASHRC"; then
  echo "[INFO] Removing bash-config block from $TARGET_BASHRC"
  sed -i '/# >>> bash-config initialize >>>/,/# <<< bash-config initialize <<</d' "$TARGET_BASHRC"
else
  echo "[INFO] No bash-config block found in $TARGET_BASHRC (skipped)"
fi

# 3. Reminder about secrets
if [[ -f "./secrets/bash_secrets.sh" ]]; then
  echo "[NOTE] The secrets file still exists at ./secrets/bash_secrets.sh"
  echo "       You may delete it manually if no longer needed."
fi

echo "[✅] Uninstall complete. Open a new shell to confirm."