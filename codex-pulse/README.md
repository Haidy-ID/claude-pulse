# codex-pulse

> Graphical pulse line for Codex CLI sessions. The native Codex footer is still configured as a fallback, but the rich bars come from this sidecar script.

Codex does not expose a Claude-style `statusline` shell hook. `codex-pulse` reads Codex's local session JSONL events instead, then renders the missing visual layer outside the TUI.

## What you get

- **Model** - latest active Codex model for the current project
- **Execution mode** - Fast/Flex service tier when enabled
- **Thinking mode** - current Codex reasoning effort (`low`, `medium`, `high`, `xhigh`)
- **Permission mode** - `Ask`, `Bypass`, or `Plan`
- **Context estimate** - latest turn token usage vs model context window
- **5h limit** - primary rolling usage window with reset countdown and bar
- **Weekly limit** - secondary rolling usage window with reset countdown and reset day
- **Native fallback** - Codex's built-in `tui.status_line` stays configured

Example:

```text
● gpt-5.5 · Fast · Think xhigh · Ask │ 204k/258k 79% │ 3h32 38% ███░░░░░ │ 2d 47% Tue
```

## Install

```bash
cd codex-pulse
./install.sh
```

The installer:

- copies `codex-pulse.sh` to `~/.codex/codex-pulse.sh`
- keeps a timestamped backup of `~/.codex/config.toml`
- configures Codex's native status items as a fallback

## Usage

```bash
# One-shot render
~/.codex/codex-pulse.sh

# Live sidecar line
~/.codex/codex-pulse.sh --watch

# tmux status-right
set -g status-right '#(~/.codex/codex-pulse.sh --tmux)'

# Diagnose sources
~/.codex/codex-pulse.sh --check
```

Useful overrides:

```bash
CODEX_PULSE_SERVICE_TIER=fast ~/.codex/codex-pulse.sh
CODEX_PULSE_REASONING_EFFORT=xhigh ~/.codex/codex-pulse.sh
CODEX_PULSE_PERMISSION_MODE=Plan ~/.codex/codex-pulse.sh
CODEX_PULSE_LANG=fr ~/.codex/codex-pulse.sh
```

## Manual native fallback config

Add or update this block in `~/.codex/config.toml`:

```toml
[tui]
status_line = ["model", "used-tokens", "context-used", "five-hour-limit", "weekly-limit", "fast-mode"]
terminal_title = ["spinner", "project", "model"]
```

## Requirements

- Codex CLI
- `jq`
- `sqlite3`

## Notes

- The graphical line reads local files under `~/.codex`; it does not print credentials and does not call OpenAI APIs directly.
- The context segment uses the latest `token_count` event's `last_token_usage` against `model_context_window`. That is the closest local signal exposed in Codex session logs.
- The 5h and weekly segments come from Codex's own local `rate_limits` event payload.
- The Fast/Flex segment reads `service_tier` from `~/.codex/config.toml`.
- The Think segment reads the active thread's `reasoning_effort`, then falls back to `model_reasoning_effort` in config.
- The permission segment reads the latest `turn_context` first, then falls back to the active thread's `approval_mode` and `sandbox_policy`.
- The layout intentionally mirrors `claude-pulse`: context has no bar, 5h has the visual bar, weekly shows the reset day.
- If no session exists for the current directory, the script falls back to the latest unarchived Codex thread.
