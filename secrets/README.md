# Secrets Directory

This directory contains sensitive configuration files that should be kept private.

## Files

### `bash_secrets.sh`
Contains environment variables with sensitive information like:
- Work usernames
- SSH key paths
- Work directory paths
- Any other secrets needed by your bash configuration

Copy `example_secrets.sh` to `bash_secrets.sh` and customize it for your environment.

### `ssh_config`
Contains your complete SSH configuration that will be symlinked to `~/.ssh/config`.

This file should include:
- Global SSH settings (connection multiplexing, timeouts, etc.)
- GitHub account configurations
- Work/organization specific hosts
- Any other SSH hosts you need

Example structure:
```
secrets/
├── bash_secrets.sh      # Your actual secrets (copy from example_secrets.sh)
├── ssh_config          # Your complete SSH configuration
├── example_secrets.sh  # Template file
└── README.md          # This file
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
   - `bash_secrets.sh` (your actual secrets)
   - `ssh_config` (your SSH configuration)
   - Any other sensitive files you need

This allows you to:
- Version control your secrets
- Easily sync them across machines
- Keep them separate from your public bash-config repository
