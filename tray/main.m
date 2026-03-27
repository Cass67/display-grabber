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
    // CGMainDisplayID() returns the display with the menu bar.
    // Returns 0 if no displays are online.
    return CGMainDisplayID();
}

- (BOOL)setMain:(CGDirectDisplayID)targetID error:(NSString **)errorOut {
    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    CGGetOnlineDisplayList(32, ids, &count);

    CGDisplayConfigRef cfg = NULL;
    CGError err = CGBeginDisplayConfiguration(&cfg);
    if (err != kCGErrorSuccess || cfg == NULL) {
        if (cfg != NULL) CGCancelDisplayConfiguration(cfg);
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
    [icon setTemplate:YES];
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
