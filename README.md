# display-grabber

macOS menu bar app for managing multi-display setups.

Useful when you share monitors between your Mac and another device. When you switch
monitors to the other device's input, use the tray app to promote a specific display
to main (menu bar) and mirror or extend the rest.

## Requirements

- macOS
- Xcode Command Line Tools (`xcode-select --install`)

## Installation

### 1. Install Command Line Tools (if not already installed)

```bash
xcode-select --install
```

### 2. Build the app (as yourself — no sudo)

```bash
make tray
```

This compiles `tray/main.m` and produces `dist/DisplayGrabber.app`.

### 3. Install and register for auto-start

```bash
sudo make install-tray
```

This copies the app to `~/Applications/`, writes a LaunchAgent plist to
`~/Library/LaunchAgents/`, and registers it with `launchctl` so the app
starts automatically at login.

> **Important:** always run `make tray` (step 2) before `sudo make install-tray`.
> The build must happen as your own user — building as root causes code-signing
> issues that prevent the app from launching.

### Uninstall

```bash
sudo make uninstall-tray
```

Removes the app and LaunchAgent and stops the running instance.

## Usage

Click the display icon in the menu bar.

### Set Main Display

Picks a display to become the main (menu bar) display and mirrors all others onto it.

### Unmirror (Extended Desktop)

Extends all displays into an independent desktop. Two-level menu:

1. Pick which display gets the **menu bar**
2. Pick the **physical left-to-right order** of all displays (the chosen display is marked ★)

Example — S34C65xU as main, physically in the centre:

```
S34C65xU  →  VX3276-QHD → S34C65xU★ → DELL U3415W
```

### Auto-detect & set main

Detects the single currently-active display and sets it as main, mirroring all others.
Useful after switching monitors away to another device — only the Mac's own display
remains active and gets promoted automatically.

### Restore last layout

After using Unmirror, a **Restore** item appears showing the last used layout (e.g.
`VX3276-QHD → S34C65xU★ → DELL U3415W`). Selecting it reapplies that layout instantly.
The layout is saved by display name and persists across reboots.

### Dry Run

Preview what Auto-detect would do without applying any changes.

## Project layout

```
tray/
  main.m                      Objective-C source (AppKit + CoreGraphics)
  Info.plist                  App bundle metadata
  launchagent.plist.template  LaunchAgent template
Makefile
```
