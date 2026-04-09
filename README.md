# display-grabber

macOS menu bar app for managing multi-display setups.

Useful when you share monitors between your Mac and another device. When you switch
monitors to the other device's input, use the tray app to promote a specific display
to main (menu bar) and mirror or extend the rest.

## Requirements

- macOS
- Xcode Command Line Tools (`xcode-select --install`)

## Installation

```bash
make tray           # Build the app
sudo make install-tray   # Install to ~/Applications and register for auto-start
sudo make uninstall-tray # Remove app and LaunchAgent
```

The app starts automatically at login via a LaunchAgent.

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
