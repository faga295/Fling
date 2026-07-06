# Fling

A minimal macOS window manager. One hotkey, Vim-style keys, done.

## Features

- **Global hotkey** (`⌃⌥Space`) summons a floating panel
- **Vim keys** to snap windows: `h` left, `l` right, `k` top, `j` bottom
- **Space** to maximize
- **Shift+H/L** to move windows across displays (with wrap-around)
- Menu bar icon for settings & quit
- Launch at login support

## Key Bindings

| Key | Action |
|-----|--------|
| `h` | Snap to left half |
| `l` | Snap to right half |
| `k` | Snap to top half |
| `j` | Snap to bottom half |
| `Space` | Maximize |
| `H` | Move to left display |
| `L` | Move to right display |
| `Esc`/`q` | Dismiss panel |

## Build

```bash
# Using Swift Package Manager
swift build

# Run
swift run Fling

# Or open in Xcode
# Install xcodegen first: brew install xcodegen
xcodegen generate
open Fling.xcodeproj
```

## Requirements

- macOS 14.0+
- Accessibility permission (prompted on first launch)

## License

MIT
