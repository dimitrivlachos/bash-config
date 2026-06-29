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

# Note: ripgrep (rg) is intentionally NOT aliased to grep. It is not a drop-in
# replacement (e.g. -E means --encoding, it recurses by default, and respects
# .gitignore), which silently breaks scripts and pipelines expecting real grep.

# fd is NOT a drop-in for find (no -L/-iname/-exec syntax), so keep
# the real find and just normalise fd's name across distros.
if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    alias fd='fdfind'
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