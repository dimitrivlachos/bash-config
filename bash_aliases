#!/bin/bash
# ==============================================================================
# SHARED ALIASES
# ==============================================================================
# Common aliases available across all systems/specialisations.
# Machine-specific aliases should be defined in specialisations/bashrc_*
#
# Note: Prompt toggle functions (tgit, tvenv, tdir, tem, ph) are defined
# in bash_prompt and are available directly as commands - no aliases needed.
# ==============================================================================

# ------------------------------------------------------------------------------
# Core System
# ------------------------------------------------------------------------------

# Aliases for modern CLI tools when available.
# Uses distro-specific fallback command names where needed:
# - Ubuntu/Debian often ship bat as "batcat"
# - Ubuntu/Debian often ship fd as "fdfind"
# This keeps the interactive aliases portable without requiring local symlinks.
if command -v eza &>/dev/null; then
    alias ls='eza'
    alias ll='eza -la --git'
    alias lt='eza --tree --level=2'
else
    alias ls='ls --color=auto'
    alias ll='ls -la --color=auto'
fi

# Prefer upstream bat name, but support Ubuntu's batcat package name.
if command -v bat &>/dev/null; then
    alias cat='bat --paging=never'
elif command -v batcat &>/dev/null; then
    alias cat='batcat --paging=never'
fi

# ripgrep exposes the rg binary name consistently across distros.
if command -v rg &>/dev/null; then
    alias grep='rg'
fi

# Prefer upstream fd name, but support Ubuntu's fdfind package name.
if command -v fd &>/dev/null; then
    alias find='fd'
elif command -v fdfind &>/dev/null; then
    alias find='fdfind'
fi

# General shortcuts
alias clear='\clear && ff'           # Clear screen and run fastfetch
alias clearf='clear'                 # Legacy alias for clear with fastfetch
alias clearall='\clear'              # Regular clear without fastfetch

# ------------------------------------------------------------------------------
# Conda/Mamba Environment Management
# ------------------------------------------------------------------------------
alias ma='mamba activate '
alias md='mamba deactivate'
alias maeb='mae && cd build/'        # Activate local env and enter build dir

# ------------------------------------------------------------------------------
# Prompt Helpers (shortcuts to bash_prompt functions)
# ------------------------------------------------------------------------------
alias rp='set_prompt'                # Reset/refresh prompt

# ------------------------------------------------------------------------------
# Kubernetes
# ------------------------------------------------------------------------------
alias k='kubectl'

# ------------------------------------------------------------------------------
# Configuration Management
# ------------------------------------------------------------------------------
alias git-setup='bc_setup_git_config'