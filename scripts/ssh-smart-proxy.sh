#!/bin/bash
# ==============================================================================
# SSH Smart Proxy — LAN/Tailscale switching with visible auth
# ==============================================================================
# ProxyCommand helper for personal machines with dual LAN + Tailscale access.
#
# Features:
#   - Status messages written to /dev/tty (bypasses ssh's fd handling)
#   - Tailscale auth messages visible via LogLevel VERBOSE on the inner SSH
#   - ConnectTimeout for LAN probe (avoids killing working LAN tunnels)
#
# Usage (in ssh_config):
#   ProxyCommand $BASH_CONFIG_DIR/scripts/ssh-smart-proxy.sh <direct> <ts> %h %p [timeout]
#
# Arguments:
#   direct  - SSH host alias for LAN access (e.g., spark-f222-direct)
#   ts      - SSH host alias for Tailscale access (e.g., spark-f222-ts)
#   %h      - Target hostname (expanded by ssh)
#   %p      - Target port (expanded by ssh)
#   timeout - LAN probe timeout in seconds (default: 3)
# ==============================================================================

DIRECT_HOST="$1"
TS_HOST="$2"
TARGET_HOST="$3"
TARGET_PORT="$4"
TIMEOUT="${5:-3}"

# Write to /dev/tty directly — ssh's ProxyCommand has its stdout/stdin wired
# to the transport, and stderr may be suppressed in non-debug mode.
# /dev/tty always reaches the user's terminal.
if [[ -w /dev/tty ]]; then
    exec 3>/dev/tty
else
    exec 3>&2
fi

status() { printf '\033[0;90m  ↪ %s\033[0m\n' "$1" >&3; }

# --- Try LAN first ---
# ConnectTimeout limits only the TCP handshake. Unlike `timeout N ssh -W ...`
# (which kills working tunnels after N seconds), this lets established LAN
# connections persist indefinitely.
status "Trying LAN ($DIRECT_HOST)..."
ssh -o ConnectTimeout="$TIMEOUT" -W "$TARGET_HOST:$TARGET_PORT" "$DIRECT_HOST" 2>/dev/null && exit 0

# --- Fall back to Tailscale ---
# LogLevel=VERBOSE surfaces the inner ssh's connection status to /dev/tty.
# The Tailscale pre-banner auth URLs ("# To authenticate, visit: ...") flow
# through the -W data channel and are shown by the outer SSH (requires
# LogLevel VERBOSE in ssh_config for the host).
status "Connecting via Tailscale ($TS_HOST)..."
exec ssh -o LogLevel=VERBOSE -W "$TARGET_HOST:$TARGET_PORT" "$TS_HOST" 2>&3 3>&-
