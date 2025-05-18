#!/bin/bash
set -euo pipefail

# Get the path to this script's directory
CONFIG_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_BASHRC="$HOME/.bashrc"
TARGET_LINK="$HOME/.bashrc_core"
SECRETS_FILE="$CONFIG_REPO/secrets/bash_secrets.sh"

# Detect or get specialisation
SPECIALISATION="${1:-}"
if [[ -z "$SPECIALISATION" ]]; then
  echo "Which specialisation are you setting up?"
  select SPECIALISATION in "frostpaw" "diamond"; do
    [[ -n "$SPECIALISATION" ]] && break
  done
fi

echo "[INFO] Linking bashrc_core -> $TARGET_LINK"
ln -sf "$CONFIG_REPO/bashrc_core" "$TARGET_LINK"

# Ensure ~/.bashrc exports the specialisation and sources bashrc_core
if ! grep -q "source ~/.bashrc_core" "$TARGET_BASHRC"; then
  echo "[INFO] Adding specialisation and source lines to $TARGET_BASHRC"
  echo "export BASH_SPECIALISATION=\"$SPECIALISATION\"" >> "$TARGET_BASHRC"
  echo "source ~/.bashrc_core" >> "$TARGET_BASHRC"
else
  echo "[INFO] ~/.bashrc already sources ~/.bashrc_core"
fi

# Create secrets dir and template if missing
if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "[INFO] Creating placeholder secrets/bash_secrets.sh"
  mkdir -p "$CONFIG_REPO/secrets"
  cat << EOF > "$SECRETS_FILE"
# Add secrets like:
# export DIAMOND_API_TOKEN="..."
# export SSH_KEY_PATH="..."
EOF
fi

echo "[✅] Install complete. Restart your shell or run:"
echo "     source ~/.bashrc_core $SPECIALISATION"
