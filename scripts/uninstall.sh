#!/usr/bin/env bash
# Uninstall script for tmux-claude-code

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_FILE="${HOME}/.claude/settings.json"
TMPDIR="${TMUX_TMPDIR:-/tmp}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Uninstalling tmux-claude-code..."

# Kill all background processes
echo "Stopping background processes..."
pkill -f claude-thinking-animator 2>/dev/null || true
pkill -f claude-stale-detector 2>/dev/null || true

# Remove PID files
echo "Cleaning up PID files..."
rm -f "$TMPDIR"/claude-{animator,timer,flash}-*.pid
rm -f "$TMPDIR"/claude-stale-detector.pid

# Clear tmux state
if [ -n "$TMUX" ]; then
    echo "Clearing tmux window states..."
    for win_id in $(tmux list-windows -a -F "#{window_id}" 2>/dev/null); do
        tmux set-window-option -t "$win_id" -u @claude-state 2>/dev/null || true
        tmux set-window-option -t "$win_id" -u @claude-thinking-frame 2>/dev/null || true
        tmux set-window-option -t "$win_id" -u @claude-timestamp 2>/dev/null || true
        tmux set-window-option -t "$win_id" -u window-status-style 2>/dev/null || true
    done

    # Remove global options
    tmux set -gu @claude-enabled 2>/dev/null || true
    tmux set -gu @claude-debug 2>/dev/null || true
    tmux set -gu @claude-interval 2>/dev/null || true
    tmux set -gu @claude-escalation 2>/dev/null || true

    echo "Reloading tmux configuration..."
    tmux source-file ~/.tmux.conf 2>/dev/null || true
fi

# Remove hooks from settings.json
if [ -f "$SETTINGS_FILE" ]; then
    echo "Removing hooks from Claude Code settings..."

    BACKUP="${SETTINGS_FILE}.backup-uninstall-$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_FILE" "$BACKUP"
    echo "  Backup saved: $BACKUP"

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$SETTINGS_FILE" "$PLUGIN_DIR" <<'EOF'
import json
import os
import sys
import tempfile

settings_file = sys.argv[1]
plugin_dir = sys.argv[2]

with open(settings_file, 'r') as f:
    settings = json.load(f)

if 'hooks' in settings:
    for event in ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'Stop', 'Notification', 'SessionEnd']:
        if event in settings['hooks']:
            settings['hooks'][event] = [
                h for h in settings['hooks'][event]
                if not (isinstance(h, dict) and
                       'hooks' in h and
                       h['hooks'] and
                       plugin_dir in h['hooks'][0].get('command', ''))
            ]
            if not settings['hooks'][event]:
                del settings['hooks'][event]

# Write atomically to prevent corruption
temp_fd, temp_path = tempfile.mkstemp(
    dir=os.path.dirname(settings_file), prefix='.settings.json.tmp'
)
try:
    with os.fdopen(temp_fd, 'w') as f:
        json.dump(settings, f, indent=2)
    os.rename(temp_path, settings_file)
    print("  Hooks removed from settings.json")
except Exception:
    if os.path.exists(temp_path):
        os.unlink(temp_path)
    raise
EOF
    else
        printf "%b\n" "  ${YELLOW}Python not found - please manually remove hooks from settings.json${NC}"
    fi
fi

printf "%b\n" "${GREEN}Uninstall complete!${NC}"
echo ""
echo "To completely remove the plugin:"
echo "  1. Remove from .tmux.conf: set -g @plugin 'itsdevcoffee/tmux-claude-code'"
echo "  2. Restart tmux or run: tmux source-file ~/.tmux.conf"
echo "  3. (Optional) Remove plugin directory: ~/.tmux/plugins/tmux-claude-code"
echo ""
echo "Backups saved:"
echo "  Settings: $BACKUP"
echo ""
echo "Restart Claude Code sessions to unload hooks completely."
