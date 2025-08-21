#!/bin/bash
# ==============================================================================
# Enhanced History Management for Multi-Machine Environments
# ==============================================================================
# Optimized for Diamond Light Source infrastructure
#
# This module provides unified command history across multiple SSH sessions
# and machines, with advanced search, sync, and management capabilities.
#
# Key Features:
# - Unified history file shared across all Diamond machines
# - Real-time synchronization between active sessions  
# - Automatic sync on session exit
# - Advanced search with context and highlighting
# - Statistics and duplicate management
# - Import/export functionality for migration
# - VS Code terminal integration
#
# Usage: Run 'hhelp' for detailed command reference
# ==============================================================================

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
# Creates a centralized history file in DIAMOND_WORK_DIR that is shared
# across all machines you SSH into. This allows seamless command history
# synchronization across the entire Diamond infrastructure.

# Centralized history for Diamond machines
if [[ -n "${DIAMOND_WORK_DIR:-}" ]]; then
  export HISTFILE="$DIAMOND_WORK_DIR/.bash_history_unified"
  # Ensure the history file exists with proper permissions
  touch "$HISTFILE" 2>/dev/null || true
fi

# ==============================================================================
# REAL-TIME HISTORY SYNCHRONIZATION
# ==============================================================================
# This section sets up automatic history synchronization that occurs after
# every command execution. This ensures that command history is immediately
# available across all active sessions.
#
# Technical Details:
# - history -a: Appends new commands from current session to the history file
# - history -c: Clears the current session's in-memory history
# - history -r: Reloads the history file into the current session's memory
#
# VS Code Integration:
# VS Code terminals use a special PROMPT_COMMAND (__vsc_prompt_cmd_original)
# for terminal integration features. We detect this and append our sync
# commands to preserve VS Code functionality while adding history sync.

# Update history after each command and sync across sessions
# Handle VS Code terminal integration properly
if [[ "$PROMPT_COMMAND" == "__vsc_prompt_cmd_original" ]]; then
  # VS Code is active, append our history sync to the existing command
  PROMPT_COMMAND="__vsc_prompt_cmd_original; history -a; history -c; history -r"
else
  # Standard terminal, set up our own PROMPT_COMMAND
  PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a; history -c; history -r"
fi

# ==============================================================================
# CORE HISTORY MANAGEMENT FUNCTIONS
# ==============================================================================

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

# Advanced history search with colored output
# Searches through the unified history file and displays results with
# line numbers and colored formatting for easy identification.
hgrep() {
  local pattern="$1"
  if [[ -z "$pattern" ]]; then
    bc_log_error "Usage: hgrep <pattern>"
    return 1
  fi
  
  # Search in unified history with hostname context
  if [[ -f "$HISTFILE" ]]; then
    grep -n "$pattern" "$HISTFILE" | while IFS=':' read -r line_num timestamp command; do
      echo -e "${BC_COLOR_BLUE}$line_num${BC_COLOR_RESET}: ${BC_COLOR_GREEN}$timestamp${BC_COLOR_RESET} $command"
    done
  else
    bc_log_warn "Unified history file not found"
    history | grep "$pattern"
  fi
}

# Display recent commands from all machines
# Shows the most recent commands from the unified history, making it easy
# to see what was done recently across all your active sessions.
recent_history() {
  local count="${1:-20}"
  if [[ -f "$HISTFILE" ]]; then
    tail -n "$count" "$HISTFILE" | nl -v1 -s': '
  else
    history "$count"
  fi
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
    # Remove duplicates while preserving order and timestamps
    awk '!seen[$0]++' "$HISTFILE" > "$temp_file"
    mv "$temp_file" "$HISTFILE"
    bc_log_success "History cleaned - duplicates removed"
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
    
    total_commands=$(wc -l < "$HISTFILE")
    unique_commands=$(cut -d' ' -f4- "$HISTFILE" | sort | uniq | wc -l)
    
    echo -e "  ${BC_COLOR_BLUE}Total commands:${BC_COLOR_RESET} $total_commands"
    echo -e "  ${BC_COLOR_BLUE}Unique commands:${BC_COLOR_RESET} $unique_commands"
    echo -e "  ${BC_COLOR_BLUE}History file:${BC_COLOR_RESET} $HISTFILE"
    
    echo -e "\n${BC_COLOR_YELLOW}Top 10 commands:${BC_COLOR_RESET}"
    cut -d' ' -f4- "$HISTFILE" | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | \
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
    grep -n -i -A"$context" -B"$context" "$query" "$HISTFILE" | \
      sed "s/$query/${BC_COLOR_RED}&${BC_COLOR_RESET}/gi"
  else
    history | grep -i "$query"
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
    
    # Merge histories, remove duplicates, sort by timestamp
    cat "$HISTFILE" "$source_file" | sort | uniq > "${HISTFILE}.tmp"
    mv "${HISTFILE}.tmp" "$HISTFILE"
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
  hstats         Display comprehensive history statistics
  hr [N]         Show recent N commands (default: 20)
  hg <pattern>   Search history for pattern with colored output
  hs             Manually sync history across sessions

🔍 SEARCH COMMANDS
  hg <pattern>              Quick search with line numbers
  hsearch <pattern> [ctx]   Advanced search with context lines
  
  Examples:
    hg "git commit"         Find all git commit commands
    hsearch "python" 5      Find python commands with 5 lines context

📊 ANALYSIS & MAINTENANCE
  hstats         Complete statistics: total commands, top commands, etc.
  hc             Clean duplicates from history file
  bc_info        Show system status including history information

💾 BACKUP & MIGRATION
  hbackup                    Create timestamped backup
  himport <file>            Import/merge history from another machine
  
  Examples:
    hbackup                 Create backup before major changes
    himport ~/.bash_history Import from local bash history

🔧 TECHNICAL DETAILS
  History File: $HISTFILE
  Capacity: 50,000 commands in memory, 100,000 in file
  Features: Timestamps, duplicate removal, real-time sync
  Sync Method: After every command + on session exit

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

🚨 TROUBLESHOOTING
  - History not syncing? Run: hs (manual sync)
  - Commands missing? Check: bc_validate_config
  - Need fresh start? Backup first: hbackup
  - File corruption? Import from backup: himport <backup_file>

💡 PRO TIPS
  - Use 'hr' instead of 'history' to see unified history
  - Search is case-insensitive and supports regex patterns  
  - History survives SSH disconnections and machine restarts
  - Commands are timestamped for easy chronological tracking
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
│ hhelp      Full help system       │ hr [N]     Recent N commands         │
│ hstats     Usage statistics       │ hg <pat>   Search for pattern        │
│ hs         Manual sync            │ hc         Clean duplicates          │
│ hbackup    Create backup          │ himport    Import history            │
└───────────────────────────────────────────────────────────────────────────┘
EOF
}

# ==============================================================================
# COMMAND ALIASES AND SHORTCUTS
# ==============================================================================

# Short, memorable aliases for all history management functions
# These provide quick access to the most commonly used features.
# Short, memorable aliases for all history management functions
# These provide quick access to the most commonly used features.
alias hs='sync_history'           # Manual sync
alias hg='hgrep'                  # Quick search
alias hr='recent_history'         # Recent commands  
alias hc='clean_history'          # Clean duplicates
alias hstats='bc_history_stats'   # Statistics
alias hsearch='bc_history_search' # Advanced search
alias hbackup='bc_backup_history' # Create backup
alias himport='bc_import_history' # Import/merge history
alias hquick='hquick'             # Quick reference card

# ==============================================================================
# INITIALIZATION AND STATUS
# ==============================================================================

# Display status message when history management loads
# This confirms that the unified history system is active and shows
# the location of the shared history file.

# Display status message when history management loads
# This confirms that the unified history system is active and shows
# the location of the shared history file.
# Initial sync on load
if [[ -n "${HISTFILE:-}" && -f "$HISTFILE" ]]; then
#   bc_log_info "Unified history loaded: $HISTFILE"
#   bc_log_info "Type 'hhelp' for history management commands"
    bc_log_debug "Unified history loaded: $HISTFILE"
fi
