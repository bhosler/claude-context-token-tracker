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
    """Walk process tree to find the Claude Code sessionId."""
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

    totals = {
        'input_tokens': 0, 'output_tokens': 0,
        'cache_read': 0, 'cache_creation': 0, 'turns': 0,
    }
    last = {'input_tokens': 0, 'output_tokens': 0, 'cache_read': 0, 'cache_creation': 0}

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

    sessions_dir = Path.home() / '.claude' / 'token-sessions'
    sessions_dir.mkdir(exist_ok=True)
    (sessions_dir / f"{session_id}.json").write_text(json.dumps(data))

    # Shared fallback
    (Path.home() / '.claude' / 'token-usage.json').write_text(json.dumps(data))

except Exception:
    pass
