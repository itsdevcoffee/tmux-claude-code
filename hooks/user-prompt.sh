#!/bin/bash
# Claude Code UserPromptSubmit/PreToolUse hook - fires when user submits input or Claude uses a tool
# Starts thinking animation

set -euo pipefail

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Cleanup trap handler
cleanup() {
    [ -f "${PID_FILE:-}" ] && rm -f "$PID_FILE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Check if indicators are enabled
if [ "$(tmux show -gv @claude-indicators-enabled 2>/dev/null)" != "on" ]; then
    cat > /dev/null  # Consume hook input
    exit 0
fi

# Get the current tmux pane
TMUX_PANE="${TMUX_PANE:-}"

if [ -z "$TMUX_PANE" ]; then
    exit 0
fi

# Read hook input (not used but required for hooks)
cat > /dev/null

# Set state to thinking
if ! tmux set-window-option -t "$TMUX_PANE" @claude-state "thinking" 2>/dev/null; then
    echo "Warning: Failed to set window state for pane $TMUX_PANE" >&2
fi
tmux set-window-option -t "$TMUX_PANE" @claude-thinking-frame "😜" 2>/dev/null || true

# Don't set @claude-emoji for thinking state - format string handles it directly

# Set hot pink background for intense processing vibe
tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=#F706CF,fg=#FFFFFF,bold" 2>/dev/null || true

# Kill any previous animator (CRITICAL: PreToolUse fires multiple times!)
# NOTE: We accept brief race condition - animator self-terminates if state changes
PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${TMUX_PANE}.pid"

# Kill previous animator if it exists
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null | head -1)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null || true
    fi
fi

# Spawn new animator (fast, non-blocking)
nohup "$SCRIPT_DIR/bin/claude-thinking-animator" "$TMUX_PANE" > /dev/null 2>&1 &
echo $! > "$PID_FILE"

exit 0
