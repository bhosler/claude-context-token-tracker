#!/bin/bash
# install-token-bar.sh
# Installs the Claude Code token stats + context window bar into ~/.claude/
# Run once on any machine: bash install-token-bar.sh

set -e
CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$SCRIPTS_DIR"
mkdir -p "$CLAUDE_DIR/token-sessions"

echo "Writing token-tracker.py..."
cat > "$SCRIPTS_DIR/token-tracker.py" << 'PYEOF'
#!/usr/bin/env python3
"""Stop hook: sums token usage, writes per-session file keyed by Claude Code sessionId."""
import json, os, subprocess, sys
from pathlib import Path

def get_ppid(pid):
    try:
        r = subprocess.run(['ps', '-o', 'ppid=', '-p', str(pid)],
                           capture_output=True, text=True)
        return int(r.stdout.strip())
    except Exception:
        return None

def find_session_id():
    sessions_dir = Path.home() / '.claude' / 'sessions'
    pid = os.getpid()
    for _ in range(6):
        pid = get_ppid(pid)
        if not pid or pid <= 1:
            break
        f = sessions_dir / f"{pid}.json"
        if f.exists():
            try:
                return json.loads(f.read_text()).get('sessionId')
            except Exception:
                pass
    return None

try:
    payload = json.load(sys.stdin)
    transcript_path = payload.get('transcript_path', '')

    if not transcript_path or not Path(transcript_path).exists():
        sys.exit(0)

    totals = {'input_tokens': 0, 'output_tokens': 0, 'cache_read': 0, 'cache_creation': 0, 'turns': 0}
    last   = {'input_tokens': 0, 'output_tokens': 0, 'cache_read': 0, 'cache_creation': 0}

    with open(transcript_path) as f:
        for line in f:
            try:
                entry = json.loads(line.strip())
                if entry.get('type') == 'assistant':
                    usage = entry.get('message', {}).get('usage', {})
                    if usage:
                        totals['input_tokens']   += usage.get('input_tokens', 0)
                        totals['output_tokens']  += usage.get('output_tokens', 0)
                        totals['cache_read']     += usage.get('cache_read_input_tokens', 0)
                        totals['cache_creation'] += usage.get('cache_creation_input_tokens', 0)
                        totals['turns'] += 1
                        last['input_tokens']   = usage.get('input_tokens', 0)
                        last['output_tokens']  = usage.get('output_tokens', 0)
                        last['cache_read']     = usage.get('cache_read_input_tokens', 0)
                        last['cache_creation'] = usage.get('cache_creation_input_tokens', 0)
            except Exception:
                pass

    session_id = find_session_id() or Path(transcript_path).stem

    data = {
        **totals,
        'session_id': session_id,
        'last_input':          last['input_tokens'],
        'last_output':         last['output_tokens'],
        'last_cache_read':     last['cache_read'],
        'last_cache_creation': last['cache_creation'],
    }

    token_sessions = Path.home() / '.claude' / 'token-sessions'
    token_sessions.mkdir(exist_ok=True)
    (token_sessions / f"{session_id}.json").write_text(json.dumps(data))
    (Path.home() / '.claude' / 'token-usage.json').write_text(json.dumps(data))

except Exception:
    pass
PYEOF

echo "Writing token-status.sh..."
cat > "$SCRIPTS_DIR/token-status.sh" << 'SHEOF'
#!/bin/bash
python3 - <<'PYEOF'
import json, os, subprocess
from pathlib import Path

CTX_MAX   = 200_000
BAR_WIDTH = 30

def fmt(n):
    return f"{n/1000:.1f}k" if n >= 1000 else str(n)

def get_ppid(pid):
    try:
        r = subprocess.run(['ps', '-o', 'ppid=', '-p', str(pid)],
                           capture_output=True, text=True)
        return int(r.stdout.strip())
    except Exception:
        return None

sessions_dir = Path.home() / '.claude' / 'sessions'
token_dir    = Path.home() / '.claude' / 'token-sessions'
session_uuid = None

pid = os.getpid()
for _ in range(6):
    pid = get_ppid(pid)
    if not pid or pid <= 1:
        break
    f = sessions_dir / f"{pid}.json"
    if f.exists():
        try:
            session_uuid = json.loads(f.read_text()).get('sessionId')
        except Exception:
            pass
        break

if not session_uuid:
    cwd = os.getcwd()
    for sf in sorted(sessions_dir.glob('*.json'), key=lambda x: x.stat().st_mtime, reverse=True):
        try:
            d = json.loads(sf.read_text())
            if d.get('cwd') == cwd:
                session_uuid = d.get('sessionId')
                break
        except Exception:
            pass

token_file = (token_dir / f"{session_uuid}.json") if session_uuid else None
if token_file and token_file.exists():
    d = json.loads(token_file.read_text())
elif (Path.home() / '.claude' / 'token-usage.json').exists():
    d = json.loads((Path.home() / '.claude' / 'token-usage.json').read_text())
else:
    print("tokens: --\n[" + "░" * BAR_WIDTH + "] 0%")
    exit()

inp   = d.get('input_tokens', 0)
out   = d.get('output_tokens', 0)
cache = d.get('cache_read', 0)
turns = d.get('turns', 0)
parts = [f"↑{fmt(inp)}", f"↓{fmt(out)}"]
if cache > 0:
    parts.append(f"⚡{fmt(cache)}")
parts.append(f"({turns}t)")

cache_read     = d.get('last_cache_read', 0)
cache_creation = d.get('last_cache_creation', 0)
fresh_input    = d.get('last_input', 0)
total_used     = cache_read + cache_creation + fresh_input
pct            = min(total_used / CTX_MAX * 100, 100)

def alloc(val):
    return max(1, round(val / CTX_MAX * BAR_WIDTH)) if val > 0 else 0

c1   = alloc(cache_read)
c2   = alloc(cache_creation)
c3   = alloc(fresh_input)
free = max(0, BAR_WIDTH - c1 - c2 - c3)
bar  = '█' * c1 + '▓' * c2 + '▒' * c3 + '░' * free

print(" ".join(parts))
print(f"[{bar}] {pct:.0f}%")
PYEOF
SHEOF

echo "Writing token-session-reset.sh (SessionStart hook)..."
cat > "$SCRIPTS_DIR/token-session-reset.sh" << 'SHEOF'
#!/bin/bash
# SessionStart hook: zeros token data for this session
mkdir -p "$HOME/.claude/token-sessions"
python3 - <<'PYEOF'
import json, time
from pathlib import Path

sessions_dir = Path.home() / '.claude' / 'sessions'
token_dir    = Path.home() / '.claude' / 'token-sessions'
zeroed = {
    "input_tokens": 0, "output_tokens": 0,
    "cache_read": 0, "cache_creation": 0, "turns": 0,
    "last_input": 0, "last_output": 0,
    "last_cache_read": 0, "last_cache_creation": 0,
}

cutoff = time.time() - 10
session_uuid = None
for f in sessions_dir.glob('*.json'):
    try:
        if f.stat().st_mtime >= cutoff:
            data = json.loads(f.read_text())
            session_uuid = data.get('sessionId')
    except Exception:
        pass

if session_uuid:
    zeroed['session_id'] = session_uuid
    (token_dir / f"{session_uuid}.json").write_text(json.dumps(zeroed))

(Path.home() / '.claude' / 'token-usage.json').write_text(json.dumps(zeroed))
PYEOF
SHEOF

chmod +x "$SCRIPTS_DIR/token-tracker.py"
chmod +x "$SCRIPTS_DIR/token-status.sh"
chmod +x "$SCRIPTS_DIR/token-session-reset.sh"

echo "Patching ~/.claude/settings.json..."
python3 - <<PYEOF
import json
from pathlib import Path

settings_path = Path.home() / '.claude' / 'settings.json'
s = json.loads(settings_path.read_text()) if settings_path.exists() else {}

# statusLine
s['statusLine'] = {
    "type": "command",
    "command": "bash $HOME/.claude/scripts/token-status.sh"
}

# hooks
s.setdefault('hooks', {})

# Stop hook
stop_hooks = s['hooks'].setdefault('Stop', [])
tracker_cmd = "python3 $HOME/.claude/scripts/token-tracker.py"
if not any(h.get('hooks', [{}])[0].get('command','') == tracker_cmd
           for h in stop_hooks if h.get('hooks')):
    stop_hooks.append({"matcher": "", "hooks": [{"type": "command", "command": tracker_cmd}]})

# SessionStart hook
start_hooks = s['hooks'].setdefault('SessionStart', [])
reset_cmd = "bash $HOME/.claude/scripts/token-session-reset.sh"
if not any(h.get('hooks', [{}])[0].get('command','') == reset_cmd
           for h in start_hooks if h.get('hooks')):
    start_hooks.append({"matcher": "", "hooks": [{"type": "command", "command": reset_cmd}]})

settings_path.write_text(json.dumps(s, indent=2))
print("settings.json updated")
PYEOF

echo ""
echo "Done. Restart Claude Code to activate."
echo ""
echo "Status bar shows:"
echo "  ↑input ↓output ⚡cache (turns)"
echo "  [████▓▒░░░░░░░░░░░░░░░░░░░░░░░] 28%"
echo ""
echo "Bar key: █ cached  ▓ cache writes  ▒ fresh input  ░ free"
