# Fling

Fling is a small macOS window manager for people who like fast keyboard control. It lives in the menu bar, opens a compact floating panel, and lets you move or resize the current window with a few keys.

## What You Can Do

- Snap the current window to the left, right, top, or bottom half of the screen.
- Maximize the current window without entering macOS fullscreen.
- Move a window to another display.
- Cycle through visible windows while the panel is open.
- Configure a global shortcut to open the panel.
- Optionally configure a second global shortcut to move the focused window to the next display immediately.
- Start Fling automatically when you log in.

## First Run

1. Launch Fling.
2. Grant Accessibility permission when macOS asks for it.
3. Look for the Fling icon in the menu bar.
4. Open `Settings...` from the menu bar menu.
5. Check or change the `Activate panel` shortcut.

If the permission prompt does not appear, enable Fling manually:

```text
System Settings > Privacy & Security > Accessibility
```

Fling needs Accessibility permission because macOS only allows window managers to move and resize other apps through that permission.

## Basic Usage

1. Focus the window you want to control.
2. Press the `Activate panel` shortcut.
3. Press a command key from the panel key table below.
4. Keep using commands, cycle to another window, or dismiss the panel.

The border highlight shows which window Fling is targeting.

## Panel Keys

| Key | Action |
|-----|--------|
| `h` | Snap target window to the left half |
| `l` | Snap target window to the right half |
| `k` | Snap target window to the top half |
| `j` | Snap target window to the bottom half |
| `Space` | Maximize target window |
| `Shift+h` | Move target window to the previous display |
| `Shift+l` | Move target window to the next display |
| `Tab` | Focus the next usable window |
| `Shift+j` | Focus the next usable window |
| `Shift+k` | Focus the previous usable window |
| `Esc` / `q` | Close the panel |
| `Ctrl+c` / `Ctrl+[` | Close the panel |

## Global Shortcuts

Open `Settings...` from the menu bar to configure global shortcuts.

| Setting | Default | Description |
|---------|---------|-------------|
| `Activate panel` | Configured in the app | Opens or closes the floating panel |
| `Move to next display` | Not set | Moves the focused window to the next display without opening the panel |

Shortcut recording requires at least one modifier key:

```text
Control, Option, Shift, or Command
```

## Menu Bar Options

The menu bar menu provides:

- `About Fling`
- `Launch at Login`
- `Settings...`
- `Quit Fling`

## Window Cycling Notes

Fling tries to skip windows that are hidden, minimized, too small, off screen, or not real app windows. Finder's desktop layer is also skipped so cycling targets actual Finder windows instead of the desktop.

## Build And Run From Source

For normal use, run the app from Xcode. The project is generated from `project.yml`:

```bash
brew install xcodegen
xcodegen generate
open Fling.xcodeproj
```

You can also run the Swift package directly:

```bash
swift run Fling
```

## Packaging

For a local release build:

```bash
xcodegen generate
xcodebuild -project Fling.xcodeproj -scheme Fling -configuration Release build
```

For distribution to other Macs, you will also need Developer ID signing and notarization.

## Requirements

- macOS 14.0 or later
- Accessibility permission
- Xcode 15 or later if building from source

## License

MIT
