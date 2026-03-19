# Claude Code Mascot 🐯

A floating animated mascot for Claude Code that shows a unique character per active session with state-driven animations.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## What it does

A small floating widget sits in the bottom-right corner of your screen. Each Claude Code session gets its own animal character from a pool of 10, with animations that reflect what the session is doing:

| State | Animation | Glow | When |
|-------|-----------|------|------|
| Thinking | Bouncing | Indigo | Claude is processing / using tools |
| Done | Pulsing | Green | Response complete |
| Error | Shaking | Red | API error or rate limit |
| Waiting | Pulsing | Orange | Needs your permission |
| Idle | Dimmed | Gray | Session inactive |

### Features
- **One character per session** — run 3 Claude Code sessions, see 3 mascots stacked
- **10 unique animals** (🐯🦊🐼🐙🦁🐸🐉🦄🐨🐺) assigned by session ID hash
- **Reads `/rename`** — if you rename a session, the mascot picks up the new name
- **Hover tooltip** — shows session name, project, and state
- **Draggable** — move it anywhere on screen
- **Auto show/hide** — appears when sessions are active, disappears when they end
- **No dock icon** — runs as an accessory app

## Setup

### 1. Compile

```bash
cd ~/.claude/mascot
swiftc -O -framework Cocoa -framework SwiftUI ClaudeMascot.swift -o ClaudeMascot
```

### 2. Configure hooks

Add to `~/.claude/settings.json` under `"hooks"`:

```json
{
  "PreToolUse": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/.claude/mascot/update-state.sh thinking"
        }
      ]
    }
  ],
  "Stop": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/.claude/mascot/update-state.sh done"
        },
        {
          "type": "command",
          "command": "afplay /System/Library/Sounds/Glass.aiff &"
        }
      ]
    }
  ],
  "StopFailure": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/.claude/mascot/update-state.sh error"
        },
        {
          "type": "command",
          "command": "afplay /System/Library/Sounds/Basso.aiff &"
        }
      ]
    }
  ],
  "Notification": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/.claude/mascot/update-state.sh waiting"
        },
        {
          "type": "command",
          "command": "afplay /System/Library/Sounds/Funk.aiff &"
        }
      ]
    }
  ]
}
```

### 3. Auto-launch (optional)

Add to `~/.zshrc`:

```bash
pgrep -x ClaudeMascot > /dev/null 2>&1 || ~/.claude/mascot/ClaudeMascot &>/dev/null &
```

### 4. Launch manually

```bash
~/.claude/mascot/ClaudeMascot &
```

## How it works

1. Claude Code hooks fire `update-state.sh` on each event (tool use, stop, error, notification)
2. The script reads the hook's JSON payload from stdin to get `session_id`, `cwd`, and `transcript_path`
3. It checks the transcript for any `/rename` commands to use as the session label
4. State is written to `~/.claude/mascot/state.json`
5. The SwiftUI app polls the state file every 0.5s and updates the floating widget

Sessions are pruned after 120s of inactivity.

## Sound notifications

The hook config above also plays macOS system sounds:

| Event | Sound |
|-------|-------|
| Done | Glass.aiff |
| Error | Basso.aiff |
| Needs attention | Funk.aiff |

Swap any sound by changing the filename — all 14 system sounds are in `/System/Library/Sounds/`.

## Requirements

- macOS 14+
- Swift 5.9+
- Claude Code with hooks support
- Python 3 (for `update-state.sh`)
