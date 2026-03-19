#!/bin/bash
# Toggle mascot visibility, or explicitly show/hide
# Usage: mascot-toggle.sh [show|hide]

STATE_FILE="$HOME/.claude/mascot/state.json"

python3 << 'PYTHON'
import json, os, sys

state_file = os.environ.get('STATE_FILE', os.path.expanduser('~/.claude/mascot/state.json'))
arg = sys.argv[1] if len(sys.argv) > 1 else 'toggle'

data = {}
if os.path.exists(state_file):
    with open(state_file) as f:
        data = json.load(f)

current = data.get('hidden', False)

if arg == 'show':
    data['hidden'] = False
elif arg == 'hide':
    data['hidden'] = True
else:  # toggle
    data['hidden'] = not current

with open(state_file, 'w') as f:
    json.dump(data, f)

status = 'hidden' if data['hidden'] else 'visible'
print(f'Mascot: {status}')
PYTHON
