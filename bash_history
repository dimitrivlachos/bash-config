#!/bin/bash
# ==============================================================================
# Enhanced History Management for Multi-Machine Environments
# ==============================================================================
# Optimized for Diamond Light Source infrastructure
#
# This module provides unified command history across multiple SSH sessions
# and machines, with advanced search, sync, and management capabilities.
# Atuin is used as the primary backend when available, with the custom
# HISTFILE-based system acting as fallback.
#
# Key Features:
# - Atuin primary backend (cross-machine sync, Ctrl+R search, per-command metadata)
# - Custom HISTFILE fallback for machines without atuin
# - HISTFILE maintained as passive text backup in both modes
# - Advanced search, statistics, and duplicate management (fallback mode)
# - Import/export functionality for migration
#
# Usage: Run 'hhelp' for detailed command reference
# ==============================================================================


# ==============================================================================
# ATUIN  (primary backend)
# ==============================================================================

# Detect atuin; all subsequent logic branches on BC_ATUIN_ACTIVE.
if command -v atuin >/dev/null 2>&1; then
  export BC_ATUIN_ACTIVE=1
  bc_log_debug "History: atuin detected — primary backend"
else
  export BC_ATUIN_ACTIVE=0
  bc_log_debug "History: atuin not found — using custom sync"
fi

# Source bash-preexec, which atuin requires to register its preexec/precmd hooks.
# Resolution order: system package → $HOME install → repo submodule.
# No-ops silently if already loaded (i.e. __bp_preexec_invoke_exec is defined).
bc_source_bash_preexec() {
  # Already loaded — nothing to do
  if declare -f __bp_preexec_invoke_exec >/dev/null 2>&1; then
    bc_log_debug "bash-preexec: already loaded"
    return 0
  fi

  local candidates=(
    "/usr/share/bash-preexec/bash-preexec.sh"   # Arch / Debian package
    "$HOME/.bash-preexec.sh"                     # Manual curl install
    "${BASH_CONFIG_DIR:-}/bash-preexec/bash-preexec.sh"  # Repo submodule
  )

  local f
  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      # shellcheck source=/dev/null
      source "$f"
      bc_log_debug "bash-preexec: sourced from $f"
      return 0
    fi
  done

  bc_log_warn "bash-preexec not found — atuin hooks will not be registered"
  bc_log_info "Run: git submodule update --init  (inside $BASH_CONFIG_DIR)"
  return 1
}

# Wire atuin (or the custom fallback) into PROMPT_COMMAND.
# Called by bashrc_core *after* PROMPT_COMMAND="set_prompt" so each backend
# can safely append without clobbering the prompt function.
#   atuin active:   set_prompt → __atuin_precmd → history -a
#   atuin absent:   set_prompt → history -a; history -c; history -r
bc_history_init() {
  if [[ "${BC_ATUIN_ACTIVE:-0}" == "1" ]]; then
    # bash-preexec must be sourced before atuin init so that atuin's
    # preexec/precmd hooks are registered into the bp arrays correctly.
    bc_source_bash_preexec
    eval "$(atuin init bash --disable-up-arrow)"
    # Passive append keeps HISTFILE as a human-readable fallback
    PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND}$'\n'}history -a"
    bc_log_debug "History PROMPT_COMMAND: atuin + passive HISTFILE append"
    # Override fallback functions with atuin redirect stubs.  Must be installed
    # here (inside bc_history_init, called after all fallback functions are
    # defined) so the stubs are not overwritten by the fallback definitions.
    _bc_atuin_redirect() {
      bc_log_warn "'$1' is disabled — atuin is the active history backend."
      bc_log_info "Use: atuin search  |  atuin history list  |  atuin sync"
    }
    hgrep()             { _bc_atuin_redirect "hg"; }
    recent_history()    { _bc_atuin_redirect "hr"; }
    hr_formatted()      { _bc_atuin_redirect "hrf"; }
    clean_history()     { _bc_atuin_redirect "hc"; }
    bc_history_stats()  { _bc_atuin_redirect "hstats"; }
    bc_history_search() { _bc_atuin_redirect "hsearch"; }
    bc_backup_history() { _bc_atuin_redirect "hbackup"; }
    bc_import_history() { _bc_atuin_redirect "himport"; }
    hhelp()             { _bc_atuin_redirect "hhelp"; }
    hquick()            { _bc_atuin_redirect "hquick"; }
    sync_history()      { atuin sync; }
  else
    # Fallback: full cross-session sync via HISTFILE
    PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND}$'\n'}history -a; history -c; history -r"
    bc_log_debug "History PROMPT_COMMAND: full sync (HISTFILE: $HISTFILE)"
  fi
}

# Verify that ATUIN_CONFIG_DIR points to the repo-managed config and that
# the config file exists.  Removes any stale symlink left from the old
# symlink-based setup.  Frostpaw only.
bc_setup_atuin_config() {
  if [[ "${BASH_SPECIALISATION:-}" != "frostpaw" ]]; then
    bc_log_warn "bc_setup_atuin_config is only supported on frostpaw systems"
    return 1
  fi

  local config_dir="$BASH_CONFIG_DIR/configs/atuin"
  local config_file="$config_dir/config.toml"

  if [[ ! -f "$config_file" ]]; then
    bc_log_error "Atuin config not found in repo: $config_file"
    return 1
  fi

  # Clean up legacy symlink if present
  local legacy_dest="$HOME/.config/atuin/config.toml"
  if [[ -L "$legacy_dest" ]]; then
    bc_log_info "Removing legacy symlink: $legacy_dest"
    rm "$legacy_dest"
  fi

  if [[ "${ATUIN_CONFIG_DIR:-}" == "$config_dir" ]]; then
    bc_log_success "ATUIN_CONFIG_DIR is set correctly: $config_dir"
  else
    bc_log_warn "ATUIN_CONFIG_DIR is not set (expected in bash_exports)"
    bc_log_info "Setting it now for this session"
    export ATUIN_CONFIG_DIR="$config_dir"
  fi
}

# Check whether bash-preexec is installed and loaded.
# Without it, atuin's precmd/preexec hooks are never called and history is not recorded.
bc_check_bash_preexec() {
  # Check if it's sourced in the current session (the definitive test)
  if declare -f __bp_preexec_invoke_exec >/dev/null 2>&1; then
    bc_log_success "bash-preexec is loaded in this session"
    return 0
  fi

  # Not loaded — check if it's installed but not yet sourced (e.g. first run before reload)
  local found_at=""
  if [[ -f /usr/share/bash-preexec/bash-preexec.sh ]]; then
    found_at="/usr/share/bash-preexec/bash-preexec.sh"
  elif [[ -f "$HOME/.bash-preexec.sh" ]]; then
    found_at="$HOME/.bash-preexec.sh"
  elif [[ -f "${BASH_CONFIG_DIR:-}/bash-preexec/bash-preexec.sh" ]]; then
    found_at="$BASH_CONFIG_DIR/bash-preexec/bash-preexec.sh"
  fi

  if [[ -n "$found_at" ]]; then
    bc_log_warn "bash-preexec is installed ($found_at) but not loaded in this session"
    bc_log_info "Reload your shell:  source ~/.bashrc"
    return 1
  fi

  bc_log_error "bash-preexec is not installed"
  bc_log_info "atuin will not record command history (timing, exit codes) without it"
  bc_log_info "The repo submodule should cover this automatically — check that it is initialised:"
  bc_log_info "  git submodule update --init  (inside $BASH_CONFIG_DIR)"
  bc_log_info "Or install via package manager:"
  bc_log_info "  Arch:          sudo pacman -S bash-preexec"
  bc_log_info "  Ubuntu/Debian: sudo apt install bash-preexec"
  return 1
}

# Verify connectivity to the atuin sync server by curling its root endpoint.
# A successful TLS handshake proves the CA cert is trusted by the system.
# On success, displays the server response (Terry Pratchett quote).
# Reads sync_address from $ATUIN_CONFIG_DIR/config.toml if present.
# Frostpaw only.
bc_verify_atuin() {
  if [[ "${BASH_SPECIALISATION:-}" != "frostpaw" ]]; then
    bc_log_warn "bc_verify_atuin is only supported on frostpaw systems"
    return 1
  fi

  # Check that atuin's recording hooks are wired into bash-preexec's arrays.
  # If they're missing, call bc_check_bash_preexec to diagnose why.
  local hooks_ok=true
  if [[ " ${preexec_functions[*]:-} " == *" __atuin_preexec "* ]]; then
    bc_log_success "atuin preexec hook registered (__atuin_preexec in preexec_functions)"
  else
    bc_log_error "atuin preexec hook NOT registered — commands will not be recorded"
    hooks_ok=false
  fi
  if [[ " ${precmd_functions[*]:-} " == *" __atuin_precmd "* ]]; then
    bc_log_success "atuin precmd hook registered (__atuin_precmd in precmd_functions)"
  else
    bc_log_error "atuin precmd hook NOT registered — exit codes and timing will not be recorded"
    hooks_ok=false
  fi
  if [[ "$hooks_ok" == true ]]; then
    bc_log_success "atuin recording hooks are active"
  else
    # Hooks missing — diagnose the underlying cause (bash-preexec not loaded/installed)
    bc_check_bash_preexec || true
  fi
  echo

  # Check atuin daemon status
  if atuin daemon status &>/dev/null; then
    local daemon_output
    daemon_output=$(atuin daemon status 2>&1)
    bc_log_success "atuin daemon is running"
    echo -e "${BC_COLOR_GRAY}${daemon_output}${BC_COLOR_RESET}"
  else
    local daemon_exit=$?
    local daemon_output
    daemon_output=$(atuin daemon status 2>&1)
    # Exit code 1 with "not running" output is the normal not-running state
    if echo "$daemon_output" | grep -qi "not running\|no daemon\|not found\|connection refused"; then
      bc_log_warn "atuin daemon is not running"
      bc_log_info "Start it with:  atuin daemon &"
    else
      bc_log_warn "atuin daemon status unknown (exit $daemon_exit)"
      [[ -n "$daemon_output" ]] && echo -e "${BC_COLOR_GRAY}${daemon_output}${BC_COLOR_RESET}"
    fi
  fi
  echo

  local sync_url="https://atuin.lan"
  local atuin_cfg="${ATUIN_CONFIG_DIR:-$HOME/.config/atuin}/config.toml"
  if [[ -f "$atuin_cfg" ]]; then
    local configured
    configured=$(grep '^sync_address' "$atuin_cfg" 2>/dev/null \
                   | sed 's/.*=[ ]*"\(.*\)".*/\1/')
    [[ -n "$configured" ]] && sync_url="$configured"
  fi

  bc_log_info "Verifying atuin connectivity: $sync_url"

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$sync_url/" 2>/dev/null)

  case "$http_code" in
    2??)
      local response
      response=$(curl -s --max-time 5 "$sync_url/" 2>/dev/null)
      bc_log_success "atuin reachable (HTTP $http_code) — CA cert trusted"
      echo -e "${BC_COLOR_CYAN}${response}${BC_COLOR_RESET}"
      ;;
    000)
      bc_log_error "Cannot reach $sync_url (connection failed)"
      bc_log_info "Check: server up?  CA cert installed?  (run bc_setup_certs)"
      return 1
      ;;
    *)
      bc_log_warn "atuin server responded with HTTP $http_code"
      return 1
      ;;
  esac
}




# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CUSTOM HISTORY  —  fallback when atuin is unavailable
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


# ==============================================================================
# HISTORY CONFIGURATION
# ==============================================================================
# Enhanced history settings for multi-machine environments with extensive
# command retention and intelligent duplicate handling.

# Enhanced history configuration
export HISTSIZE=50000              # Commands to keep in memory during session
export HISTFILESIZE=100000         # Commands to keep in history file on disk
export HISTCONTROL=ignoreboth:erasedups  # Ignore duplicates and commands starting with space
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "  # Add timestamps to history entries
export HISTIGNORE="ls:ll:cd:pwd:bg:fg:history:clear"  # Don't store these common commands

# Append to history file instead of overwriting (crucial for multi-session sync)
shopt -s histappend

# ==============================================================================
# UNIFIED HISTORY FILE SETUP
# ==============================================================================
# Creates specialization-aware history files that adapt to your current environment.
# Diamond specialization uses shared network storage when available, while other
# specializations use local unified history files.

# Specialization-aware unified history
case "${BASH_SPECIALISATION:-}" in
  "diamond")
    if [[ -n "${DIAMOND_WORK_DIR:-}" && -d "$DIAMOND_WORK_DIR" && -w "$DIAMOND_WORK_DIR" ]]; then
      export HISTFILE="$DIAMOND_WORK_DIR/.bash_history_unified"
      bc_log_debug "Using Diamond unified history: $HISTFILE"
    else
      export HISTFILE="$HOME/.bash_history_diamond"
      bc_log_debug "Using Diamond local history: $HISTFILE"
    fi
    ;;
  "asteria"|"frostpaw")
    export HISTFILE="$HOME/.bash_history_${BASH_SPECIALISATION}"
    bc_log_debug "Using ${BASH_SPECIALISATION} specialization history: $HISTFILE"
    ;;
  *)
    export HISTFILE="$HOME/.bash_history_unified"
    bc_log_debug "Using default unified history: $HISTFILE"
    ;;
esac

# Ensure the history file exists with proper permissions
touch "$HISTFILE" 2>/dev/null || true

# ==============================================================================
# CORE HISTORY MANAGEMENT FUNCTIONS
# ==============================================================================

# Utility function for consistent timestamp formatting
# Centralizes timestamp parsing to eliminate code duplication
bc_format_timestamp() {
  local timestamp="$1"
  local format="${2:-compact}"  # compact, full, epoch
  
  case "$format" in
    "full")
      date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown"
      ;;
    "compact")
      date -d "@$timestamp" "+%m-%d %H:%M" 2>/dev/null || echo "unknown"
      ;;
    "epoch")
      echo "$timestamp"
      ;;
    *)
      date -d "@$timestamp" "+%m-%d %H:%M" 2>/dev/null || echo "unknown"
      ;;
  esac
}

# Manual history synchronization
# Useful when you want to immediately sync history without waiting for the
# next command prompt, or when troubleshooting sync issues.
sync_history() {
  history -a  # Append current session to history file
  history -c  # Clear current session history
  history -r  # Re-read history file
  bc_log_success "History synced across machines"
}

# ==============================================================================
# SESSION EXIT HANDLING
# ==============================================================================
# Ensures that command history is saved when a session ends, even if the
# session terminates unexpectedly. This uses bash's EXIT trap mechanism.

# Auto-sync on session exit
bc_history_exit_sync() {
  [[ $- == *i* ]] || return 0  # Interactive shells only
  if [[ -n "${HISTFILE:-}" && -f "$HISTFILE" ]]; then
    history -a
    bc_log_info "History automatically synced on session exit"
  fi
}

# Register exit trap for automatic sync
trap 'bc_history_exit_sync' EXIT

# ==============================================================================
# SEARCH AND RETRIEVAL FUNCTIONS
# ==============================================================================

# Advanced history search with colored output (gawk-optimized)
# Searches through the unified history file and displays results with
# line numbers and colored formatting for easy identification.
# Usage: hgrep <pattern> [count] [--show-all]
hgrep() {
  local pattern=""
  local max_results=10
  local show_all=false

  # Parse arguments (order-insensitive)
  while [[ $# -gt 0 ]]; do
    case $1 in
      --show-all)
        show_all=true
        shift
        ;;
      -*)
        bc_log_error "Unknown option: $1"
        bc_log_info "Usage: hgrep <pattern> [count] [--show-all]"
        return 1
        ;;
      *)
        if [[ -z "$pattern" ]]; then
          pattern="$1"
        elif [[ "$1" =~ ^[0-9]+$ ]]; then
          max_results="$1"
        else
          bc_log_error "Invalid argument: $1"
          bc_log_info "Usage: hgrep <pattern> [count] [--show-all]"
          return 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$pattern" ]]; then
    bc_log_error "Usage: hgrep <pattern> [count] [--show-all]"
    bc_log_info "Examples:"
    bc_log_info "  hg spotfinder        # Show last 10 matches"
    bc_log_info "  hg spotfinder 20     # Show last 20 matches"
    bc_log_info "  hg spotfinder --show-all  # Show all matches"
    return 1
  fi

  # If we have a unified history file, search using gawk/awk, preferring a fast gawk pass
  if [[ -f "$HISTFILE" ]]; then
    if [[ "$show_all" == true ]]; then
      echo -e "${BC_COLOR_CYAN}🔍 All search results for: ${BC_COLOR_YELLOW}$pattern${BC_COLOR_RESET}"
    else
      echo -e "${BC_COLOR_CYAN}🔍 Last $max_results search results for: ${BC_COLOR_YELLOW}$pattern${BC_COLOR_RESET}"
    fi

    # Choose awk implementation: prefer gawk for gensub/strftime support
    local awk_bin=""
    if command -v gawk >/dev/null 2>&1; then
      awk_bin=gawk
    elif command -v awk >/dev/null 2>&1; then
      awk_bin=awk
    else
      bc_log_error "No awk/gawk available on PATH"
      return 1
    fi

    # If gawk is available, use a single-pass implementation that collects
    # matches, highlights them, and prints only the most recent N (or all).
    if [[ "$awk_bin" == "gawk" ]]; then
      # Pass color escape sequences via -v to avoid shell interpolation issues
      gawk -v pat="$pattern" -v max="$max_results" -v showall="$show_all" \
           -v red="$(printf '\033[0;31m')" \
           -v green="$(printf '\033[0;32m')" \
           -v blue="$(printf '\033[0;34m')" \
           -v reset="$(printf '\033[0m')" \
           'BEGIN { IGNORECASE=1; m=0; ts="" }
      {
        if ($0 ~ /^#([0-9]+)$/) {
          ts = substr($0,2)
          # format timestamp to mm-dd HH:MM
          ts_fmt = strftime("%m-%d %H:%M", ts)
          next
        }
        # Skip history-related commands that would show up in search (unless showing all)
        if (showall != "true" &&
            ($0 ~ /^(hg|hgrep|hr|hs|hstats|hc|hhelp|hquick|hrf|hsearch|hbackup|himport|history)\s/ ||
             $0 ~ /history\s*\|\s*grep/ ||
             $0 ~ /^bc_history_/ ||
             $0 == "history")) {
          next
        }
        if ($0 ~ pat) {
          m++
          highlighted = gensub(pat, red "&" reset, "g", $0)
          # color timestamp and line-number
          matches[m] = green ts_fmt reset " " blue m reset ": " highlighted
        }
      }
      END {
        if (m == 0) {
          printf "\033[33mNo matches found\033[0m\n"
          exit
        }
        if (showall == "true") {
          for (i = 1; i <= m; i++) print matches[i]
          printf "\033[36mTotal: %d matches\033[0m\n", m
        } else {
          start = m - max + 1
          if (start < 1) start = 1
          for (i = start; i <= m; i++) print matches[i]
          if (m > max) {
            printf "\033[33mShowing last %d of %d matches\033[0m\n", max, m
            printf "\033[37mUse '\''--show-all'\'' to see all matches\033[0m\n"
          } else {
            printf "\033[36mTotal: %d matches\033[0m\n", m
          }
        }
      }' "$HISTFILE"

    else
      # Fallback for non-gawk awk: use grep to find matches, then filter and limit
      if [[ "$show_all" == true ]]; then
        mapfile -t raw_matches < <(grep -i -n -- "$pattern" "$HISTFILE" 2>/dev/null || true)
      else
        mapfile -t raw_matches < <(grep -i -n -- "$pattern" "$HISTFILE" 2>/dev/null | \
          grep -v -E "^[0-9]+:(hg|hgrep|hr|hs|hstats|hc|hhelp|hquick|hrf|hsearch|hbackup|himport|history)\s" | \
          grep -v -E "^[0-9]+:history\s*\|\s*grep" | \
          grep -v -E "^[0-9]+:bc_history_" | \
          grep -v -E "^[0-9]+:history$" || true)
      fi

      local total_matches=${#raw_matches[@]}
      if [[ $total_matches -eq 0 ]]; then
        echo -e "${BC_COLOR_YELLOW}No matches found${BC_COLOR_RESET}"
        return 0
      fi

      # Determine which slice to show
      local start_idx=0
      if [[ "$show_all" != true && $total_matches -gt $max_results ]]; then
        start_idx=$(( total_matches - max_results ))
      fi

      for ((i=start_idx; i<total_matches; i++)); do
        # raw_matches elements are 'linenumber:line'
        local raw="${raw_matches[i]}"
        local lineno="${raw%%:*}"
        local line_only="${raw#*:}"
        # highlight using sed (case-insensitive)
        local highlighted
        highlighted=$(printf '%s' "$line_only" | sed -E "s/($pattern)/$(printf '%b' '\\\033[0;31m')\\1$(printf '%b' '\\\033[0m')/Ig")
        # Print colored line number + highlighted text
        echo -e "${BC_COLOR_BLUE}${lineno}${BC_COLOR_RESET}: $highlighted"
      done

      if [[ "$show_all" != true && $total_matches -gt $max_results ]]; then
        echo -e "${BC_COLOR_YELLOW}Showing last $max_results of $total_matches matches${BC_COLOR_RESET}"
        echo -e "${BC_COLOR_GRAY}Use '--show-all' to see all matches${BC_COLOR_RESET}"
      else
        echo -e "${BC_COLOR_CYAN}Total: $total_matches matches${BC_COLOR_RESET}"
      fi
    fi

  else
    bc_log_warn "Unified history file not found"
    if [[ "$show_all" == true ]]; then
      history | grep -i --color=auto -- "$pattern"
    else
      history | grep -i --color=auto -- "$pattern" | \
        grep -v -E "\s(hg|hgrep|hr|hs|hstats|hc|hhelp|hquick|hrf|hsearch|hbackup|himport|history)\s" | \
        grep -v -E "history\s*\|\s*grep" | tail -n "$max_results"
    fi
  fi
}

# Display recent commands from all machines
# Shows the most recent commands from the unified history, making it easy
# to see what was done recently across all your active sessions.
recent_history() {
  local count="${1:-20}"
  if [[ -f "$HISTFILE" ]]; then
    # Parse history with timestamps and format nicely
    local line_num=1
    local commands_shown=0
    
    # Read from end of file to get recent commands
    tac "$HISTFILE" | while IFS= read -r line; do
      if [[ "$line" =~ ^#([0-9]+)$ ]]; then
        # This is a timestamp line - convert to readable format
        local timestamp="${BASH_REMATCH[1]}"
        local readable_time
        readable_time=$(bc_format_timestamp "$timestamp" "compact")
        printf "${BC_COLOR_GREEN}%s${BC_COLOR_RESET} " "$readable_time"
      else
        # This is a command line
        printf "${BC_COLOR_BLUE}%3d${BC_COLOR_RESET}: %s\n" "$((count - commands_shown))" "$line"
        ((commands_shown++))
        # Stop if we've shown enough commands
        if ((commands_shown >= count)); then
          break
        fi
      fi
    done | tac  # Reverse again to show in chronological order
  else
    history "$count"
  fi
}

# Enhanced recent history with multiple display options
# Provides different ways to view recent commands with timestamps
hr_formatted() {
  local count="${1:-20}"
  local format="${2:-compact}"  # compact, full, timestamps-only
  
  if [[ ! -f "$HISTFILE" ]]; then
    bc_log_warn "No unified history file found"
    history "$count"
    return
  fi
  
  case "$format" in
    "full")
      echo -e "${BC_COLOR_CYAN}Recent $count commands (full format):${BC_COLOR_RESET}"
      ;;
    "compact")
      echo -e "${BC_COLOR_CYAN}Recent $count commands:${BC_COLOR_RESET}"
      ;;
    "timestamps")
      echo -e "${BC_COLOR_CYAN}Recent $count commands (with timestamps):${BC_COLOR_RESET}"
      ;;
  esac
  
  local commands_shown=0
  
  # Read from end of file to get recent commands
  tac "$HISTFILE" | while IFS= read -r line; do
    if [[ "$line" =~ ^#([0-9]+)$ ]]; then
      # This is a timestamp line
      local timestamp="${BASH_REMATCH[1]}"
      case "$format" in
        "full")
          local readable_time
          readable_time=$(bc_format_timestamp "$timestamp" "full")
          printf "${BC_COLOR_GREEN}[%s]${BC_COLOR_RESET} " "$readable_time"
          ;;
        "compact")
          local readable_time
          readable_time=$(bc_format_timestamp "$timestamp" "compact")
          printf "${BC_COLOR_GREEN}%s${BC_COLOR_RESET} " "$readable_time"
          ;;
        "timestamps")
          printf "${BC_COLOR_GREEN}%s${BC_COLOR_RESET} " "$timestamp"
          ;;
      esac
    else
      # This is a command line
      printf "${BC_COLOR_BLUE}%3d${BC_COLOR_RESET}: %s\n" "$((count - commands_shown))" "$line"
      ((commands_shown++))
      
      # Stop when we've shown enough commands
      if ((commands_shown >= count)); then
        break
      fi
    fi
  done | tac  # Reverse again to show in chronological order
}

# ==============================================================================
# MAINTENANCE AND OPTIMIZATION FUNCTIONS
# ==============================================================================

# Remove duplicate entries from unified history
# Over time, the unified history file may accumulate duplicate commands.
# This function removes duplicates while preserving command order and timestamps.
clean_history() {
  if [[ -f "$HISTFILE" ]]; then
    local temp_file
    temp_file=$(mktemp)
    
    bc_log_info "Cleaning history file (preserving timestamps)..."
    
    # More sophisticated deduplication that preserves timestamp-command pairs
    awk '
    /^#[0-9]+$/ {
      # This is a timestamp - store it
      timestamp = $0
      next
    }
    {
      # This is a command - check if we have seen this timestamp+command combo
      combo = timestamp "\n" $0
      if (!seen[combo]++) {
        print timestamp
        print $0
      }
    }
    ' "$HISTFILE" > "$temp_file"
    
    local old_count new_count
    old_count=$(grep -v '^#' "$HISTFILE" | wc -l)
    new_count=$(grep -v '^#' "$temp_file" | wc -l)
    
    mv "$temp_file" "$HISTFILE"
    bc_log_success "History cleaned: $old_count → $new_count commands (removed $((old_count - new_count)) duplicates)"
    sync_history
  else
    bc_log_warn "No unified history file to clean"
  fi
}

# ==============================================================================
# STATISTICS AND ANALYSIS FUNCTIONS
# ==============================================================================

# Comprehensive history statistics and analysis
# Provides insights into command usage patterns, including most frequently
# used commands, total command count, and file location information.
bc_history_stats() {
  echo -e "${BC_COLOR_CYAN}📊 History Statistics:${BC_COLOR_RESET}"
  
  if [[ -f "$HISTFILE" ]]; then
    local total_commands
    local unique_commands
    
    # Filter out timestamp lines (starting with #) when counting
    total_commands=$(grep -v '^#' "$HISTFILE" | wc -l)
    unique_commands=$(grep -v '^#' "$HISTFILE" | sort | uniq | wc -l)
    
    echo -e "  ${BC_COLOR_BLUE}Total commands:${BC_COLOR_RESET} $total_commands"
    echo -e "  ${BC_COLOR_BLUE}Unique commands:${BC_COLOR_RESET} $unique_commands"
    echo -e "  ${BC_COLOR_BLUE}History file:${BC_COLOR_RESET} $HISTFILE"
    
    echo -e "\n${BC_COLOR_YELLOW}Top 10 commands:${BC_COLOR_RESET}"
    # Filter out timestamps and extract just the first word of each command
    grep -v '^#' "$HISTFILE" | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | \
      awk '{printf "  %s%-20s%s %s\n", "'${BC_COLOR_GREEN}'", $2, "'${BC_COLOR_RESET}'", $1}'
  else
    echo -e "  ${BC_COLOR_YELLOW}Using local history only${BC_COLOR_RESET}"
    history | tail -n 1 | awk '{print "  Total commands: " $1}'
  fi
}

# Advanced search with context lines
# Similar to hgrep but provides surrounding context lines for better
# understanding of when and how commands were used.
bc_history_search() {
  local query="$1"
  local context="${2:-3}"
  
  if [[ -z "$query" ]]; then
    bc_log_error "Usage: bc_history_search <pattern> [context_lines]"
    return 1
  fi
  
  if [[ -f "$HISTFILE" ]]; then
    echo -e "${BC_COLOR_CYAN}🔍 History search results for: ${BC_COLOR_YELLOW}$query${BC_COLOR_RESET}"
    echo -e "${BC_COLOR_YELLOW}Context: $context lines before/after${BC_COLOR_RESET}\n"
    
    # Use a more sophisticated approach to handle timestamps in context
    local current_timestamp=""
    local line_num=1
    local lines=()
    local match_lines=()
    
    # First pass: read all lines and find matches
    while IFS= read -r line; do
      if [[ "$line" =~ ^#([0-9]+)$ ]]; then
        current_timestamp="${BASH_REMATCH[1]}"
        lines+=("TIMESTAMP:$current_timestamp")
      else
        if echo "$line" | grep -qi "$query"; then
          match_lines+=($line_num)
        fi
        lines+=("COMMAND:$line_num:$line")
        ((line_num++))
      fi
    done < "$HISTFILE"
    
    # Second pass: display matches with context
    for match_line in "${match_lines[@]}"; do
      local start=$((match_line - context))
      local end=$((match_line + context))
      [[ $start -lt 1 ]] && start=1
      
      for ((i=start; i<=end && i<=${#lines[@]}; i++)); do
        local entry="${lines[$((i-1))]}"
        if [[ "$entry" =~ ^TIMESTAMP:([0-9]+)$ ]]; then
          local ts="${BASH_REMATCH[1]}"
          local readable_time
          readable_time=$(bc_format_timestamp "$ts" "full")
          echo -e "  ${BC_COLOR_GREEN}$readable_time${BC_COLOR_RESET}"
        elif [[ "$entry" =~ ^COMMAND:([0-9]+):(.*)$ ]]; then
          local cmd_line="${BASH_REMATCH[1]}"
          local cmd_text="${BASH_REMATCH[2]}"
          local highlighted_line
          highlighted_line=$(echo "$cmd_text" | sed "s/$query/$(printf '\033[0;31m')&$(printf '\033[0m')/gi")
          echo -e "  ${BC_COLOR_BLUE}$cmd_line${BC_COLOR_RESET}: $highlighted_line"
        fi
      done
      echo ""  # Blank line between matches
    done
  else
    history | grep -i --color=auto "$query"
  fi
}

# ==============================================================================
# BACKUP AND IMPORT/EXPORT FUNCTIONS
# ==============================================================================

# Create timestamped backup of history file
# Useful before major operations or when migrating between systems.
# Backups are stored alongside the original file with timestamp suffix.
bc_backup_history() {
  if [[ -f "$HISTFILE" ]]; then
    local backup_file="$HISTFILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$HISTFILE" "$backup_file"
    bc_log_success "History backed up to: $backup_file"
  else
    bc_log_warn "No history file to backup"
  fi
}

# Import and merge history from another machine or backup
# This function safely merges external history files with your current
# unified history, removing duplicates and preserving chronological order.
bc_import_history() {
  local source_file="$1"
  if [[ -z "$source_file" || ! -f "$source_file" ]]; then
    bc_log_error "Usage: bc_import_history <path_to_history_file>"
    return 1
  fi
  
  if [[ -f "$HISTFILE" ]]; then
    # Backup current history first
    bc_backup_history

    local temp_file
    temp_file=$(mktemp)

    # Merge while preserving timestamp+command pair structure
    awk '
    /^#[0-9]+$/ { timestamp = $0; next }
    {
      combo = timestamp "\n" $0
      if (!seen[combo]++) {
        print timestamp
        print $0
      }
    }
    ' "$HISTFILE" "$source_file" > "$temp_file"

    mv "$temp_file" "$HISTFILE"
    bc_log_success "History imported and merged from: $source_file"
    sync_history
  else
    cp "$source_file" "$HISTFILE"
    bc_log_success "History imported from: $source_file"
  fi
}

# ==============================================================================
# HELP AND DOCUMENTATION
# ==============================================================================

# Comprehensive help system for history management
# Displays detailed information about all available commands, usage examples,
# and troubleshooting tips for the unified history system.
# Uses centralized timestamp formatting for consistency.
hhelp() {
  cat << 'EOF'
═══════════════════════════════════════════════════════════════════════════════
📚 UNIFIED HISTORY MANAGEMENT SYSTEM - COMMAND REFERENCE
═══════════════════════════════════════════════════════════════════════════════

🚀 OVERVIEW
This system provides unified command history across all Diamond Light Source
machines you SSH into. Commands are automatically synced in real-time and
preserved across sessions.

📍 QUICK START COMMANDS
  hhelp          Show this help (you're reading it now!)
  hstats         Display comprehensive history statistics (timestamp-aware)
  hr [N]         Show recent N commands with readable timestamps
  hrf [N] [fmt]  Show recent commands with format: compact/full/timestamps
  hg <pattern>   Search history for pattern with colored output
  hs             Manually sync history across sessions

🔍 SEARCH COMMANDS
  hg <pattern>              Quick search (shows last 10 matches by default)
  hg <pattern> [count]      Show last N matches
  hg <pattern> --show-all   Show all matches
  hsearch <pattern> [ctx]   Advanced search with context lines

  Examples:
    hg "git commit"              Find last 10 git commit commands
    hg "git commit" 5            Find last 5 git commit commands
    hg "git commit" --show-all   Find all git commit commands
    hsearch "python" 5           Find python commands with 5 lines context

📊 ANALYSIS & MAINTENANCE
  hstats         Complete statistics: total commands, top commands, etc.
  hc             Clean duplicates from history file
  bc_info        Show system status including history information

💾 BACKUP & MIGRATION
  hbackup                   Create timestamped backup
  himport <file>            Import/merge history from another machine

  Examples:
    hbackup                 Create backup before major changes
    himport ~/.bash_history Import from local bash history

📝 USAGE EXAMPLES
  # Find that complex command you ran on another GPU node
  hg "sbatch.*gpu"

  # See what you've been working on recently across all sessions
  hr 10
  
  # Search for conda environment setups with context
  hsearch "conda activate" 3
  
  # Clean up accumulated duplicates
  hc && hstats
  
  # Backup before importing history from old machine
  hbackup && himport /path/to/old_history

🔧 TECHNICAL DETAILS
  History File: $HISTFILE
  Capacity: 50,000 commands in memory, 100,000 in file
  Features: Timestamps, duplicate removal, real-time sync
  Sync Method: After every command + on session exit

🚨 TROUBLESHOOTING
  - History not syncing? Run: hs (manual sync)
  - Commands missing? Check: bc_validate_config
  - Need fresh start? Backup first: hbackup
  - File corruption? Import from backup: himport <backup_file>

💡 PRO TIPS
  - Use 'hr' instead of 'history' to see unified history with nice timestamps
  - Use 'hrf 10 full' for detailed timestamp format
  - Search is case-insensitive and supports regex patterns
  - Statistics now properly exclude timestamp lines from command counts
  - History survives SSH disconnections and machine restarts
  - Use 'hsearch' with context for debugging complex workflows

═══════════════════════════════════════════════════════════════════════════════
💎 Optimized for Diamond Light Source Multi-Machine Workflows
═══════════════════════════════════════════════════════════════════════════════
EOF
}

# Quick reference card for essential commands
# A condensed version of the help for quick lookups
hquick() {
  cat << 'EOF'
┌─ HISTORY QUICK REFERENCE ─────────────────────────────────────────────────┐
│ hhelp      Full help system       │ hr [N]     Recent N commands          │
│ hstats     Usage statistics       │ hg <pat>   Search for pattern         │
│ hs         Manual sync            │ hc         Clean duplicates           │
│ hbackup    Create backup          │ himport    Import history             │
│ hrf [N] [fmt]  Formatted recent   │ hsearch    Advanced search            │
└───────────────────────────────────────────────────────────────────────────┘
EOF
}

# ==============================================================================
# COMMAND ALIASES AND SHORTCUTS
# ==============================================================================

# Short, memorable aliases for all history management functions
# These provide quick access to the most commonly used features.
alias hs='sync_history'           # Manual sync
alias hg='hgrep'                  # Quick search
alias hr='recent_history'         # Recent commands
alias hrf='hr_formatted'          # Recent commands with formatting options
alias hc='clean_history'          # Clean duplicates
alias hstats='bc_history_stats'   # Statistics
alias hsearch='bc_history_search' # Advanced search
alias hbackup='bc_backup_history' # Create backup
alias himport='bc_import_history' # Import/merge history

# ==============================================================================
# INITIALIZATION AND STATUS
# ==============================================================================

# Display status message when history management loads
# This confirms that the unified history system is active and shows
# the location of the shared history file.
if [[ -n "${HISTFILE:-}" && -f "$HISTFILE" ]]; then
#   bc_log_info "Unified history loaded: $HISTFILE"
#   bc_log_info "Type 'hhelp' for history management commands"
    bc_log_debug "Unified history loaded: $HISTFILE"
fi
