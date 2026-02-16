#!/usr/bin/env bash
# Claude Code SessionStart hook - initializes window state
# Sets initial state to "active" and cleans up any previous processes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

require_enabled
require_pane

# Consume hook input (not used)
cat > /dev/null

# Redirect all output to avoid "hook error" messages in Claude Code
exec >/dev/null 2>&1

# Set active state and update window display
set_pane_state "$TMUX_PANE" "active" "🤖"
aggregate_state "$TMUX_PANE"
set_window_style "$TMUX_PANE" "bg=colour54,fg=colour255,bold"

# Kill any previous animator for this window
WINDOW=$(get_window "$TMUX_PANE") || exit 1
kill_window_animator "$WINDOW"

exit 0
