#!/usr/bin/env bash
# Claude Code SessionEnd hook - fires when session terminates
# Clears pane state and re-aggregates window display
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

require_enabled

TMUX_PANE="${TMUX_PANE:-}"
if [ -z "$TMUX_PANE" ]; then
    cat > /dev/null
    exit 0
fi

# Consume hook input (JSON from Claude Code)
cat > /dev/null

# Kill all background processes for this window/pane
WINDOW=$(get_window "$TMUX_PANE") || exit 0
kill_window_animator "$WINDOW"
kill_pane_timer "$TMUX_PANE"
kill_flash "$TMUX_PANE"

# Set ended state and update window display
set_pane_state "$TMUX_PANE" "ended" "💀"
tmux set-window-option -t "$TMUX_PANE" -u @claude-thinking-frame 2>/dev/null || true
aggregate_state "$TMUX_PANE"
clear_window_style "$TMUX_PANE"

exit 0
