#!/bin/bash
python3 - <<'PYEOF'
import json, os, subprocess
from pathlib import Path

CTX_MAX   = 200_000
BAR_WIDTH = 30

def fmt(n):
    return f"{n/1000:.1f}k" if n >= 1000 else str(n)

# ── Find session UUID by walking up process tree ───────────────────────────
def get_ppid(pid):
    try:
        r = subprocess.run(['ps', '-o', 'ppid=', '-p', str(pid)],
                           capture_output=True, text=True)
        return int(r.stdout.strip())
    except Exception:
        return None

sessions_dir  = Path.home() / '.claude' / 'sessions'
token_dir     = Path.home() / '.claude' / 'token-sessions'
session_uuid  = None

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

# Fallback: newest token-session file matching cwd
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

# Load token data
token_file = (token_dir / f"{session_uuid}.json") if session_uuid else None
if token_file and token_file.exists():
    d = json.loads(token_file.read_text())
elif (Path.home() / '.claude' / 'token-usage.json').exists():
    d = json.loads((Path.home() / '.claude' / 'token-usage.json').read_text())
else:
    print("tokens: --\n[" + "░" * BAR_WIDTH + "] 0%")
    exit()

# ── Token stats line ───────────────────────────────────────────────────────
inp   = d.get('input_tokens', 0)
out   = d.get('output_tokens', 0)
cache = d.get('cache_read', 0)
turns = d.get('turns', 0)

parts = [f"↑{fmt(inp)}", f"↓{fmt(out)}"]
if cache > 0:
    parts.append(f"⚡{fmt(cache)}")
parts.append(f"({turns}t)")

# ── Context bar ────────────────────────────────────────────────────────────
cache_read     = d.get('last_cache_read', 0)
cache_creation = d.get('last_cache_creation', 0)
fresh_input    = d.get('last_input', 0)
total_used     = cache_read + cache_creation + fresh_input
pct            = min(total_used / CTX_MAX * 100, 100)

def alloc(val):
    return max(1, round(val / CTX_MAX * BAR_WIDTH)) if val > 0 else 0

c1   = alloc(cache_read)      # █ cached context
c2   = alloc(cache_creation)  # ▓ cache writes
c3   = alloc(fresh_input)     # ▒ fresh input
free = max(0, BAR_WIDTH - c1 - c2 - c3)

bar = '█' * c1 + '▓' * c2 + '▒' * c3 + '░' * free

print(" ".join(parts))
print(f"[{bar}] {pct:.0f}%")
PYEOF
