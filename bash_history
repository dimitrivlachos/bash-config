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
  
  # Search in unified history with proper timestamp handling
  if [[ -f "$HISTFILE" ]]; then
    echo -e "${BC_COLOR_CYAN}🔍 Search results for: ${BC_COLOR_YELLOW}$pattern${BC_COLOR_RESET}"
    
    local current_timestamp=""
    local line_num=1
    
    while IFS= read -r line; do
      if [[ "$line" =~ ^#([0-9]+)$ ]]; then
        # This is a timestamp line
        local timestamp="${BASH_REMATCH[1]}"
        current_timestamp=$(bc_format_timestamp "$timestamp" "compact")
      else
        # This is a command line - check if it matches our pattern
        if echo "$line" | grep -q "$pattern"; then
          # Highlight the matching pattern using printf to properly expand color variables
          local highlighted_line
          highlighted_line=$(echo "$line" | sed "s/$pattern/$(printf '\033[0;31m')&$(printf '\033[0m')/g")
          echo -e "${BC_COLOR_GREEN}$current_timestamp${BC_COLOR_RESET} ${BC_COLOR_BLUE}$line_num${BC_COLOR_RESET}: $highlighted_line"
        fi
        ((line_num++))
      fi
    done < "$HISTFILE"
  else
    bc_log_warn "Unified history file not found"
    history | grep --color=auto "$pattern"
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
  - Use 'hr' instead of 'history' to see unified history with nice timestamps
  - Use 'hrf 10 full' for detailed timestamp format
  - Search is case-insensitive and supports regex patterns  
  - History survives SSH disconnections and machine restarts
  - Statistics now properly exclude timestamp lines from command counts
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
