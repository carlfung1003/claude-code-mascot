# Claude Code Mascot 🐯🤖

A floating animated mascot for Claude Code that shows a unique character per active session with state-driven animations.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## What it does

A small floating widget sits in the bottom-right corner of your screen. Each Claude Code session gets its own character, with animations that reflect the session state:

| State | Animation | Glow | When |
|-------|-----------|------|------|
| Thinking | Bouncing | Indigo | Claude is processing / using tools |
| Done | Pulsing | Green | Response complete |
| Error | Shaking | Red | API error or rate limit |
| Waiting | Pulsing | Orange | Needs your permission |
| Idle | Dimmed | Gray | Session inactive |

### Features
- **One character per session** — run 5 sessions, see 5 mascots stacked
- **2 collections** — Cats and Robots (right-click to switch)
- **Unique characters** — assigned sequentially, no duplicates until pool is exhausted
- **Reads `/rename`** — session names appear as labels
- **Reads `/color`** — custom glow ring colors per session
- **Right-click menu** — remove session, change size (S/M/L/XL), switch collection, hide, quit
- **Sound notifications** — Glass (done), Basso (error), Funk (needs attention)
- **Hover tooltip** — shows character name, project, and state
- **Draggable** — move it anywhere on screen
- **Auto show/hide** — appears when sessions are active, disappears when they end
- **No dock icon** — runs as an accessory app

## Character Collections

### Cats 🐱
| Sakura (桜) | Kuro (黒) | Mochi (餅) | Tora (虎) | Sora (空) |
|------------|----------|-----------|----------|----------|
| Pink theme | Dark purple | Cream/warm | Orange tabby | Sky blue |

### Robots 🤖
| Bolt (MK-1) | Nova (NV-7) | Titan (TX-5) | Pixel (PX-8) | Zero (Z-0) |
|-------------|-------------|--------------|--------------|------------|
| Round white helper | Purple android girl | Orange chunky mech | Green retro TV-head | White floating orb |

Each character has 5 emotion states: `focused`, `happy`, `frustrated`, `neutral`, `sleepy`

## Setup

### 1. Compile

```bash
cd ~/.claude/mascot
swiftc -O -parse-as-library -framework Cocoa -framework SwiftUI ClaudeMascot.swift MascotMenu.swift -o ClaudeMascot
```

### 2. Configure hooks

Add to `~/.claude/settings.json` under `"hooks"`:

```json
{
  "PreToolUse": [
    {
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "bash ~/.claude/mascot/update-state.sh thinking" }
      ]
    }
  ],
  "Stop": [
    {
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "bash ~/.claude/mascot/update-state.sh done" },
        { "type": "command", "command": "afplay /System/Library/Sounds/Glass.aiff &" }
      ]
    }
  ],
  "StopFailure": [
    {
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "bash ~/.claude/mascot/update-state.sh error" },
        { "type": "command", "command": "afplay /System/Library/Sounds/Basso.aiff &" }
      ]
    }
  ],
  "Notification": [
    {
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "bash ~/.claude/mascot/update-state.sh waiting" },
        { "type": "command", "command": "afplay /System/Library/Sounds/Funk.aiff &" }
      ]
    }
  ]
}
```

**Important:** Sound and state update must be **separate hook entries** (not chained with `&&`). Chaining with `&` disconnects stdin, preventing the state script from reading the session ID.

### 3. Auto-launch (optional)

Add to `~/.zshrc`:

```bash
pgrep -x ClaudeMascot > /dev/null 2>&1 || ~/.claude/mascot/ClaudeMascot &>/dev/null &
```

### 4. Controls

- **Right-click** the mascot for all controls (size, collection, hide, quit)
- **Show/hide:** `bash ~/.claude/mascot/mascot-toggle.sh` (or ask Claude: "show mascot" / "hide mascot")
- **Switch collection:** right-click → Collection → Cats/Robots

## How it works

1. Claude Code hooks fire `update-state.sh` on each event (tool use, stop, error, notification)
2. The script reads the hook's JSON payload from stdin to get `session_id`, `cwd`, and `transcript_path`
3. It scans the transcript for `/rename` and `/color` commands to use as label/glow color
4. State is written to `~/.claude/mascot/state.json`
5. The SwiftUI app polls the state file every 0.5s and updates the floating widget
6. Characters are assigned sequentially (oldest session = first character) — no duplicates until pool is exhausted

## Adding new character collections

### Image generation guidelines

**Consistency is everything.** Use a single shared style prefix for ALL characters in a collection:

```
# Good — all characters share identical style instructions
STYLE="cute Japanese anime chibi robot mascot, kawaii mecha style, rounded soft design, simple white background, clean vector art, small icon size, no text"

gemini-image.sh "$STYLE, [character-specific description]" output.png
```

```
# Bad — different style per character = inconsistent set
"retro pixel robot..." → pixel art style
"sleek android..." → realistic style
"chibi mech..." → anime style
```

### Background removal

**For colored characters** (non-white body): Generate on white background, then flood-fill remove from edges:
```bash
python3 remove-bg.py media/robots/titan/
```

**For white/light characters** (white body): Generate on green-screen background, then chroma-key remove:
```
# Generate with green bg
STYLE="..., solid bright green background #00FF00, ..."

# Then chroma-key remove (see crop-sheet.py for reference)
```

**Never use aggressive threshold removal** — it destroys white pixels inside the character. Always flood-fill from borders only, so internal whites are preserved.

### Character sheet approach (not recommended)

Generating a single "character sheet" with all emotions and cropping doesn't work reliably:
- AI models don't produce consistent grid layouts
- Auto-detection of character boundaries fails when characters overlap or are arranged non-linearly
- Even-split fallback cuts through characters

**Instead:** Generate each emotion as a separate image with the same style prefix.

### Adding to the app

1. Create `media/<collection>/<name>/` with `focused.png`, `happy.png`, `frustrated.png`, `neutral.png`, `sleepy.png`
2. Add to the pool in `ClaudeMascot.swift`:
```swift
let newPool: [MascotCharacter] = [
    MascotCharacter(id: "name", name: "Name", subtitle: "Tag", collection: "collection", themeColor: .blue),
]
```
3. Register in `allCollections` dictionary
4. Recompile and relaunch

## Sound notifications

| Event | Sound | Customization |
|-------|-------|---------------|
| Done | Glass.aiff | Swap filename in settings.json |
| Error | Basso.aiff | All 14 system sounds in `/System/Library/Sounds/` |
| Needs attention | Funk.aiff | Or use custom `.aiff`/`.mp3` files |

## Known limitations

- **macOS Sequoia 15.6:** `NSStatusItem` (menu bar icon) doesn't work for unsigned/unnotarized apps. Use the right-click context menu instead.
- **Session timeout:** Sessions are pruned after 8 hours of inactivity
- **`/rename` delay:** Label updates on the next hook trigger (next tool call), not instantly after renaming

## Requirements

- macOS 14+
- Swift 5.9+
- Claude Code with hooks support
- Python 3 (for `update-state.sh`)
- Pillow (`pip3 install Pillow`) — only needed for image processing scripts
