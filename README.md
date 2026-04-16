# 🌀 bash-config

Modular, secure, and portable Bash configuration system with environment-specific customisations for home and work setups.

This repo is designed to be:

- 🧩 **Modular** – clean separation of shared and machine-specific logic
- 🛡️ **Secure** – sensitive details are kept in a separate `secrets/` file (git-ignored)
- 🧼 **Maintainable** – easily extensible as your setup evolves
- 🌍 **Portable** – supports multiple environments via specialisations

---

## 📁 Structure
```
bash-config/
├── bashrc_core         # Main orchestrator script (symlinked as ~/.bashrc_core)
├── bash_aliases        # Shared aliases across all systems
├── bash_prompt         # Prompt appearance and toggles
├── bash_exports        # Shared environment settings
├── bash_tools          # Utility shell functions (e.g. mae, Git config setup)
├── install.sh          # Setup helper script
├── configs/
│   ├── gitconfig_base      # Shared Git aliases and settings
│   ├── gitconfig_diamond   # Diamond-specific Git config template
│   └── gitconfig_frostpaw  # Frostpaw-specific Git config template
├── secrets/
│   ├── bash_secrets.sh         # Local-only, untracked file for credentials and paths
│   ├── gitconfig_user_public   # Git user config for public account (untracked)
│   └── gitconfig_user_private  # Git user config for private account (untracked)
└── specialisations/
    ├── bashrc_frostpaw # Home setup (Arch Linux, neofetch, yay updates)
    └── bashrc_diamond  # Work setup (modules, SSH keys, hostname mapping)
```

---

## 🚀 Installation

### 1. Clone the repo
```bash
git clone git@github.com:dimitrivlachos/bash-config.git ~/Documents/bash-config
cd ~/Documents/bash-config
```

### 2. Run the installer
```bash
./install.sh
```

This will:
- Ask you which specialisation to enable (frostpaw or diamond)
- Link bashrc_core to ~/.bashrc_core
- Append this to your ~/.bashrc:
    ```bash
    export BASH_SPECIALISATION="frostpaw"
    source ~/.bashrc_core
    ```
- Create a placeholder `secrets/bash_secrets.sh` if it doesn't exist
- Install **bash-preexec** (required for atuin history recording — see [Atuin History](#-atuin-history))

### 3. Set up Git configuration
```bash
git-setup
```

This will generate your `~/.gitconfig` with all aliases and settings. See [Git Configuration](#-git-configuration) below for details.

---

## 🧠 Specialisations
The following specialisation values are supported:
| Name | Description |
| ---- | ----------- |
| frostpaw | Home setup (Arch Linux, neofetch, yay updates) |
| diamond | Work setup (modules, SSH keys, hostname mapping) |

Set the desired specialisation in `~/.bashrc`:
```bash
export BASH_SPECIALISATION="{specialisation}"
```
This variable is read by `bashrc_core` to load the correct specialisation file.

---

## 🔑 Secrets 🔐
Sensitive values are stored in:
```bash
bash-config/secrets/bash_secrets.sh
```
This file is *ignored by Git* and sourced by `bashrc_core`. It contains environment variables for:
- Usernames
- Key paths

This allows a file to dynamically set the correct values such as:
```bash
/dls/science/users/$USER/...
```

### Git User Configuration
Git user details are also stored in secrets to keep your email addresses private:

**For Frostpaw (dual GitHub accounts):**
Create these files in `secrets/`:

```ini
# secrets/gitconfig_user_public (for github.com-d)
[user]
    name = Your Name
    email = your.work@email.com
```

```ini
# secrets/gitconfig_user_private (for github.com-s)
[user]
    name = Your Name
    email = your.personal@email.com
```

**For Diamond:**
Only `secrets/gitconfig_user_public` is needed with your work credentials.

---

## 🔧 Git Configuration

This bash-config includes a comprehensive Git configuration system with:
- 40+ useful aliases for common Git operations
- Sensible defaults for core, pull, push, and merge behavior
- Automatic user switching based on remote URL (Frostpaw only)
- Cross-platform line ending handling

### Setup

Run the setup command to generate your `~/.gitconfig`:
```bash
git-setup
```

This reads the template files in `configs/` and generates `~/.gitconfig` with absolute paths resolved for your system.

### How It Works

**Base Configuration** (`configs/gitconfig_base`)
Contains all shared aliases and settings used across all machines:
- Status, commit, branch, and log shortcuts
- Editor, pager, and color settings
- Merge and diff configurations

**Specialisation Templates** (`configs/gitconfig_{diamond,frostpaw}`)
- **Diamond**: Simple setup that includes base config + public user credentials
- **Frostpaw**: Advanced setup with conditional includes based on Git remote URLs
  - Repos cloned with `git@github.com-d:...` use public account
  - Repos cloned with `git@github.com-s:...` use private account

**User Credentials** (`secrets/gitconfig_user_{public,private}`)
Contain your name and email, kept in the gitignored `secrets/` directory.

### Using Git Aliases

View all available aliases:
```bash
git aliases
```

Some useful examples:
```bash
# Status shortcuts
git s              # Short status with branch info
git st             # Full status

# Commit shortcuts
git cm "message"   # Commit with message
git ca             # Amend last commit
git can            # Amend without changing message

# Branch management
git b              # List branches
git ba             # List all branches (including remote)
git bd branch-name # Delete branch (safe)

# Beautiful logs
git l              # Compact log with graph
git lg             # Colorful detailed log with graph

# Quick operations
git unstage file   # Unstage a file
git undo           # Undo last commit (keeps changes)
git discard file   # Discard changes to file
```

### Configuration Highlights

**Core Settings:**
- `editor = vim` - Uses Vim for commit messages
- `autocrlf = input` - Handles cross-platform line endings (converts CRLF→LF on commit)
- `pager = less -FRX` - Improved pager settings (quits if one screen, shows colors, doesn't clear)

**Behavior:**
- `push.autoSetupRemote = true` - No need for `-u` flag when pushing new branches
- `pull.rebase = false` - Uses merge strategy (creates merge commits)
- `init.defaultBranch = main` - New repos use `main` instead of `master`

**Better Diffs & Merges:**
- `merge.conflictstyle = diff3` - Shows 3-way conflict markers (yours | base | theirs)
- `diff.colorMoved = default` - Highlights moved code blocks differently

### Updating Configuration

If you modify the config templates in `configs/`, regenerate your `~/.gitconfig`:
```bash
git-setup
```

The system will backup your existing config before generating a new one.

---

## � Atuin History

[Atuin](https://github.com/atuinsh/atuin) is used as the primary shell history backend, providing cross-machine sync, per-command metadata (exit code, duration, host), and an interactive Ctrl+R search UI.

### Dependencies

Atuin relies on [bash-preexec](https://github.com/rcaloras/bash-preexec) to hook into bash's `preexec`/`precmd` lifecycle. **Without it, atuin will not record any commands** — the Ctrl+R search UI still works, but nothing new is added to history.

The installer handles this automatically. To install manually:

| Distro | Command |
| ------ | ------- |
| Arch Linux | `sudo pacman -S bash-preexec` |
| Ubuntu / Debian | `sudo apt install bash-preexec` |
| RHEL / other | `curl -fsSL https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh -o ~/.bash-preexec.sh` |

### Verifying the setup

Check that bash-preexec is loaded and atuin is recording correctly:
```bash
bc_check_bash_preexec   # Check bash-preexec is installed and active
bc_verify_atuin         # Check atuin sync server connectivity (frostpaw only)
```

If commands are not appearing in atuin search, run `bc_check_bash_preexec` — it will tell you whether bash-preexec is missing, installed-but-not-loaded, or fully active.

### How recording works

```
bash runs a command
  → bash-preexec fires preexec_functions[] → __atuin_preexec → atuin history start
  → command executes
  → bash-preexec fires precmd_functions[]  → __atuin_precmd  → atuin history end
```

The bash HISTFILE is still maintained as a passive text backup via `history -a` in `PROMPT_COMMAND`, so it remains intact if atuin ever becomes unavailable.

---

## �💡 Prompt Toggles
These commands let you customise your prompt in real-time:
| Command | Description |
| ------- | ----------- |
| `tgit` | Toggle Git branch display |
| `tdir` | Toggle between long `\W` and short `\w` directory display |
| `tem` | Toggle emoji usage in prompt |
| `ph` | Show all available prompt helpers |
| `rp` | Reset prompt to default |

These are available globally on all systems.