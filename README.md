# display-grabber

Multi display tool.

Automatically set the active Mac display as the main display and mirror the rest.

Useful when you share monitors between your Mac and another device — when you switch
two monitors to the other device's input, run `display-grabber` and it picks up the
remaining live display, promotes it to main (menu bar), and mirrors the inactive ones.

## Requirements

- macOS, Python 3.11+
- [`pyobjc-framework-Quartz`](https://pypi.org/project/pyobjc-framework-Quartz/)

## Installation

### Python CLI

```bash
pip install .
```

Or editable (for development):

```bash
pip install -e .
```

### macOS Tray App

The tray app (`DisplayGrabber.app`) provides a menu bar interface for managing displays without using the terminal.

```bash
make tray           # Build the tray app
make install-tray   # Install to ~/Applications and register for auto-start
make uninstall-tray # Remove app and LaunchAgent
```

## Usage

```
display-grabber [--list | --main <id> | --dry-run]
```

| Option | Description |
|---|---|
| *(none)* | Auto-detect the single live display and apply config |
| `--list` | List all connected displays with IDs, resolution, and model name |
| `--main <id>` | Force a specific display as main, mirror all others |
| `--dry-run` | Show what auto-detect would do without applying changes |

### Examples

```bash
# See what's connected
display-grabber --list
# Connected displays (3 total):
#   [2] 2560x1440 @ (0,0)  [MAIN]  VX3276-QHD
#   [1] 3440x1440 @ (6000,0)  [inactive]  DELL U3415W
#   [3] 3440x1440 @ (2560,0)  [inactive]  S34C65xU

# Auto-detect and apply (the common case)
display-grabber

# Force a specific display
display-grabber --main 2
```

### Tray App

The tray app provides quick access to display management from the macOS menu bar:

- **Auto-detect & set main** — Automatically detects and sets the main display
- **Set Main Display** — Manually choose which display to set as main
- **Dry Run** — Preview what would happen without making changes
- **Quit** — Exits the app (auto-start will be disabled)

The app automatically starts at login and runs in the background.

### How detection works

A display is considered **live** when `CGDisplayIsActive` returns true and it isn't
asleep. When a monitor switches its input to another device, macOS marks it inactive —
`display-grabber` uses this to find the one remaining display connected to the Mac.

If all three monitors are currently on the Mac (e.g. you haven't switched any away
yet), auto-detect will report multiple live displays and prompt you to use `--main <id>`.

## Development

```bash
make dev-install   # editable install (Python CLI)
make lint          # ruff format + check
make typecheck     # pyright
make check         # lint + typecheck
make tray          # build tray app
make install-tray  # install tray app
make uninstall-tray # uninstall tray app
```

## Project layout

```
src/display_grabber/
  __init__.py      version
  displays.py      CoreGraphics display logic
  cli.py           argparse entry point
tray/
  main.m           Tray app source (Objective-C)
  Info.plist       App bundle metadata
  launchagent.plist.template  LaunchAgent template
typings/Quartz/
  __init__.pyi     hand-written stubs for pyobjc Quartz
pyproject.toml
Makefile
```
