# ● claude-pulse

> The vital signs of your Claude Code session. Because flying blind with a rate limit is like playing Dark Souls without the health bar.

```
● Opus │ 60k·200k 30% │ 4h12 2% ██░░░░░░ │ 4j 27% Ven.
  │          │              │                  │
  │          │              │                  └─ Weekly quota + reset day
  │          │              └─ Rate limit + countdown + progress bar
  │          └─ Context tokens used · total + percentage
  └─ Active model
```

## What you get

- **Context window** — tokens used vs total, so you know if you're in 200k or 1M mode
- **5h rate limit** — live countdown + percentage + visual bar. No more surprise throttling
- **7d weekly quota** — because burning 80% on Monday is a lifestyle choice
- **Smart colors** — white when chill, amber at 50%, red at 80%. Pulse animation when you're cooked
- **Spike damping** — no false 100% spikes from API hiccups
- **Atomic writes** — no race conditions between concurrent refreshes

## Install

```bash
curl -sS https://raw.githubusercontent.com/Haidy-ID/claude-pulse/main/install.sh | bash
```

Restart Claude Code. That's it.

### Manual install

```bash
# Download
curl -sS https://raw.githubusercontent.com/Haidy-ID/claude-pulse/main/claude-pulse.sh -o ~/.claude/claude-pulse.sh

# Enable
# Add to ~/.claude/settings.json:
# "statusline": "bash ~/.claude/claude-pulse.sh"
```

## Requirements

- **Claude Code** (with a Pro/Team subscription)
- **curl** + **jq** (probably already there)
- A terminal with true color support (any modern terminal)

## Compatibility

| Platform | Status |
|----------|--------|
| macOS Terminal / iTerm / Warp | ✅ |
| Windows — Git Bash | ✅ |
| Windows — WSL | ✅ |
| Linux | ✅ |

## Layout breakdown

```
● Opus │ 60k·200k 30% │ 2h51 2% ░░░░░░░░ │ 3j 29% Ven.
```

| Segment | Description |
|---------|-------------|
| `● Opus` | Active model (compact name) |
| `60k·200k` | Tokens used · context window size |
| `30%` | Context usage (white → amber → red) |
| `2h51` | Time until 5h rate limit resets |
| `2%` | Current 5h utilization |
| `██░░░░░░` | Visual progress bar |
| `3j` | Days until weekly reset |
| `29%` | Weekly quota used |
| `Ven.` | Weekly reset day (< 48h shows exact time) |

## How it works

1. Reads Claude Code's status JSON from stdin (built-in hook)
2. Fetches rate limit data from Anthropic's OAuth usage API (cached 60s)
3. Renders a compact, colored status line

No background processes. No daemon. No config files to maintain. It's a bash script that reads stdin and prints a string. Peak simplicity.

## Credits

Built by [Lünn](https://github.com/Haidy-ID) during a late night Claude Code session. The irony of using Claude to build a Claude monitoring tool is not lost on us.

## License

MIT — Do whatever you want with it. If you improve it, PRs welcome.
