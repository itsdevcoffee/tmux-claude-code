#!/usr/bin/env bash
# Shared helpers for tmux-claude-code hooks and scripts
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/../lib/helpers.sh"

# Resolve SCRIPT_DIR (parent of lib/) for callers that need it
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Temp directory for PID files and locks
CLAUDE_TMPDIR="${TMUX_TMPDIR:-/tmp}"

# Kill a process tracked by a PID file, then remove the file.
# Usage: kill_pid_file <pid_file>
kill_pid_file() {
    local pid_file="$1"
    [ -f "$pid_file" ] || return 0
    local pid
    pid=$(head -1 "$pid_file" 2>/dev/null | tr -cd '0-9')
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
}

# Kill the thinking animator for a given window.
# Usage: kill_window_animator <window_id>
kill_window_animator() {
    kill_pid_file "${CLAUDE_TMPDIR}/claude-animator-${1}.pid"
}

# Kill the escalation timer for a given pane.
# Usage: kill_pane_timer <pane_id>
kill_pane_timer() {
    kill_pid_file "${CLAUDE_TMPDIR}/claude-timer-${1}.pid"
}

# Kill the flash timer for a given target (pane or window).
# Usage: kill_flash <target_id>
kill_flash() {
    kill_pid_file "${CLAUDE_TMPDIR}/claude-flash-${1}.pid"
}

# Check if Claude indicators are enabled. Exits 0 (consuming stdin) if disabled.
# Usage: require_enabled
require_enabled() {
    if [ "$(tmux show -gv @claude-enabled 2>/dev/null)" != "on" ]; then
        cat > /dev/null
        exit 0
    fi
}

# Ensure TMUX_PANE is set. Exits 0 (consuming stdin) if missing.
# Usage: require_pane
require_pane() {
    TMUX_PANE="${TMUX_PANE:-}"
    if [ -z "$TMUX_PANE" ]; then
        cat > /dev/null
        exit 0
    fi
}

# Get the window ID for the current TMUX_PANE.
# Usage: WINDOW=$(get_window "$TMUX_PANE")
get_window() {
    tmux display-message -t "$1" -p '#{window_id}' 2>/dev/null
}

# Set per-pane Claude state (state, emoji, timestamp).
# Usage: set_pane_state <pane_id> <state> <emoji>
set_pane_state() {
    local pane="$1" state="$2" emoji="$3"
    tmux set-option -p -t "$pane" @claude-pane-state "$state" 2>/dev/null || true
    tmux set-option -p -t "$pane" @claude-pane-emoji "$emoji" 2>/dev/null || true
    tmux set-option -p -t "$pane" @claude-timestamp "$(date +%s)" 2>/dev/null || true
}

# Aggregate pane states and update window display.
# Usage: aggregate_state <pane_id>
aggregate_state() {
    "$SCRIPT_DIR/bin/claude-aggregate-state" "$1"
}

# Set window-status-style for a pane's window.
# Usage: set_window_style <pane_id> <style>
set_window_style() {
    tmux set-window-option -t "$1" window-status-style "$2" 2>/dev/null || true
}

# Clear (unset) window-status-style for a pane's window.
# Usage: clear_window_style <pane_id>
clear_window_style() {
    tmux set-window-option -t "$1" -u window-status-style 2>/dev/null || true
}

# State priority (lower = more urgent). Used by aggregator and dashboard.
# Usage: priority=$(state_priority "thinking")
state_priority() {
    case "$1" in
        waiting)  echo 1 ;;
        question) echo 2 ;;
        thinking) echo 3 ;;
        active)   echo 4 ;;
        complete) echo 5 ;;
        stale)    echo 6 ;;
        ended)    echo 7 ;;
        *)        echo 99 ;;
    esac
}
