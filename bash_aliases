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
alias ls='ls --color=auto'
alias clearf='clear && ff'

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