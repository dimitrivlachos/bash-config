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
#   ProxyCommand $BASH_CONFIG_DIR/scripts/ssh-smart-proxy.sh <direct> <fallback> %h %p [timeout] [mode]
#
# Arguments:
#   direct   - SSH host alias for LAN/direct access (e.g., spark-f222-direct)
#   fallback - SSH host alias for fallback access (e.g., spark-f222-ts)
#   %h       - Target hostname (expanded by ssh)
#   %p       - Target port (expanded by ssh)
#   timeout  - LAN probe timeout in seconds (default: 3)
#   mode     - Connection mode:
#              "tunnel" (default) — ssh -W through LAN/fallback host
#              "direct"           — raw TCP pipe (nc/socat/python3) for both
#                                   LAN and fallback; no SSH-level forwarding
#                                   (for bastions that refuse -W)
# ==============================================================================

DIRECT_HOST="$1"
FALLBACK_HOST="$2"
TARGET_HOST="$3"
TARGET_PORT="$4"
TIMEOUT="${5:-3}"
FALLBACK_MODE="${6:-tunnel}"

# Write to /dev/tty directly — ssh's ProxyCommand has its stdout/stdin wired
# to the transport, and stderr may be suppressed in non-debug mode.
# /dev/tty always reaches the user's terminal.
if [[ -w /dev/tty ]]; then
    exec 3>/dev/tty
else
    exec 3>&2
fi

status() { printf '\033[0;90m  ↪ %s\033[0m\n' "$1" >&3; }
debug()  { [[ "${BASH_CONFIG_DEBUG:-}" == "true" ]] && printf '\033[0;37m🔍 [PROXY:%s] %s\033[0m\n' "$DIRECT_HOST" "$1" >&3; }

# In direct mode, nc is required for both the LAN probe and the TCP pipe.
if [[ "$FALLBACK_MODE" == "direct" ]] && ! command -v nc &>/dev/null; then
    printf '\033[0;31m  ✖ ssh-smart-proxy: nc (netcat) is not installed — required for direct mode.\033[0m\n' >&3
    printf '\033[0;31m    Install it with: sudo apt install netcat-openbsd  OR  sudo dnf install nmap-ncat\033[0m\n' >&3
    exit 1
fi

debug "mode=$FALLBACK_MODE target=$TARGET_HOST:$TARGET_PORT timeout=${TIMEOUT}s"

# --- Try LAN / fall back ---
if [[ "$FALLBACK_MODE" == "direct" ]]; then
    # Direct mode — for bastions that refuse ssh -W forwarding.
    # Probe the LAN IP with nc -z; connect via nc as a raw TCP pipe.
    # No SSH-level forwarding is needed since the outer ssh session IS the target.
    DIR_HOSTNAME=$(ssh -G "$DIRECT_HOST" 2>/dev/null | awk '/^hostname /{print $2}')
    DIR_PORT=$(ssh -G "$DIRECT_HOST" 2>/dev/null | awk '/^port /{print $2}')
    : "${DIR_HOSTNAME:=$DIRECT_HOST}"
    : "${DIR_PORT:=22}"
    debug "LAN probe: nc -z -w $TIMEOUT $DIR_HOSTNAME $DIR_PORT"
    status "Trying LAN ($DIRECT_HOST)..."
    nc -z -w "$TIMEOUT" "$DIR_HOSTNAME" "$DIR_PORT" 2>/dev/null
    PROBE_EXIT=$?
    if [[ $PROBE_EXIT -eq 0 ]]; then
        debug "LAN probe succeeded (exit 0) — piping to $DIR_HOSTNAME:$DIR_PORT"
        exec nc "$DIR_HOSTNAME" "$DIR_PORT"
    fi
    debug "LAN probe failed (exit $PROBE_EXIT) — falling back"
    FB_HOSTNAME=$(ssh -G "$FALLBACK_HOST" 2>/dev/null | awk '/^hostname /{print $2}')
    FB_PORT=$(ssh -G "$FALLBACK_HOST" 2>/dev/null | awk '/^port /{print $2}')
    : "${FB_HOSTNAME:=$FALLBACK_HOST}"
    : "${FB_PORT:=$TARGET_PORT}"
    debug "Fallback: $FB_HOSTNAME:$FB_PORT"
    status "Connecting directly ($FALLBACK_HOST → $FB_HOSTNAME:$FB_PORT)..."
    exec nc "$FB_HOSTNAME" "$FB_PORT"
else
    # Tunnel mode — ssh -W through the LAN or fallback host.
    # ConnectTimeout limits only the TCP handshake. Unlike `timeout N ssh -W ...`
    # (which kills working tunnels after N seconds), this lets established LAN
    # connections persist indefinitely.
    debug "LAN tunnel: ssh -o ConnectTimeout=$TIMEOUT -W $TARGET_HOST:$TARGET_PORT $DIRECT_HOST"
    status "Trying LAN ($DIRECT_HOST)..."
    ssh -o ConnectTimeout="$TIMEOUT" -W "$TARGET_HOST:$TARGET_PORT" "$DIRECT_HOST" 2>/dev/null
    LAN_EXIT=$?
    debug "LAN tunnel exit code: $LAN_EXIT"
    [[ $LAN_EXIT -eq 0 ]] && exit 0
    # LogLevel=VERBOSE surfaces the inner ssh's connection status to /dev/tty.
    # Tailscale pre-banner auth URLs ("# To authenticate, visit: ...") flow
    # through the -W data channel and are shown by the outer SSH (requires
    # LogLevel VERBOSE in ssh_config for the host).
    debug "Fallback tunnel: ssh -o LogLevel=VERBOSE -W $TARGET_HOST:$TARGET_PORT $FALLBACK_HOST"
    status "Connecting via fallback ($FALLBACK_HOST)..."
    exec ssh -o LogLevel=VERBOSE -W "$TARGET_HOST:$TARGET_PORT" "$FALLBACK_HOST" 2>&3 3>&-
fi
