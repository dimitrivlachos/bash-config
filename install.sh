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

# Insert a managed block into ~/.bashrc with spacing
if grep -q "# >>> bash-config initialize >>>" "$TARGET_BASHRC"; then
  echo "[INFO] Removing existing bash-config block from $TARGET_BASHRC"
  sed -i '/# >>> bash-config initialize >>>/,/# <<< bash-config initialize <<</d' "$TARGET_BASHRC"
fi

echo "[INFO] Adding bash-config block to $TARGET_BASHRC"
{
  echo ""
  echo "# >>> bash-config initialize >>>"
  echo "# !! This block is managed by the bash-config installer !!"
  echo "export BASH_SPECIALISATION=\"$SPECIALISATION\""
  echo "source ~/.bashrc_core"
  echo "# <<< bash-config initialize <<<"
  echo ""
} >> "$TARGET_BASHRC"

# Create secrets dir and template if missing
if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "[INFO] Creating placeholder secrets/bash_secrets.sh"
  mkdir -p "$CONFIG_REPO/secrets"
  cat << EOF > "$SECRETS_FILE"
# Add secrets like:
# export DIAMOND_USERNAME="your_username"
# export DIAMOND_GITHUB_KEY="~/.ssh/id_work_key"
EOF
fi

echo "[✅] Install complete. Restart your shell or run:"
echo "     source ~/.bashrc_core"