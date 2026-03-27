# Menu Bar Tray App Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a persistent macOS menu bar app (`DisplayGrabber.app`) that exposes auto-detect, set-main, and dry-run display operations without needing a terminal.

**Architecture:** Single Objective-C source file (`tray/main.m`) containing `DisplayManager` (CoreGraphics logic) and `AppDelegate` (NSStatusBar + NSMenu), compiled with `clang` and packaged as a `.app` bundle via Makefile targets. A LaunchAgent plist manages auto-start at login.

**Tech Stack:** Objective-C, AppKit, CoreGraphics, clang 17, launchctl

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `tray/Info.plist` | Create | App bundle metadata (LSUIElement, bundle ID, etc.) |
| `tray/launchagent.plist.template` | Create | LaunchAgent template with APP_PATH placeholder |
| `tray/main.m` | Create | All app source: DisplayManager + AppDelegate + main() |
| `Makefile` | Modify | Add `tray`, `install-tray`, `uninstall-tray` targets |

---

## Chunk 1: Supporting Files + Makefile

### Task 1: Create `tray/Info.plist`

**Files:**
- Create: `tray/Info.plist`

- [ ] **Step 1: Create the file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>        <string>com.display-grabber.tray</string>
    <key>CFBundleExecutable</key>        <string>DisplayGrabber</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
```

- [ ] **Step 2: Validate plist syntax**

Run: `plutil tray/Info.plist`
Expected: `tray/Info.plist: OK`

---

### Task 2: Create `tray/launchagent.plist.template`

**Files:**
- Create: `tray/launchagent.plist.template`

- [ ] **Step 1: Create the file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.display-grabber.tray</string>
    <key>ProgramArguments</key>
    <array>
        <string>APP_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Verify APP_PATH placeholder is present**

Run: `grep -c APP_PATH tray/launchagent.plist.template`
Expected: `1`

---

### Task 3: Add Makefile targets

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add tray variables and targets to Makefile**

Add the following to `Makefile` (after the existing targets):

```makefile
# --- Tray app ---
TRAY_SRC     = tray/main.m
TRAY_APP     = dist/DisplayGrabber.app
TRAY_BIN     = $(TRAY_APP)/Contents/MacOS/DisplayGrabber
TRAY_PLIST   = $(TRAY_APP)/Contents/Info.plist
LAUNCH_AGENTS = $(HOME)/Library/LaunchAgents
AGENT_PLIST  = $(LAUNCH_AGENTS)/com.display-grabber.tray.plist
UID          := $(shell id -u)

.PHONY: tray install-tray uninstall-tray

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

install-tray: tray
	cp -r $(TRAY_APP) ~/Applications/
	mkdir -p $(LAUNCH_AGENTS)
	sed "s|APP_PATH|$(HOME)/Applications/DisplayGrabber.app/Contents/MacOS/DisplayGrabber|g" \
	    tray/launchagent.plist.template > $(AGENT_PLIST)
	launchctl bootstrap gui/$(UID) $(AGENT_PLIST)

uninstall-tray:
	-launchctl bootout gui/$(UID) $(AGENT_PLIST) 2>/dev/null
	rm -f $(AGENT_PLIST)
	rm -rf ~/Applications/DisplayGrabber.app
```

- [ ] **Step 2: Commit scaffold files**

```bash
git add tray/Info.plist tray/launchagent.plist.template Makefile
git commit -m "feat: add tray app scaffold (plists + Makefile targets)"
```

---

## Chunk 2: DisplayManager

### Task 4: Write `DisplayManager` in `tray/main.m`

**Files:**
- Create: `tray/main.m`

The entire app lives in one file. Build it section by section, compiling after each section to catch errors early.

- [ ] **Step 1: Write the file header and DisplayManager interface**

Create `tray/main.m` with the following content (this is the complete starting skeleton — subsequent steps will append to it or replace `// APPDELEGATE_PLACEHOLDER` and `// MAIN_PLACEHOLDER`):

```objc
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

// ---------------------------------------------------------------------------
// DisplayManager — CoreGraphics display queries and configuration
// ---------------------------------------------------------------------------

@interface DisplayManager : NSObject
- (NSArray<NSDictionary *> *)listDisplays;
- (CGDirectDisplayID)detectActive;
- (BOOL)setMain:(CGDirectDisplayID)targetID error:(NSString **)errorOut;
- (NSString *)dryRunForDisplay:(CGDirectDisplayID)targetID;
@end

@implementation DisplayManager

- (NSArray<NSDictionary *> *)listDisplays {
    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    CGError err = CGGetOnlineDisplayList(32, ids, &count);
    if (err != kCGErrorSuccess) return @[];

    NSMutableArray *result = [NSMutableArray array];
    for (uint32_t i = 0; i < count; i++) {
        CGDirectDisplayID did = ids[i];
        size_t w = CGDisplayPixelsWide(did);
        size_t h = CGDisplayPixelsHigh(did);
        BOOL isMain = CGDisplayIsMain(did);
        [result addObject:@{
            @"id":     @(did),
            @"width":  @(w),
            @"height": @(h),
            @"isMain": @(isMain),
        }];
    }
    return result;
}

- (CGDirectDisplayID)detectActive {
    // Per spec: use CGMainDisplayID(). Only fall back if there is exactly one display.
    CGDirectDisplayID main = CGMainDisplayID();
    if (main != 0) return main;

    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    CGGetOnlineDisplayList(32, ids, &count);
    return count == 1 ? ids[0] : 0; // 0 = "could not determine"
}

- (BOOL)setMain:(CGDirectDisplayID)targetID error:(NSString **)errorOut {
    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    CGGetOnlineDisplayList(32, ids, &count);

    CGDisplayConfigRef cfg = NULL;
    CGError err = CGBeginDisplayConfiguration(&cfg);
    if (err != kCGErrorSuccess || cfg == NULL) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"CGBeginDisplayConfiguration failed (%d)", err];
        return NO;
    }

    // Remove any existing mirroring first. CGDisplayMirrorOfDisplay state must be
    // cleared before reassigning a new master; the Python CLI does the same.
    // Note: the design spec omits this step but it is required for correct behaviour.
    for (uint32_t i = 0; i < count; i++) {
        if (ids[i] != targetID) {
            CGConfigureDisplayMirrorOfDisplay(cfg, ids[i], kCGNullDirectDisplay);
        }
    }

    // Place target at (0,0) to make it the menu-bar display
    CGConfigureDisplayOrigin(cfg, targetID, 0, 0);

    // Mirror all other displays onto the target
    for (uint32_t i = 0; i < count; i++) {
        if (ids[i] != targetID) {
            CGConfigureDisplayMirrorOfDisplay(cfg, ids[i], targetID);
        }
    }

    err = CGCompleteDisplayConfiguration(cfg, kCGConfigureForSession);
    if (err != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(cfg);
        if (errorOut) *errorOut = [NSString stringWithFormat:@"CGCompleteDisplayConfiguration failed (%d)", err];
        return NO;
    }
    return YES;
}

- (NSString *)dryRunForDisplay:(CGDirectDisplayID)targetID {
    NSArray<NSDictionary *> *displays = [self listDisplays];

    NSDictionary *target = nil;
    NSMutableArray *mirrors = [NSMutableArray array];
    for (NSDictionary *d in displays) {
        if ([d[@"id"] unsignedIntValue] == targetID) {
            target = d;
        } else {
            [mirrors addObject:d];
        }
    }

    if (!target) return @"Display not found.";

    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"Would set display %u (%lu×%lu) as main.\n",
        targetID,
        [target[@"width"] unsignedLongValue],
        [target[@"height"] unsignedLongValue]];

    if (mirrors.count == 0) {
        [summary appendString:@"No other displays to mirror."];
    } else {
        NSMutableArray *mirrorDescs = [NSMutableArray array];
        for (NSDictionary *d in mirrors) {
            [mirrorDescs addObject:[NSString stringWithFormat:@"display %u (%lu×%lu)",
                [d[@"id"] unsignedIntValue],
                [d[@"width"] unsignedLongValue],
                [d[@"height"] unsignedLongValue]]];
        }
        [summary appendFormat:@"Would mirror: %@", [mirrorDescs componentsJoinedByString:@", "]];
    }
    return summary;
}

@end

// APPDELEGATE_PLACEHOLDER
// MAIN_PLACEHOLDER
```

- [ ] **Step 2: Verify DisplayManager compiles (stub out placeholders)**

Replace the placeholder lines with minimal stubs so clang has something to compile:

```bash
# Temporarily verify compile with just DisplayManager + a stub main
clang -fobjc-arc \
  -framework AppKit \
  -framework CoreGraphics \
  -framework CoreFoundation \
  -x objective-c - -o /tmp/dm_test <<'EOF'
$(cat tray/main.m | sed 's|// APPDELEGATE_PLACEHOLDER||' | sed 's|// MAIN_PLACEHOLDER|int main(int argc,const char**argv){return 0;}|')
EOF
```

Expected: no errors, exits 0. (Warnings about unused variables are acceptable.)

If that sed inline approach is awkward, just temporarily edit main.m to replace the placeholders with `int main(int argc,const char**argv){return 0;}`, compile, then revert.

- [ ] **Step 3: Commit DisplayManager**

```bash
git add tray/main.m
git commit -m "feat: add DisplayManager (CoreGraphics display logic)"
```

---

## Chunk 3: AppDelegate + main() + full compile

### Task 5: Write `AppDelegate` in `tray/main.m`

**Files:**
- Modify: `tray/main.m` — replace `// APPDELEGATE_PLACEHOLDER`

- [ ] **Step 1: Replace `// APPDELEGATE_PLACEHOLDER` with the full AppDelegate**

The complete AppDelegate. Replace the placeholder line in `tray/main.m` with:

```objc
// ---------------------------------------------------------------------------
// AppDelegate — NSStatusBar, NSMenu, user actions
// ---------------------------------------------------------------------------

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (strong) NSStatusItem *statusItem;
@property (strong) DisplayManager *displayManager;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.displayManager = [[DisplayManager alloc] init];

    self.statusItem = [[NSStatusBar systemStatusBar]
                       statusItemWithLength:NSSquareStatusItemLength];

    NSImage *icon = [NSImage imageWithSystemSymbolName:@"display.2"
                                 accessibilityDescription:@"Display Grabber"];
    [icon setTemplate:YES]; // adapts to dark/light menu bar automatically
    self.statusItem.button.image = icon;

    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    self.statusItem.menu = menu;
}

// Called every time the menu is about to open — rebuild from current display state
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];

    NSArray<NSDictionary *> *displays = [self.displayManager listDisplays];

    // --- Status items (non-clickable, show current display state) ---
    for (NSDictionary *d in displays) {
        BOOL isMain = [d[@"isMain"] boolValue];
        NSString *label = [NSString stringWithFormat:@"Display %u — %lu×%lu%@",
            [d[@"id"] unsignedIntValue],
            [d[@"width"] unsignedLongValue],
            [d[@"height"] unsignedLongValue],
            isMain ? @" (main)" : @""];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:label action:nil keyEquivalent:@""];
        item.state = isMain ? NSControlStateValueOn : NSControlStateValueOff;
        item.enabled = NO;
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Auto-detect ---
    NSMenuItem *autoItem = [[NSMenuItem alloc] initWithTitle:@"Auto-detect & set main"
                                                      action:@selector(autoDetect:)
                                               keyEquivalent:@""];
    autoItem.target = self;
    [menu addItem:autoItem];

    // --- Set Main submenu ---
    NSMenuItem *setMainItem = [[NSMenuItem alloc] initWithTitle:@"Set Main Display"
                                                         action:nil
                                                  keyEquivalent:@""];
    NSMenu *setMainMenu = [[NSMenu alloc] init];
    for (NSDictionary *d in displays) {
        CGDirectDisplayID did = [d[@"id"] unsignedIntValue];
        NSString *label = [NSString stringWithFormat:@"Display %u — %lu×%lu",
            did,
            [d[@"width"] unsignedLongValue],
            [d[@"height"] unsignedLongValue]];
        NSMenuItem *sub = [[NSMenuItem alloc] initWithTitle:label
                                                     action:@selector(setMainDisplay:)
                                              keyEquivalent:@""];
        sub.target = self;
        sub.representedObject = d[@"id"];
        [setMainMenu addItem:sub];
    }
    setMainItem.submenu = setMainMenu;
    [menu addItem:setMainItem];

    // --- Dry Run submenu ---
    NSMenuItem *dryRunItem = [[NSMenuItem alloc] initWithTitle:@"Dry Run"
                                                        action:nil
                                                 keyEquivalent:@""];
    NSMenu *dryRunMenu = [[NSMenu alloc] init]; // separate instance from setMainMenu
    for (NSDictionary *d in displays) {
        CGDirectDisplayID did = [d[@"id"] unsignedIntValue];
        NSString *label = [NSString stringWithFormat:@"Display %u — %lu×%lu",
            did,
            [d[@"width"] unsignedLongValue],
            [d[@"height"] unsignedLongValue]];
        NSMenuItem *sub = [[NSMenuItem alloc] initWithTitle:label
                                                     action:@selector(dryRunDisplay:)
                                              keyEquivalent:@""];
        sub.target = self;
        sub.representedObject = d[@"id"];
        [dryRunMenu addItem:sub];
    }
    dryRunItem.submenu = dryRunMenu;
    [menu addItem:dryRunItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Quit ---
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                      action:@selector(quitApp:)
                                               keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];
}

// --- Actions ---

- (void)autoDetect:(id)sender {
    CGDirectDisplayID target = [self.displayManager detectActive];
    if (target == 0) {
        [self showAlert:@"No displays found." informative:@""];
        return;
    }
    NSString *err = nil;
    BOOL ok = [self.displayManager setMain:target error:&err];
    if (!ok) [self showAlert:@"Failed to set display." informative:err ?: @""];
}

- (void)setMainDisplay:(NSMenuItem *)sender {
    CGDirectDisplayID did = [sender.representedObject unsignedIntValue];
    NSString *err = nil;
    BOOL ok = [self.displayManager setMain:did error:&err];
    if (!ok) [self showAlert:@"Failed to set display." informative:err ?: @""];
}

- (void)dryRunDisplay:(NSMenuItem *)sender {
    CGDirectDisplayID did = [sender.representedObject unsignedIntValue];
    NSString *summary = [self.displayManager dryRunForDisplay:did];
    [self showAlert:@"Dry Run" informative:summary];
}

- (void)quitApp:(id)sender {
    // Bootout the LaunchAgent so KeepAlive doesn't relaunch us immediately
    NSString *agentPlist = [NSString stringWithFormat:
        @"%@/Library/LaunchAgents/com.display-grabber.tray.plist",
        NSHomeDirectory()];
    if ([[NSFileManager defaultManager] fileExistsAtPath:agentPlist]) {
        NSString *uid = [NSString stringWithFormat:@"%d", getuid()];
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/bin/launchctl";
        task.arguments = @[@"bootout", [NSString stringWithFormat:@"gui/%@", uid], agentPlist];
        [task launch];
        [task waitUntilExit];
    }
    [NSApp terminate:nil];
}

// --- Helpers ---

- (void)showAlert:(NSString *)message informative:(NSString *)info {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = info ?: @"";
    [alert runModal];
}

@end
```

- [ ] **Step 2: Replace `// MAIN_PLACEHOLDER` with `main()`**

Replace the placeholder line with:

```objc
// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
```

- [ ] **Step 3: Compile the full app**

Run: `make tray`

Expected output ends with something like:
```
codesign --sign - --force dist/DisplayGrabber.app
```
Exit code: 0. No errors. Warnings are acceptable.

If you see `error: use of undeclared identifier` or similar — double-check that the placeholder lines were fully replaced and not left as comments alongside the new code.

- [ ] **Step 4: Smoke-test the app launches**

Run: `open dist/DisplayGrabber.app`

Expected: A monitor icon appears in the macOS menu bar. Click it — the menu should appear with display status items at the top, the three action entries, and Quit.

If the icon does not appear: check Console.app for crash logs from `DisplayGrabber`.

- [ ] **Step 5: Test each menu action manually**

- Click **Dry Run → [any display]**: an alert should appear with "Would set display X…" text.
- Click **Set Main Display → [a display]**: display configuration should apply (the main display should change). If you only have one display, the operation completes silently.
- Click **Auto-detect & set main**: same as above using the current main display.
- Click **Quit**: app exits and does NOT relaunch (since the LaunchAgent is not loaded yet at this point).

- [ ] **Step 6: Commit**

```bash
git add tray/main.m
git commit -m "feat: add AppDelegate and main() — tray app complete"
```

---

### Task 6: Install and verify auto-start

**Files:**
- No new files — uses targets defined in Task 3

- [ ] **Step 1: Install**

Run: `make install-tray`

Expected:
```
cp -r dist/DisplayGrabber.app ~/Applications/
...
launchctl bootstrap gui/<uid> ~/Library/LaunchAgents/com.display-grabber.tray.plist
```
Exit code: 0.

- [ ] **Step 2: Verify the app is running**

Run: `pgrep -l DisplayGrabber`

Expected: a line like `12345 DisplayGrabber`

The menu bar icon should be visible.

- [ ] **Step 3: Verify KeepAlive + Quit interaction**

1. Click Quit in the menu bar.
2. Wait 2 seconds.
3. Run: `pgrep -l DisplayGrabber`
   Expected: no output (app did NOT relaunch, because Quit called `launchctl bootout`).

If the app relaunches immediately, the `bootout` call in `quitApp:` is not finding the plist path. Check `NSHomeDirectory()` matches `$HOME` in the shell.

- [ ] **Step 4: Verify auto-start on login (optional — requires logout)**

Log out and back in. The menu bar icon should appear automatically.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "docs: note install/uninstall steps in plan"
```

---

### Task 7: Verify uninstall

- [ ] **Step 1: Run uninstall**

Run: `make uninstall-tray`

Expected:
```
launchctl bootout gui/<uid> ...
rm -f ...
rm -rf ~/Applications/DisplayGrabber.app
```

- [ ] **Step 2: Confirm app is gone**

Run: `pgrep DisplayGrabber`
Expected: no output.

Run: `ls ~/Applications/DisplayGrabber.app 2>&1`
Expected: `No such file or directory`
