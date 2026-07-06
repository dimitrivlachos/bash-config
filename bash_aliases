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

# Wrap grep/find to print an occasional one-line hint toward rg/fd, while still
# running the real binary. Behaviour is unchanged for scripts and pipelines.
#
# unalias first, on its own line: aliases expand at parse time, so the stock
# `grep --color=auto` alias would break the grep() definition below. Splitting
# the statement clears the alias before the function block is parsed.
unalias grep find 2>/dev/null

# Hint at most once per 12h per tool, tracked by mtime in a cache file. A shell
# variable won't work: piped `... | grep` runs the function in a subshell, so
# the guard wouldn't persist. Builtins only, to avoid recursing into grep/find.
_search_nudge() {  # $1 = cache key, $2 = message
    [[ $- == *i* && -z $NO_SEARCH_NUDGE ]] || return 0
    local f="${XDG_CACHE_HOME:-$HOME/.cache}/search-nudge-$1" now last
    printf -v now '%(%s)T' -1
    last=$(<"$f") 2>/dev/null
    (( now - ${last:-0} < 43200 )) && return 0
    printf '%s' "$now" >"$f" 2>/dev/null
    printf '\e[2m%s\e[0m\n' "$2" >&2  # dim, to stderr so pipes stay clean
}

if command -v rg &>/dev/null; then
    grep() {
        _search_nudge grep '(tip: `rg` is faster and prettier for interactive search)'
        command grep --color=auto "$@"
    }
else
    # No rg: skip the wrapper but keep colored grep, so this file stands alone.
    alias grep='grep --color=auto'
fi
if command -v fd &>/dev/null || command -v fdfind &>/dev/null; then
    find() {
        _search_nudge find '(tip: `fd` is faster for simple filename searches)'
        command find "$@"
    }
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