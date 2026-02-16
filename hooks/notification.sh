#!/usr/bin/env bash
# Claude Code Notification hook - fires when Claude is waiting for input
# Updates tmux window state to show waiting/needs attention

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/helpers.sh"

require_enabled
require_pane

# Read hook input (JSON from Claude Code)
hook_input=$(cat)

# Redirect all output to avoid "hook error" messages in Claude Code
exec >/dev/null 2>&1

# Handle permission_prompt as question state
if echo "$hook_input" | grep -q '"notification_type":"permission_prompt"'; then
    WINDOW=$(get_window "$TMUX_PANE") || exit 1
    kill_window_animator "$WINDOW"
    kill_pane_timer "$TMUX_PANE"

    set_pane_state "$TMUX_PANE" "question" "🔮"
    aggregate_state "$TMUX_PANE"
    set_window_style "$TMUX_PANE" "bg=colour128,fg=colour255,bold,blink"

    # Start escalation timer: escalate to "waiting" if unanswered
    ESCALATION_TIMEOUT=$(tmux show-option -gqv @claude-escalation 2>/dev/null)
    ESCALATION_TIMEOUT=${ESCALATION_TIMEOUT:-15}
    TIMER_PID_FILE="${CLAUDE_TMPDIR}/claude-timer-${TMUX_PANE}.pid"
    (
        sleep "$ESCALATION_TIMEOUT"
        current_pane_state=$(tmux show-option -p -t "$TMUX_PANE" -v @claude-pane-state 2>/dev/null)
        if [ "$current_pane_state" = "question" ]; then
            set_pane_state "$TMUX_PANE" "waiting" "🫦"
            aggregate_state "$TMUX_PANE"
            set_window_style "$TMUX_PANE" "bg=colour33,fg=colour255,bold,blink"
        fi
        rm -f "$TIMER_PID_FILE" 2>/dev/null
    ) &
    echo $! > "$TIMER_PID_FILE"

# Handle idle_prompt - set to active state
elif echo "$hook_input" | grep -q '"notification_type":"idle_prompt"'; then
    WINDOW=$(get_window "$TMUX_PANE") || exit 1
    kill_window_animator "$WINDOW"

    set_pane_state "$TMUX_PANE" "active" "🤖"
    aggregate_state "$TMUX_PANE"
    set_window_style "$TMUX_PANE" "bg=colour54,fg=colour255,bold"
fi

exit 0
