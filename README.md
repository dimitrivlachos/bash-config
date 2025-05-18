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
├── bashrc_core # Main orchestrator script (symlinked as ~/.bashrc_core)
├── bash_aliases # Shared aliases across all systems
├── bash_prompt # Prompt appearance and toggles
├── bash_exports # Shared environment settings
├── bash_tools # Utility shell functions (e.g. mae)
├── install.sh # Setup helper script
├── secrets/
│ └── bash_secrets.sh # Local-only, untracked file for credentials and paths
└── specialisations/
├── bashrc_frostpaw # Home setup (Arch Linux, neofetch, yay updates)
└── bashrc_diamond # Work setup (modules, SSH keys, hostname mapping)
```

---

## 🚀 Installation

### 1. Clone the repo
```bash
git clone git@github.com:dimitrivlachos/bash-config.git ~/Documents/bash-config
cd ~/Documents/bash-config

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
- Create a placeholder `secrets/bash_secrets.sh` if it doesn’t exist

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

## 🔑 Secrets 🔐
Sensitive values are stored in:
```bash
bash-config/secrets/bash_secrets.sh
```
This file is *ignored by Git* and sourced by `bashrc_core`. It contins environment variables for:
- Usernames
- Key paths
This allows a file to dynamically set the correct values such as:
```bash
/dls/science/users/$USER/...
```

## 💡 Prompt Toggles
These commands let you customise your prompt in real-time:
| Command | Description |
| ------- | ----------- |
| `tgit` | Toggle Git branch display |
| `tdir` | Toggle between long `\W` and short `\w` directory display |
| `tem` | Toggle emoji usage in prompt |
| `ph` | Show all available prompt helpers |
| `rp` | Reset prompt to default |

These are available globally on all systems.