#!/bin/bash
# Updates mascot state for the current Claude Code session
# Reads hook payload from stdin, extracts session info, updates state file
# Usage: update-state.sh <state>
# Env vars (optional): MASCOT_CAT=sakura|kuro|mochi|tora|sora
#                       MASCOT_COLOR=#hex
#                       MASCOT_SIZE=32-120

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

# Color name → hex mapping for /color parsing
COLOR_MAP = {
    'red': '#FF4444', 'green': '#44BB44', 'blue': '#4488FF',
    'yellow': '#FFD700', 'orange': '#FF8C00', 'purple': '#9966FF',
    'pink': '#FF69B4', 'cyan': '#00CED1', 'white': '#FFFFFF',
    'magenta': '#FF00FF', 'lime': '#00FF00', 'teal': '#008080',
    'indigo': '#4B0082', 'violet': '#EE82EE', 'coral': '#FF7F50',
    'salmon': '#FA8072', 'gold': '#FFD700', 'silver': '#C0C0C0',
    'crimson': '#DC143C', 'turquoise': '#40E0D0',
}

# Look for /rename and /color in transcript (both formats)
label = ''
transcript_color = ''
if transcript and os.path.exists(transcript):
    try:
        with open(transcript, 'r') as f:
            for line in f:
                try:
                    entry = json.loads(line.strip())
                    etype = entry.get('type', '')

                    # Format 1: direct metadata (written immediately by /rename, /color)
                    if etype in ('custom-title', 'agent-name'):
                        name = entry.get('customTitle') or entry.get('agentName', '')
                        if name:
                            label = name

                    if etype == 'agent-color':
                        cname = entry.get('agentColor', '').lower()
                        if cname.startswith('#'):
                            transcript_color = cname
                        elif cname in COLOR_MAP:
                            transcript_color = COLOR_MAP[cname]

                    # Format 2: local_command stdout (legacy)
                    if (etype == 'system'
                        and entry.get('subtype') == 'local_command'
                        and isinstance(entry.get('content', ''), str)
                        and '<local-command-stdout>' in entry['content']):
                        raw = entry['content']

                        if 'Session renamed to: ' in raw:
                            start = raw.index('Session renamed to: ') + len('Session renamed to: ')
                            end = raw.find('</local-command-stdout>', start)
                            if end == -1:
                                end = raw.find('<', start)
                            if end == -1:
                                end = len(raw)
                            label = raw[start:end].strip()

                        if 'Session color set to: ' in raw:
                            start = raw.index('Session color set to: ') + len('Session color set to: ')
                            end = raw.find('</local-command-stdout>', start)
                            if end == -1:
                                end = raw.find('<', start)
                            if end == -1:
                                end = len(raw)
                            color_name = raw[start:end].strip().lower()
                            if color_name.startswith('#'):
                                transcript_color = color_name
                            else:
                                transcript_color = COLOR_MAP.get(color_name, '')
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

# Preserve existing session fields (color, cat) if not explicitly overridden
existing = data.get('sessions', {}).get(session_id, {})

# Smart "waiting" logic: only set waiting if currently "thinking" (mid-work).
# If state is already "done", a Notification is just an alert, not a real wait.
if state == 'waiting':
    current_state = existing.get('state', '')
    current_time = existing.get('timestamp', 0)
    if current_state == 'done' and (time.time() - current_time) < 5:
        # Stop fired recently → this is just an end-of-response alert, stay "done"
        state = 'done'

session_data = {
    'state': state,
    'timestamp': time.time(),
    'label': label,
}

# Color priority: env override > transcript /color > existing
color = os.environ.get('MASCOT_COLOR', '') or transcript_color or existing.get('color', '')
if color:
    session_data['color'] = color

# Cat: env override > existing
cat = os.environ.get('MASCOT_CAT', '') or existing.get('cat', '')
if cat:
    session_data['cat'] = cat

# Update this session
data['sessions'][session_id] = session_data

# Mascot size (global setting)
size = os.environ.get('MASCOT_SIZE', '')
if size:
    try:
        data['mascotSize'] = max(32, min(120, float(size)))
    except:
        pass

# Prune dead sessions (no update in 120s)
now = time.time()
data['sessions'] = {
    k: v for k, v in data['sessions'].items()
    if now - v['timestamp'] < 28800  # 8 hours
}

# Write atomically
tmp = state_file + '.tmp'
with open(tmp, 'w') as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    json.dump(data, f)
    fcntl.flock(f, fcntl.LOCK_UN)
os.replace(tmp, state_file)
PYTHON
