#!/usr/bin/env bash
# ==============================================================================
# sysview.sh — launch (or re-attach to) a split-pane system-monitor session.
# Invoked by the tmux "Prefix + S" binding; the session name is passed as $1.
# ==============================================================================
set -euo pipefail

name="${1:-sysview}"

# If the session already exists, don't rebuild it — the binding's switch-client
# will just drop us back into it.
if tmux has-session -t "=${name}" 2>/dev/null; then
    exit 0
fi

# Return a shell command line that launches the first available tool from the
# given preference list, falling back to a clear message if none are installed.
pick_monitor() {
    for tool in "$@"; do
        if command -v "${tool}" >/dev/null 2>&1; then
            printf '%s' "${tool}"
            return
        fi
    done
    printf 'echo "none of: %s installed"' "$*"
}

# CPU/overall monitors, best first. GPU monitors cover Nvidia/AMD/Intel.
cpu_cmd="$(pick_monitor btop htop top)"
gpu_cmd="$(pick_monitor nvtop nvidia-smi radeontop intel_gpu_top)"

# nvidia-smi is one-shot; make it refresh like the others.
[[ "${gpu_cmd}" == "nvidia-smi" ]] && gpu_cmd="nvidia-smi -l 1"

# base-index / pane-base-index are 1 in tmux.conf, so window 1 / panes 1-2.
tmux new-session -d -s "${name}"
tmux split-window -h -t "${name}"
tmux send-keys -t "${name}:1.1" "${cpu_cmd}" C-m
tmux send-keys -t "${name}:1.2" "${gpu_cmd}" C-m
