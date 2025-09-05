# Secrets Directory

This directory contains sensitive configuration files that should be kept private.

## Files

### `bash_secrets.sh`
Contains environment variables with sensitive information like:
- Work usernames
- SSH key paths
- Work directory paths
- Any other secrets needed by your bash configuration

Copy `bash_secrets.sh.template` to `bash_secrets.sh` and customize it for your environment.

### `ssh_config`
Contains your complete SSH configuration that will be symlinked to `~/.ssh/config`.

This file should include:
- Global SSH settings (connection multiplexing, timeouts, etc.)
- GitHub account configurations
- Work/organization specific hosts
- Any other SSH hosts you need

Copy `ssh_config.template` to `ssh_config` and customize it for your environment.

#### SSH Key Strategy for Dual Network Environments

When working with systems that have both internal and external access (like Diamond Light Source), you may need a special SSH key strategy:

**External Machine (Home/Personal):**
- Generate `id_ed25519_diamond` on your personal machine
- Add the public key to authorized_keys on the work systems
- Use this key for connecting from outside the work network

**Internal Network (Work Systems):**
- Generate another `id_ed25519_diamond` on the work file system
- This key exists in the shared .ssh folder across all work machines
- Also add this public key to authorized_keys on work systems
- Use this key for direct connections when on the internal network

**SSH Config Smart Switching:**
The SSH configuration uses `ProxyCommand` with smart fallback logic:
```ssh
Host ws123
    ProxyCommand bash -c 'timeout 5 ssh -q -W %h:%p ws123-direct 2>/dev/null || ssh -W %h:%p bastion'
```

This approach:
1. **Tries direct connection first** (`ws123-direct`) - works when on internal network
2. **Times out after 5 seconds** if direct connection fails
3. **Falls back to bastion proxy** - works from external networks
4. **Uses same key name** (`id_ed25519_diamond`) but different physical keys depending on location

This allows seamless SSH access whether you're working from home or from within the work network, without needing to change configurations or remember different connection methods.

Example structure:
```
secrets/
├── bash_secrets.sh          # Your actual secrets (copy from template)
├── ssh_config              # Your complete SSH configuration (copy from template)
├── bash_secrets.sh.template # Template file
├── ssh_config.template     # Template file
├── README.md              # This file
└── .gitignore             # Protects your actual secrets
```

## SSH Configuration Management

The SSH config will be automatically managed when you:
1. Run `bc_setup_ssh_config` manually
2. Load a specialization that includes SSH config management (like diamond)
3. Run `bc_validate_config` (which will warn if SSH config isn't properly set up)

The system will:
- Create a symlink from `~/.ssh/config` to `secrets/ssh_config`
- Backup any existing SSH config file
- Set proper permissions (600) on the SSH config file

## Security Note

**Keep this directory private!** It contains sensitive information like:
- SSH configurations with hostnames and usernames
- Paths to SSH keys
- Work-related directory paths

Consider using a private git repository for your secrets that you clone into this directory across your machines.

## Usage with Private Repository

1. Create a private git repository for your secrets
2. Clone it into this `secrets` directory:
   ```bash
   cd /path/to/bash-config
   rm -rf secrets  # Remove the existing secrets directory
   git clone git@github.com:yourusername/your-private-secrets.git secrets
   ```
3. Ensure your private repository contains:
   - `bash_secrets.sh` (copied and customized from `bash_secrets.sh.template`)
   - `ssh_config` (copied and customized from `ssh_config.template`)
   - Any other sensitive files you need

This allows you to:
- Version control your secrets
- Easily sync them across machines
- Keep them separate from your public bash-config repository
