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

# Alias's for modern cli tools if available (eza, bat, rg, fd)
# Falls back to standard tools if not installed
if command -v eza &>/dev/null; then
    alias ls='eza'
    alias ll='eza -la --git'
    alias lt='eza --tree --level=2'
else
    alias ls='ls --color=auto'
    alias ll='ls -la --color=auto'
fi

command -v bat &>/dev/null && alias cat='bat --paging=never'
command -v rg  &>/dev/null && alias grep='rg'
command -v fd  &>/dev/null && alias find='fd'

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