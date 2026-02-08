# tmux-claude-code Plugin Architecture

## What This Plugin Does

A tmux plugin that shows visual state indicators for Claude Code sessions in tmux window tabs. Each window tab changes color and emoji based on what Claude is doing (thinking, waiting for permission, complete, etc.). Supports multiple Claude sessions per window with per-pane tracking and aggregated display.

## Repository

- **GitHub:** `itsdevcoffee/tmux-claude-code`
- **Local path:** `~/.tmux/plugins/tmux-claude-code/`
- **License:** MIT
- **Installed via:** TPM (Tmux Plugin Manager)

## File Map

```
tmux-claude-code/
├── claude-code.tmux           # TPM entry point — defaults, install, keybindings
├── scripts/
│   ├── install.sh             # Injects hooks into ~/.claude/settings.json (Python)
│   └── uninstall.sh           # Removes hooks
├── hooks/                     # Claude Code hook scripts (fired by Claude lifecycle events)
│   ├── session-start.sh       # SessionStart → sets "active" state
│   ├── user-prompt.sh         # UserPromptSubmit + PreToolUse → sets "thinking", starts animator
│   ├── notification.sh        # Notification → handles "question"/"waiting" + escalation timer
│   ├── stop.sh                # Stop → sets "complete", green flash
│   └── session-end.sh         # SessionEnd → clears pane state, re-aggregates
├── bin/
│   ├── tmux-claude-code-on    # Sets format strings (window-status-format) with nested conditionals
│   ├── tmux-claude-code-cleanup-all  # Kills all processes, clears all state
│   ├── claude-aggregate-state # Reads per-pane states, computes worst-state + count for window
│   ├── claude-thinking-animator  # Background daemon — animates braille spinner during thinking
│   ├── claude-stale-detector  # Background daemon — polls for stale sessions (>5min idle)
│   ├── claude-dashboard       # Popup dashboard (prefix+Alt+J) — lists all sessions with fzf
│   └── tmux-claude-clear-all  # Legacy alias
├── config/
│   └── example-settings.json  # Example Claude Code hooks config
└── docs/context/              # Implementation specs and technical docs
    ├── 2026-01-21-keybindings.md
    ├── mouse-click-bug.md
    ├── multi-pane-awareness.md
    ├── popup-dashboard.md
    ├── session-end-stale-detector.md
    └── plugin-architecture.md
```

## State Machine

```
SessionStart → active (🤖)
    ↓ UserPromptSubmit/PreToolUse
thinking (⠋⠙⠹⠸ animated)
    ↓ Notification(permission_prompt)
question (🔮)
    ↓ 15s timeout
waiting (🫦)
    ↓ PreToolUse (user approved)
thinking → Stop → complete (✅)
    ↓ 5min idle (stale detector)
stale (⏳)

SessionEnd → clears pane state

Any state + 5min idle → stale (⏳)
```

### State Priority (lower = more urgent, wins in multi-pane)

| Priority | State | Emoji | Background | Foreground |
|----------|-------|-------|------------|------------|
| 1 | waiting | 🫦 | colour33 (blue) | colour255, bold, blink |
| 2 | question | 🔮 | colour128 (violet) | colour255, bold, blink |
| 3 | thinking | ⠹ (animated) | colour200 (pink) | colour255, bold |
| 4 | active | 🤖 | colour54 (purple) | colour255, bold |
| 5 | complete | ✅ | colour48 (green) | colour232, bold |
| 6 | stale | ⏳ | colour130 (amber) | colour255 |
| 7 | ended | 💀 | colour240 (grey) | colour245 |
| — | no claude | — | colour130 (brown) | colour223, bold |

**CRITICAL:** Always use `colour256` indices (not hex colors) in tmux format strings. Hex `#` characters corrupt tmux's range declarations inside nested conditionals. See `docs/context/mouse-click-bug.md`.

## Architecture: Multi-Pane Awareness

### Per-Pane State (tmux 3.0+ pane options)

Each hook stores state at the **pane level**:
```bash
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "thinking"
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "⠹"
tmux set-option -p -t "$TMUX_PANE" @claude-timestamp "$(date +%s)"
```

### Aggregation (window level)

After setting pane state, every hook calls the aggregator:
```bash
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"
```

The aggregator:
1. Reads all panes in the window via `tmux list-panes -t "$WINDOW" -F '#{pane_id}|#{@claude-pane-state}|#{@claude-pane-emoji}|#{@claude-timestamp}|#{pane_current_command}'`
2. Skips panes where `pane_current_command` is a shell (stale Claude state)
3. Finds the **worst state** (lowest priority number wins)
4. Counts Claude panes
5. Sets window-level display variables: `@claude-state`, `@claude-emoji`, `@claude-count`, `@claude-count-display`

### Count Badge

When >1 Claude pane exists in a window, a superscript count appears: `🔮³`

Superscript mapping: `¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹ ⁺`

Single-pane windows show no badge (identical to pre-multi-pane behavior).

## Format Strings

Defined in `bin/tmux-claude-code-on`. Two format strings:

- **`window-status-format`** — Non-current windows (colored backgrounds)
- **`window-status-current-format`** — Current window (colored foreground, transparent bg)

Both use:
- `#[push-default]` / `#[pop-default]` for clean style isolation
- 8-level nested `#{?#{==:...},...,...}` conditionals
- Separate style tokens: `#[bg=colour54]#[fg=colour255]#[bold]` (NOT comma-separated)
- `#{@claude-count-display}` appended after emoji for count badge

## Hooks System

Hooks are registered in `~/.claude/settings.json` by `scripts/install.sh`:

| Event | Script | Fires When |
|-------|--------|------------|
| SessionStart | session-start.sh | Claude starts or resumes |
| UserPromptSubmit | user-prompt.sh | User submits a prompt |
| PreToolUse | user-prompt.sh | Claude is about to use a tool |
| Stop | stop.sh | Claude finishes responding |
| Notification | notification.sh | Claude needs attention (permission prompt, idle) |
| SessionEnd | session-end.sh | Claude session terminates |

### Hook Pattern (every hook follows this structure)

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Check if enabled
if [ "$(tmux show -gv @claude-enabled 2>/dev/null)" != "on" ]; then
    cat > /dev/null
    exit 0
fi

TMUX_PANE="${TMUX_PANE:-}"
[ -z "$TMUX_PANE" ] && exit 0

# Read hook JSON input
hook_input=$(cat)

# Set per-pane state
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "STATE" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "EMOJI" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-timestamp "$(date +%s)" 2>/dev/null || true

# Aggregate
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"

# Set window-status-style for immediate visual feedback
tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=colourN,fg=colourN,bold" 2>/dev/null || true
```

## Background Daemons

### Thinking Animator (`bin/claude-thinking-animator`)
- Cycles braille frames (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`) on `@claude-thinking-frame`
- Uses `flock` for exclusive per-window locking
- Reads frames from `@claude-emoji-thinking` option (space-separated)
- Stops when `@claude-state` is no longer "thinking"
- Keyed by **window ID** (not pane ID)
- PID file: `${TMUX_TMPDIR}/claude-animator-${WINDOW}.pid`

### Stale Detector (`bin/claude-stale-detector`)
- Global singleton (one per tmux server)
- Uses `flock` to prevent duplicates
- Polls every `@claude-stale-interval` seconds (default 30)
- Marks panes idle >  `@claude-stale-timeout` seconds (default 300) as stale
- Only marks `active` and `complete` states as stale (never thinking/question/waiting)
- Started by `bin/tmux-claude-code-on`, killed by `bin/tmux-claude-code-cleanup-all`
- PID file: `${TMUX_TMPDIR}/claude-stale-detector.pid`

## Configuration Options

### Emoji
| Option | Default | Description |
|--------|---------|-------------|
| `@claude-emoji-active` | 🤖 | Active state emoji |
| `@claude-emoji-thinking` | `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` | Space-separated animation frames |
| `@claude-emoji-question` | 🔮 | Permission prompt emoji |
| `@claude-emoji-waiting` | 🫦 | Waiting (unanswered >15s) emoji |
| `@claude-emoji-complete` | ✅ | Task complete emoji |
| `@claude-emoji-ended` | 💀 | Session terminated emoji |
| `@claude-emoji-stale` | ⏳ | Stale session emoji |

### Timing
| Option | Default | Description |
|--------|---------|-------------|
| `@claude-interval` | 160 | Animation interval (ms) |
| `@claude-escalation` | 15 | Seconds before question → waiting |
| `@claude-stale-timeout` | 300 | Seconds before marking stale |
| `@claude-stale-interval` | 30 | Stale detector poll interval (s) |

### Keybindings
| Option | Default | Action |
|--------|---------|--------|
| `@claude-key-enable` | `M-K` | Enable indicators |
| `@claude-key-disable` | `M-k` | Disable indicators |
| `@claude-key-clear` | `M-c` | Clear current window |
| `@claude-key-clear-all` | `M-C` | Clear all windows |
| `@claude-key-dashboard` | `M-j` | Open popup dashboard |

Set any key to empty string to disable it.

### Dashboard
| Option | Default | Description |
|--------|---------|-------------|
| `@claude-dashboard-all-sessions` | off | Scan all tmux sessions |

## tmux Variables (Per-Pane)

Set via `tmux set-option -p`:
- `@claude-pane-state` — Current state for this pane
- `@claude-pane-emoji` — Current emoji for this pane
- `@claude-timestamp` — Unix epoch of last state change

## tmux Variables (Per-Window)

Set by the aggregator via `tmux set-window-option`:
- `@claude-state` — Aggregated worst state across all panes
- `@claude-emoji` — Emoji for the worst state
- `@claude-count` — Number of Claude panes in window
- `@claude-count-display` — Pre-formatted superscript badge (² ³ ⁴ etc.)
- `@claude-thinking-frame` — Current animation frame (set by animator)
- `@claude-needs-animator` — Flag for hook to start animator
- `@claude-timestamp` — Latest timestamp across all panes

## tmux Variables (Global)

Set via `tmux set-option -g`:
- `@claude-enabled` — "on" / "off"

## Known Constraints

1. **colour256 only** — Never use hex colors (`#RRGGBB`) in format strings or `window-status-style`. The `#` character corrupts tmux's format parser inside nested conditionals.

2. **Separate style tokens** — Use `#[bg=colour54]#[fg=colour255]#[bold]` not `#[bg=colour54,fg=colour255,bold]`. Comma-separated styles break inside conditional expressions.

3. **Unicode emoji width** — ZWJ sequences (like 😵‍💫) cause layout bouncing in tmux. Use fixed-width characters (braille `⠋⠙⠹⠸`, standard emoji, ASCII) for animation frames.

4. **SessionEnd reliability** — The `SessionEnd` hook doesn't fire on hard crashes (SIGKILL). The stale detector and `pane_current_command` check in the aggregator cover this gap.

5. **tmux 3.0+ required** — Pane options (`set-option -p`) require tmux 3.0+. On older versions, multi-pane tracking degrades to last-write-wins.

6. **tmux 3.2+ for popup** — `display-popup` requires tmux 3.2+. Dashboard falls back to `new-window` on older versions.

## Development Workflow

1. Edit files directly in `~/.tmux/plugins/tmux-claude-code/`
2. Reload with `prefix + r` (oh-my-tmux auto-updates plugins on reload)
3. New/modified hooks require restarting Claude sessions to take effect
4. Push to GitHub: `git push origin main` (SSH remote)
5. Update on other machines: TPM update or `prefix + r`

## Commit History

```
bbac6af Add stale session detector and ended/stale format states
7265601 Add multi-pane awareness and SessionEnd hook
2a77702 Fix animation interval to respect @claude-interval option
69e19b9 Fix format string rendering and replace emoji animation with braille spinner
8e641e8 Fix mouse click bug: use colour256 instead of hex colors
```

## Pending Uncommitted Changes

- `bin/claude-dashboard` (NEW) — Popup dashboard feature
- `claude-code.tmux` (MODIFIED) — Dashboard defaults and keybinding
- Maximus review fixes applied to both files
