# claude-token-bar

A token usage display and context window progress bar for the [Claude Code](https://claude.ai/code) CLI status line.

```
↑48 ↓19.8k ⚡952.8k (33t)
[████████████▓▒░░░░░░░░░░░░░░░░] 28%
```

**Line 1** — cumulative session token counts  
**Line 2** — visual context window bar (200k = full)

| Character | Meaning |
|-----------|---------|
| `█` | Cached context (CLAUDE.md, prior turns already in cache) |
| `▓` | Cache writes (new content being written to cache this turn) |
| `▒` | Fresh uncached input |
| `░` | Free context window remaining |

Each Claude Code window tracks its own tokens independently — open multiple windows, each shows its own session data.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/bhosler/claude-context-token-tracker/main/install.sh | bash
```

Then restart Claude Code.

---

## What it installs

Three scripts into `~/.claude/scripts/`:

| Script | Role |
|--------|------|
| `token-tracker.py` | **Stop hook** — runs after each turn, reads transcript, writes per-session token file |
| `token-status.sh` | **statusLine** — reads token file, renders the two-line display |
| `token-session-reset.sh` | **SessionStart hook** — zeros token counts at the start of each session |

And patches `~/.claude/settings.json` to wire them in — without touching your existing config.

---

## How it works

Claude Code writes a session file at `~/.claude/sessions/{pid}.json` for each running instance. Both the Stop hook and the status bar script walk the process tree to find that file and extract the `sessionId`. This means multiple Claude Code windows each read and write their own `~/.claude/token-sessions/{sessionId}.json` — no cross-contamination.

Context % is calculated from the **last turn's** token breakdown:
```
(last_cache_read + last_cache_creation + last_input) / 200,000
```

---

## Requirements

- Claude Code CLI
- Python 3 (standard library only)
- macOS or Linux

---

## Uninstall

Remove the three hooks from `~/.claude/settings.json` (the `Stop`, `SessionStart` entries pointing to these scripts, and the `statusLine` key), then delete `~/.claude/scripts/token-*.{py,sh}`.

---

## License

MIT
