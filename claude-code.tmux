#!/usr/bin/env bash
# tmux-claude-code - Visual state indicators for Claude Code in tmux
# TPM plugin entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Helper function to get tmux option with default value
get_tmux_option() {
    local value
    value=$(tmux show-option -gqv "$1")
    echo "${value:-$2}"
}

# Set default options if not already set
tmux set-option -gq @claude-enabled "on"
tmux set-option -gq @claude-debug "off"

# Animation settings
tmux set-option -gq @claude-interval "160"
tmux set-option -gq @claude-escalation "15"

# Emoji settings
tmux set-option -gq @claude-emoji-active "🤖"
tmux set-option -gq @claude-emoji-thinking "⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"
tmux set-option -gq @claude-emoji-question "🔮"
tmux set-option -gq @claude-emoji-waiting "🫦"
tmux set-option -gq @claude-emoji-complete "✅"
tmux set-option -gq @claude-emoji-ended "💀"
tmux set-option -gq @claude-emoji-stale "⏳"

# Stale detection settings
tmux set-option -gq @claude-stale-timeout "300"
tmux set-option -gq @claude-stale-interval "30"

# Keybinding settings - Set to empty string to disable a keybinding
tmux set-option -gq @claude-key-enable "M-K"       # Alt+Shift+K
tmux set-option -gq @claude-key-disable "M-k"      # Alt+K
tmux set-option -gq @claude-key-clear "M-c"        # Alt+C (clear current window)
tmux set-option -gq @claude-key-clear-all "M-C"    # Alt+Shift+C (clear all windows)
tmux set-option -gq @claude-key-dashboard "M-j"    # Alt+J (dashboard popup)

# Dashboard settings
tmux set-option -gq @claude-dashboard-all-sessions "off"

# Make scripts executable
chmod +x "$CURRENT_DIR/hooks/"*.sh "$CURRENT_DIR/bin/"* "$CURRENT_DIR/scripts/"*.sh "$CURRENT_DIR/lib/"*.sh

# Run installation (quiet if already installed)
if [ -f "${HOME}/.claude/settings.json" ] && grep -q "tmux-claude-code" "${HOME}/.claude/settings.json" 2>/dev/null; then
    "$CURRENT_DIR/scripts/install.sh" --quiet
else
    "$CURRENT_DIR/scripts/install.sh"
fi

# Bind a key if the option is non-empty
bind_key() {
    local key="$1"
    shift
    [ -n "$key" ] && tmux bind-key "$key" "$@"
}

# Setup keybindings
setup_keybindings() {
    bind_key "$(get_tmux_option @claude-key-enable M-K)" \
        run-shell "tmux set -g @claude-enabled on && '$CURRENT_DIR/bin/tmux-claude-code-on'"

    bind_key "$(get_tmux_option @claude-key-disable M-k)" \
        run-shell "tmux set -g @claude-enabled off && '$CURRENT_DIR/bin/tmux-claude-code-cleanup-all' && tmux display-message 'Claude indicators disabled'"

    bind_key "$(get_tmux_option @claude-key-clear M-c)" \
        run-shell "tmux set-window-option -t '#{window_id}' @claude-state 'active' && tmux set-window-option -t '#{window_id}' -u window-status-style && tmux display-message 'Claude state cleared'"

    bind_key "$(get_tmux_option @claude-key-clear-all M-C)" \
        run-shell "'$CURRENT_DIR/bin/tmux-claude-code-cleanup-all'"

    # Dashboard: use display-popup for tmux 3.2+, fallback to new-window
    local key_dashboard
    key_dashboard=$(get_tmux_option @claude-key-dashboard M-j)
    if [ -n "$key_dashboard" ]; then
        local tmux_version major minor
        tmux_version=$(tmux -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        major=$(echo "$tmux_version" | cut -d. -f1)
        minor=$(echo "$tmux_version" | cut -d. -f2)

        if [ -n "$major" ] && { [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 2 ]; }; }; then
            tmux bind-key "$key_dashboard" display-popup -E -w 80% -h 50% \
                "'$CURRENT_DIR/bin/claude-dashboard'"
        else
            tmux bind-key "$key_dashboard" new-window -n "claude-dash" \
                "$CURRENT_DIR/bin/claude-dashboard"
        fi
    fi
}

setup_keybindings
