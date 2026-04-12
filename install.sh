#!/bin/bash
set -euo pipefail

# Get the path to this script's directory
CONFIG_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TARGET="$HOME/.bashrc"
TARGET_LINK="$HOME/.bashrc_core"
SECRETS_FILE="$CONFIG_REPO/secrets/bash_secrets.sh"

# Initialize submodules (secrets directory)
if [[ -f "$CONFIG_REPO/.gitmodules" ]]; then
  echo "[INFO] Initializing git submodules..."
  cd "$CONFIG_REPO"
  git submodule update --init --recursive 2>/dev/null || {
    echo "[WARN] Could not initialize secrets submodule (private repo access needed)"
    echo "       You can set up secrets manually from the templates in secrets/"
  }
fi

# Parse arguments
SPECIALISATION="${1:-}"
TARGET_BASHRC="${2:-$DEFAULT_TARGET}"

# Prompt for specialisation if not provided
if [[ -z "$SPECIALISATION" ]]; then
  echo "Which specialisation are you setting up?"
  select SPECIALISATION in "frostpaw" "diamond" "asteria"; do
    [[ -n "$SPECIALISATION" ]] && break
  done
fi

# Confirm target file exists
if [[ ! -f "$TARGET_BASHRC" ]]; then
  echo "[ERROR] Target file $TARGET_BASHRC does not exist."
  echo "        Please create it or specify a valid path."
  exit 1
fi

echo "[INFO] Linking bashrc_core -> $TARGET_LINK"
ln -sf "$CONFIG_REPO/bashrc_core" "$TARGET_LINK"

# Remove existing block if present
if grep -q "# >>> bash-config initialize >>>" "$TARGET_BASHRC"; then
  echo "[INFO] Removing existing bash-config block from $TARGET_BASHRC"
  sed -i '/# >>> bash-config initialize >>>/,/# <<< bash-config initialize <<</d' "$TARGET_BASHRC"
fi

# Append clean managed block
{
  echo ""
  echo "# >>> bash-config initialize >>>"
  echo "# !! This block is managed by the bash-config installer !!"
  echo "export BASH_SPECIALISATION=\"$SPECIALISATION\""
  echo "source ~/.bashrc_core"
  echo "# <<< bash-config initialize <<<"
  echo ""
} >> "$TARGET_BASHRC"

echo "[INFO] Appended bash-config block to $TARGET_BASHRC"

# Create secrets file if missing
if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "[INFO] Creating placeholder secrets/bash_secrets.sh"
  mkdir -p "$CONFIG_REPO/secrets"
  cat << EOF > "$SECRETS_FILE"
# Add secrets like:
# export DIAMOND_USERNAME="your_username"
# export DIAMOND_GITHUB_KEY="~/.ssh/id_work_key"
EOF
fi

echo "[✅] Install complete."
echo ""

# ==============================================================================
# POST-INSTALL SETUP WIZARD
# ==============================================================================
# Source only the specific modules needed for the wizard rather than the full
# bashrc_core — avoids side effects from history traps, PROMPT_COMMAND
# patching, fastfetch, and update checks running inside a script context.
_bc_install_source_config() {
  export BASH_SPECIALISATION="$SPECIALISATION"
  export BASH_CONFIG_DIR="$CONFIG_REPO"
  # shellcheck source=/dev/null
  source "$CONFIG_REPO/bash_tools"   2>/dev/null || true   # bc_log_*, bc_setup_git_config, bc_validate_config
  # shellcheck source=/dev/null
  source "$CONFIG_REPO/bash_certs"   2>/dev/null || true   # bc_setup_certs, bc_check_certs
  # shellcheck source=/dev/null
  source "$CONFIG_REPO/bash_history" 2>/dev/null || true   # bc_setup_atuin_config, bc_verify_atuin
  # shellcheck source=/dev/null
  source "$CONFIG_REPO/bash_ssh"     2>/dev/null || true   # bc_setup_ssh_config, bc_setup_sk_ssh_handles
}

_bc_run_setup_steps() {
  _bc_install_source_config

  echo "Would you like to run optional post-install steps now?"
  echo ""
  echo "  [1] Set up Git configuration  (generate ~/.gitconfig)"
  echo "  [2] Set up SSH configuration  (link config + SK key handles)"
  echo "  [3] Validate installation     (bc_validate_config)"
  if [[ "$SPECIALISATION" == "frostpaw" ]]; then
  echo "  [4] Set up certificates       (install Caddy root CA + verify atuin)"
  fi
  echo "  [0] Skip — I will set up manually later"
  echo ""

  local choice=""
  # Read explicitly from /dev/tty so stdin state cannot interfere
  while [[ -z "$choice" ]]; do
    read -rp "Enter numbers separated by spaces, or 0 to skip: " choice </dev/tty || {
      echo ""
      echo "[INFO] Could not read input — skipping setup steps."
      return 0
    }
  done

  local did_anything=false

  for opt in $choice; do
    case "$opt" in
      1)
        echo ""
        echo "[INFO] Running Git configuration setup..."
        if bc_setup_git_config; then
          did_anything=true
        fi
        ;;
      2)
        echo ""
        echo "[INFO] Setting up SSH config symlink and SK key handles..."
        if bc_setup_ssh_config; then
          did_anything=true
        fi
        ;;
      3)
        echo ""
        echo "[INFO] Validating installation..."
        bc_validate_config
        did_anything=true
        ;;
      4)
        echo ""
        echo "[INFO] Setting up atuin config..."
        bc_setup_atuin_config || true
        echo ""
        echo "[INFO] Installing CA certificates..."
        if bc_setup_certs; then
          did_anything=true
          echo ""
          echo "[INFO] Verifying atuin connectivity..."
          bc_verify_atuin || true
        fi
        ;;
      0)
        break
        ;;
      *)
        echo "[WARN] Unknown option: $opt (skipping)"
        ;;
    esac
  done

  echo ""
  if [[ "$did_anything" == "true" ]]; then
    echo "[INFO] Setup steps completed."
  fi
}

if [[ -t 1 ]]; then
  _bc_run_setup_steps
else
  echo "[INFO] Non-interactive mode — skipping post-install menu."
fi

echo ""
echo "Next steps (if not done above):"
echo "  git-setup            — generate ~/.gitconfig from templates"
echo "  ssh-setup            — link SSH config + connect to bastion"
echo "  bc_validate_config   — check everything is set up correctly"
echo ""
echo "Reload your shell:  source $TARGET_BASHRC"