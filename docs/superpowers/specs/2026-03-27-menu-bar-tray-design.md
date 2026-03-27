# Menu Bar Tray App — Design Spec

## Overview

A persistent macOS menu bar application (`DisplayGrabber.app`) that exposes the same display-management operations as the `display-grabber` CLI, accessible without a terminal. Written in Objective-C, compiled with `clang` from Command Line Tools, packaged as a proper `.app` bundle, and auto-started via a LaunchAgent.

**Minimum macOS version:** 11 (Big Sur) — required for SF Symbols via `NSImage`.

## Why Objective-C

Swift 6.2.4 (`swiftlang-6.2.4.1.4`) does not match the installed SDK (built with Swift 6.2 / `swiftlang-6.2.3.3.2`), making `swiftc` unusable. `clang` 17 works correctly and can compile Objective-C + AppKit + CoreGraphics with no extra tooling.

## Source Layout

```
tray/
  main.m                      # All source: NSStatusBar, NSMenu, CoreGraphics display logic
  Info.plist                  # LSUIElement=YES, NSPrincipalClass=NSApplication
  launchagent.plist.template  # LaunchAgent template (APP_PATH substituted at install time)
```

No asset files — the icon uses an SF Symbol (`display.2`) loaded at runtime via `imageWithSystemSymbolName:accessibilityDescription:`.

## Architecture

### `main.m` — three logical sections

**`DisplayManager`** (ObjC class):
- `listDisplays` — wraps `CGGetOnlineDisplayList`, returns `NSArray` of `NSDictionary` with keys `id` (CGDirectDisplayID), `width`, `height`, `isMain` (BOOL)
- `detectActive` — returns the `CGDirectDisplayID` of the current main display via `CGMainDisplayID()`. If there is only one online display, returns that.
- `setMain:(CGDirectDisplayID)targetID` — applies the same logic as the CLI:
  1. `CGBeginDisplayConfiguration(&config)`
  2. `CGConfigureDisplayOrigin(config, targetID, 0, 0)` — makes it the menu-bar display
  3. For every other online display: `CGConfigureDisplayMirrorOfDisplay(config, otherID, targetID)`
  4. `CGCompleteDisplayConfiguration(config, kCGConfigureForSession)`
- `dryRunForDisplay:(CGDirectDisplayID)targetID` — returns an `NSString` summary without applying, in the format:
  ```
  Would set display <ID> (<W>×<H>) as main.
  Would mirror: display <ID> (<W>×<H>), display <ID> (<W>×<H>)
  ```

**`AppDelegate`** (implements `NSMenuDelegate`):
- Owns `NSStatusItem` with a template image (`display.2`)
- Owns `NSMenu`; rebuilds it in `menuNeedsUpdate:` so the display list is always current
- Dispatches operations to `DisplayManager`; surfaces results via `NSAlert` (no entitlements needed, works on all supported macOS versions)
- Quit action: calls `launchctl bootout gui/<uid> <agent-plist-path>` before `[NSApp terminate:nil]`, so `KeepAlive` does not immediately relaunch the app

**`main()`**:
```objc
int main(int argc, const char *argv[]) {
    NSApplication *app = [NSApplication sharedApplication]; // reads NSPrincipalClass from bundle
    AppDelegate *delegate = [[AppDelegate alloc] init];
    app.delegate = delegate;
    [app run];
    return 0;
}
```

## Menu Structure

```
✓ Display 2 — 2560×1440 (main)     ← NSControlStateValueOn checkmark on current main
  Display 1 — 3440×1440            ← NSControlStateValueOff, [item setEnabled:NO]
  Display 3 — 3440×1440
──────────────────────────────────
  Auto-detect & set main           ← calls detectActive → setMain, shows NSAlert on error
  Set Main Display ▶               ← submenu, one item per display
    Display 2 — 2560×1440
    Display 1 — 3440×1440
    Display 3 — 3440×1440
  Dry Run ▶                        ← separate NSMenu instance (cannot share one NSMenu
    Display 2 — 2560×1440          ←   across two parent items); shows NSAlert with summary
    Display 1 — 3440×1440
    Display 3 — 3440×1440
──────────────────────────────────
  Quit                             ← bootout LaunchAgent, then [NSApp terminate:nil]
```

The menu is rebuilt on every `menuNeedsUpdate:` call. The current main display gets `NSControlStateValueOn` (renders as a checkmark). Status items at the top are `[item setEnabled:NO]`.

"Set Main" and "Dry Run" submenus are constructed as two separate `NSMenu` instances each time the menu rebuilds.

## Build

```makefile
TRAY_SRC     = tray/main.m
TRAY_APP     = dist/DisplayGrabber.app
TRAY_BIN     = $(TRAY_APP)/Contents/MacOS/DisplayGrabber
TRAY_PLIST   = $(TRAY_APP)/Contents/Info.plist

tray: $(TRAY_SRC) tray/Info.plist
	mkdir -p dist
	mkdir -p $(TRAY_APP)/Contents/MacOS
	mkdir -p $(TRAY_APP)/Contents/Resources
	clang -fobjc-arc \
	      -framework AppKit \
	      -framework CoreGraphics \
	      -framework CoreFoundation \
	      $(TRAY_SRC) -o $(TRAY_BIN)
	cp tray/Info.plist $(TRAY_PLIST)
	codesign --sign - --force $(TRAY_APP)
```

Ad-hoc signing (`--sign -`) is sufficient — no Apple Developer account required. This satisfies Gatekeeper and ensures `CGCompleteDisplayConfiguration` works correctly under SIP.

## Installation

```makefile
LAUNCH_AGENTS = $(HOME)/Library/LaunchAgents
AGENT_PLIST   = $(LAUNCH_AGENTS)/com.display-grabber.tray.plist
UID           := $(shell id -u)

install-tray: tray
	cp -r $(TRAY_APP) ~/Applications/
	mkdir -p $(LAUNCH_AGENTS)
	sed "s|APP_PATH|$(HOME)/Applications/DisplayGrabber.app/Contents/MacOS/DisplayGrabber|g" \
	    tray/launchagent.plist.template > $(AGENT_PLIST)
	# 'launchctl bootstrap' is the modern replacement for the deprecated 'launchctl load'
	launchctl bootstrap gui/$(UID) $(AGENT_PLIST)

uninstall-tray:
	-launchctl bootout gui/$(UID) $(AGENT_PLIST)
	rm -f $(AGENT_PLIST)
	rm -rf ~/Applications/DisplayGrabber.app
```

`tray/launchagent.plist.template`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>             <string>com.display-grabber.tray</string>
  <key>ProgramArguments</key> <array><string>APP_PATH</string></array>
  <key>RunAtLoad</key>         <true/>
  <key>KeepAlive</key>         <true/>
</dict>
</plist>
```

Note: `KeepAlive = true` means launchd will restart the app if it exits unexpectedly. The Quit menu item handles this by calling `launchctl bootout` before terminating so launchd stops managing the process.

## Info.plist

```xml
<key>CFBundleIdentifier</key>        <string>com.display-grabber.tray</string>
<key>CFBundleExecutable</key>        <string>DisplayGrabber</string>
<key>CFBundleVersion</key>           <string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSUIElement</key>               <true/>   <!-- no Dock icon, no app switcher -->
<key>NSPrincipalClass</key>          <string>NSApplication</string>
<key>NSHighResolutionCapable</key>   <true/>   <!-- crisp icon on Retina displays -->
```

## Out of Scope

- Hotkey support
- Preferences window
- Display arrangement preview
- Automatic detection on display connect/disconnect (can be added later via `CGDisplayRegisterReconfigurationCallback`)
