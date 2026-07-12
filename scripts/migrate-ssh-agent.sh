#!/bin/bash
# ==============================================================================
# SSH AGENT MIGRATION
# ==============================================================================
# Moves an existing machine over to the new ssh agent setup: one agent per
# machine, keys cached on first use via AddKeysToAgent. Cleans up the state
# left behind by the old per-shell agent machinery.
#
# Usage:  ./scripts/migrate-ssh-agent.sh
# Safe to re-run. Run 'git pull' in the repo first so the modules are current.
# ==============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BASH_CONFIG_DIR="$REPO"

# shellcheck source=/dev/null
source "$REPO/bash_logging"
# shellcheck source=/dev/null
source "$REPO/bash_ssh"

# bc_setup_ssh_keys needs the specialisation; pick it up from the managed
# block in ~/.bashrc if this script is run outside a configured shell
if [[ -z "${BASH_SPECIALISATION:-}" ]]; then
  BASH_SPECIALISATION=$(grep -oP 'BASH_SPECIALISATION="\K[^"]+' "$HOME/.bashrc" 2>/dev/null || true)
  export BASH_SPECIALISATION
fi

short_host="${HOSTNAME:-$(uname -n)}"
bc_log_info "Migrating ${short_host%%.*} (${BASH_SPECIALISATION:-unknown specialisation}) to the new ssh agent setup"
echo

# ------------------------------------------------------------------------------
# 1. Remove state files from the old per-shell agent machinery
# ------------------------------------------------------------------------------
if [[ -f "$HOME/.ssh-agent-info" ]]; then
  rm "$HOME/.ssh-agent-info"
  bc_log_success "Removed old agent info file: ~/.ssh-agent-info"
fi
if [[ -d "$HOME/.ssh/agent" ]]; then
  rmdir "$HOME/.ssh/agent" 2>/dev/null \
    && bc_log_success "Removed empty ~/.ssh/agent directory" \
    || bc_log_warn "~/.ssh/agent is not empty, inspect and remove it manually"
fi

# ------------------------------------------------------------------------------
# 2. Set up the machine's single agent
# ------------------------------------------------------------------------------
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  bc_setup_ssh_agent_service

  # Keep the user manager alive across logout so the agent survives on
  # headless machines (same approach as the atuin daemon)
  if [[ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != "yes" ]]; then
    if loginctl enable-linger "$USER" 2>/dev/null; then
      bc_log_success "Enabled linger for $USER"
    else
      bc_log_warn "Could not enable linger, run: sudo loginctl enable-linger $USER"
    fi
  fi
else
  bc_log_info "No systemd user session here, shells will use the env-file agent fallback"
fi

# ------------------------------------------------------------------------------
# 3. Attach and kill off any agents piled up by the old setup
# ------------------------------------------------------------------------------
bc_ssh_agent_attach
bc_ssh_agent_prune

# ------------------------------------------------------------------------------
# 4. Make sure the ssh config deployment is current
# ------------------------------------------------------------------------------
bc_setup_ssh_config

# ------------------------------------------------------------------------------
# 5. Verify
# ------------------------------------------------------------------------------
echo
rc=0
ssh-add -l >/dev/null 2>&1 || rc=$?
if [[ $rc -le 1 ]]; then
  bc_log_success "Agent reachable at $SSH_AUTH_SOCK"
else
  bc_log_error "Agent not reachable, check systemctl --user status ssh-agent.service"
  exit 1
fi
# ssh -G normalises the value to true
if ssh -G github.com 2>/dev/null | grep -Eq "^addkeystoagent (true|yes)"; then
  bc_log_success "AddKeysToAgent active, keys will cache on first use"
else
  bc_log_warn "AddKeysToAgent not showing in ssh -G, is ~/.ssh/config up to date?"
fi

# ------------------------------------------------------------------------------
# 6. Offer key generation (interactive only)
# ------------------------------------------------------------------------------
if [[ -t 0 && -n "${BASH_SPECIALISATION:-}" ]]; then
  echo
  bc_setup_ssh_keys
else
  bc_log_info "Run bc_setup_ssh_keys from a shell to generate this machine's keys"
fi

echo
bc_log_success "Migration done. New shells attach to the agent automatically."
bc_log_info "First use of each key asks for its passphrase once, then it stays cached."
