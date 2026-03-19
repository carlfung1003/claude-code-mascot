#!/bin/bash
# Updates mascot state for the current Claude Code session
# Reads hook payload from stdin, extracts session info, updates state file
# Usage: update-state.sh <state>

export MASCOT_STATE="${1:-idle}"
export MASCOT_STATE_FILE="$HOME/.claude/mascot/state.json"
export MASCOT_PAYLOAD=$(cat)

python3 << 'PYTHON'
import json, os, time, fcntl

state = os.environ['MASCOT_STATE']
state_file = os.environ['MASCOT_STATE_FILE']

# Parse hook payload
try:
    payload = json.loads(os.environ.get('MASCOT_PAYLOAD', '{}'))
except:
    payload = {}

session_id = payload.get('session_id', str(os.getppid()))
cwd = payload.get('cwd', os.getcwd())
transcript = payload.get('transcript_path', '')

# Look for /rename in transcript (only in local_command system entries)
label = ''
if transcript and os.path.exists(transcript):
    try:
        with open(transcript, 'r') as f:
            for line in f:
                try:
                    entry = json.loads(line.strip())
                    # Only match actual /rename CLI commands
                    if (entry.get('type') == 'system'
                        and entry.get('subtype') == 'local_command'
                        and isinstance(entry.get('content', ''), str)
                        and 'Session renamed to: ' in entry['content']
                        and '<local-command-stdout>' in entry['content']):
                        raw = entry['content']
                        start = raw.index('Session renamed to: ') + len('Session renamed to: ')
                        end = raw.find('</local-command-stdout>', start)
                        if end == -1:
                            end = raw.find('<', start)
                        if end == -1:
                            end = len(raw)
                        label = raw[start:end].strip()
                except:
                    continue
    except:
        pass

# Fall back to directory name
if not label:
    label = os.path.basename(cwd) if cwd else 'unknown'

# Read existing state
data = {'sessions': {}}
if os.path.exists(state_file):
    try:
        with open(state_file, 'r') as f:
            data = json.load(f)
    except:
        data = {'sessions': {}}

# Update this session
data['sessions'][session_id] = {
    'state': state,
    'timestamp': time.time(),
    'label': label
}

# Prune dead sessions (no update in 120s)
now = time.time()
data['sessions'] = {
    k: v for k, v in data['sessions'].items()
    if now - v['timestamp'] < 120
}

# Write atomically
tmp = state_file + '.tmp'
with open(tmp, 'w') as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    json.dump(data, f)
    fcntl.flock(f, fcntl.LOCK_UN)
os.replace(tmp, state_file)
PYTHON
