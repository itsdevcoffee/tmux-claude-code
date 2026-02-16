#!/usr/bin/env bash
# Claude Code UserPromptSubmit/PreToolUse hook - fires when user submits input or Claude uses a tool
# Starts thinking animation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

require_enabled
require_pane

# Consume hook input (not used)
cat > /dev/null

# Redirect all output to avoid "hook error" messages in Claude Code
exec >/dev/null 2>&1

# Set thinking state and update window display
set_pane_state "$TMUX_PANE" "thinking" "⠹"
aggregate_state "$TMUX_PANE"
set_window_style "$TMUX_PANE" "bg=colour200,fg=colour255,bold"

# Start animator if the aggregator flagged it as needed
WINDOW=$(get_window "$TMUX_PANE") || exit 1
NEEDS_ANIMATOR=$(tmux show-window-option -t "$WINDOW" -v @claude-needs-animator 2>/dev/null)

if [ "$NEEDS_ANIMATOR" = "on" ]; then
    PID_FILE="${CLAUDE_TMPDIR}/claude-animator-${WINDOW}.pid"
    kill_pid_file "$PID_FILE"

    nohup "$SCRIPT_DIR/bin/claude-thinking-animator" "$WINDOW" > /dev/null 2>&1 &
    echo $! > "$PID_FILE"

    tmux set-window-option -t "$WINDOW" -u @claude-needs-animator 2>/dev/null || true
fi

exit 0
