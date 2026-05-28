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
