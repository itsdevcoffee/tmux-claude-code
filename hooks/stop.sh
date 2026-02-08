#!/usr/bin/env bash
# Claude Code Stop hook - fires when Claude finishes responding
# Updates tmux window state to show completion

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

require_enabled
require_pane

# Consume hook input (JSON from Claude Code)
cat > /dev/null

# Set complete state and update window display
set_pane_state "$TMUX_PANE" "complete" "✅"
aggregate_state "$TMUX_PANE"

# Kill thinking animator
WINDOW=$(get_window "$TMUX_PANE") || exit 1
kill_window_animator "$WINDOW"

# Flash green for success, reset after 3 seconds
set_window_style "$TMUX_PANE" "bg=colour48,fg=colour232,bold"
FLASH_PID_FILE="${CLAUDE_TMPDIR}/claude-flash-${WINDOW}.pid"
(sleep 3 && clear_window_style "$TMUX_PANE" && rm -f "$FLASH_PID_FILE" 2>/dev/null) &
echo $! > "$FLASH_PID_FILE"

exit 0
