#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

// ---------------------------------------------------------------------------
// DisplayManager — CoreGraphics display queries and configuration
// ---------------------------------------------------------------------------

@interface DisplayManager : NSObject
- (NSArray<NSDictionary *> *)listDisplays;
- (CGDirectDisplayID)detectActive;
- (BOOL)setMain:(CGDirectDisplayID)targetID error:(NSString **)errorOut;
- (BOOL)unmirrorOrdered:(NSArray<NSNumber *> *)orderedIDs mainID:(CGDirectDisplayID)mainID error:(NSString **)errorOut;
- (NSString *)dryRunForDisplay:(CGDirectDisplayID)targetID;
@end

@implementation DisplayManager

- (NSDictionary<NSNumber *, NSString *> *)_fetchDisplayNames {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/system_profiler"];
    task.arguments = @[@"SPDisplaysDataType", @"-json"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    NSError *launchErr = nil;
    if (![task launchAndReturnError:&launchErr]) return @{};
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!json) return @{};

    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (NSDictionary *gpu in json[@"SPDisplaysDataType"] ?: @[]) {
        for (NSDictionary *monitor in gpu[@"spdisplays_ndrvs"] ?: @[]) {
            id rawID = monitor[@"_spdisplays_displayID"];
            NSString *name = monitor[@"_name"];
            if (rawID && name) {
                NSNumber *key = @([rawID unsignedIntValue]);
                names[key] = name;
            }
        }
    }
    return names;
}

- (NSArray<NSDictionary *> *)listDisplays {
    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    CGError err = CGGetOnlineDisplayList(32, ids, &count);
    if (err != kCGErrorSuccess) return @[];

    NSDictionary<NSNumber *, NSString *> *names = [self _fetchDisplayNames];

    NSMutableArray *result = [NSMutableArray array];
    for (uint32_t i = 0; i < count; i++) {
        CGDirectDisplayID did = ids[i];
        size_t w = CGDisplayPixelsWide(did);
        size_t h = CGDisplayPixelsHigh(did);
        BOOL isMain = CGDisplayIsMain(did);
        NSString *name = names[@(did)] ?: @"";
        [result addObject:@{
            @"id":     @(did),
            @"width":  @(w),
            @"height": @(h),
            @"isMain": @(isMain),
            @"name":   name,
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

// orderedIDs: physical left-to-right order. mainID: which display gets the menu bar (can be anywhere in the row).
- (BOOL)unmirrorOrdered:(NSArray<NSNumber *> *)orderedIDs mainID:(CGDirectDisplayID)mainID error:(NSString **)errorOut {
    // Step 1: firmly claim the menu bar on mainID using setMain.
    if (![self setMain:mainID error:errorOut]) return NO;

    // Step 2: remove all mirroring.
    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    CGGetOnlineDisplayList(32, ids, &count);

    CGDisplayConfigRef cfg = NULL;
    CGError err = CGBeginDisplayConfiguration(&cfg);
    if (err != kCGErrorSuccess || cfg == NULL) {
        if (cfg != NULL) CGCancelDisplayConfiguration(cfg);
        if (errorOut) *errorOut = [NSString stringWithFormat:@"CGBeginDisplayConfiguration (unmirror) failed (%d)", err];
        return NO;
    }
    for (uint32_t i = 0; i < count; i++) {
        CGConfigureDisplayMirrorOfDisplay(cfg, ids[i], kCGNullDirectDisplay);
    }
    err = CGCompleteDisplayConfiguration(cfg, kCGConfigureForSession);
    if (err != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(cfg);
        if (errorOut) *errorOut = [NSString stringWithFormat:@"CGCompleteDisplayConfiguration (unmirror) failed (%d)", err];
        return NO;
    }

    // Step 3: lay out displays in the requested physical order.
    // mainID sits at (0,0); displays to its left get negative x coords,
    // displays to its right get positive x coords.
    NSUInteger mainIdx = [orderedIDs indexOfObject:@(mainID)];

    cfg = NULL;
    err = CGBeginDisplayConfiguration(&cfg);
    if (err != kCGErrorSuccess || cfg == NULL) {
        if (cfg != NULL) CGCancelDisplayConfiguration(cfg);
        if (errorOut) *errorOut = [NSString stringWithFormat:@"CGBeginDisplayConfiguration (layout) failed (%d)", err];
        return NO;
    }

    CGConfigureDisplayOrigin(cfg, mainID, 0, 0);

    // Displays to the right of main
    int32_t xRight = (int32_t)CGDisplayPixelsWide(mainID);
    for (NSUInteger i = mainIdx + 1; i < orderedIDs.count; i++) {
        CGDirectDisplayID did = [orderedIDs[i] unsignedIntValue];
        CGConfigureDisplayOrigin(cfg, did, xRight, 0);
        xRight += (int32_t)CGDisplayPixelsWide(did);
    }

    // Displays to the left of main (negative x)
    int32_t xLeft = 0;
    for (NSInteger i = (NSInteger)mainIdx - 1; i >= 0; i--) {
        CGDirectDisplayID did = [orderedIDs[i] unsignedIntValue];
        xLeft -= (int32_t)CGDisplayPixelsWide(did);
        CGConfigureDisplayOrigin(cfg, did, xLeft, 0);
    }

    err = CGCompleteDisplayConfiguration(cfg, kCGConfigureForSession);
    if (err != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(cfg);
        if (errorOut) *errorOut = [NSString stringWithFormat:@"CGCompleteDisplayConfiguration (layout) failed (%d)", err];
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

- (NSString *)_labelForDisplay:(NSDictionary *)d {
    NSString *name = [d[@"name"] length] > 0 ? [NSString stringWithFormat:@" — %@", d[@"name"]] : @"";
    return [NSString stringWithFormat:@"Display %u (%lu×%lu)%@",
        [d[@"id"] unsignedIntValue],
        [d[@"width"] unsignedLongValue],
        [d[@"height"] unsignedLongValue],
        name];
}

// Short name for permutation labels: monitor name if known, else "Display N"
- (NSString *)_shortNameForDisplay:(NSDictionary *)d {
    if ([d[@"name"] length] > 0) return d[@"name"];
    return [NSString stringWithFormat:@"Display %u", [d[@"id"] unsignedIntValue]];
}

// Generate all permutations of an array (for ≤4 displays this is fine)
- (NSArray<NSArray *> *)_permutations:(NSArray *)arr {
    if (arr.count <= 1) return @[arr];
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < arr.count; i++) {
        NSMutableArray *rest = [arr mutableCopy];
        [rest removeObjectAtIndex:i];
        for (NSArray *perm in [self _permutations:rest]) {
            NSMutableArray *full = [NSMutableArray arrayWithObject:arr[i]];
            [full addObjectsFromArray:perm];
            [result addObject:full];
        }
    }
    return result;
}

// Called every time the menu is about to open — rebuild from current display state
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];

    NSArray<NSDictionary *> *displays = [self.displayManager listDisplays];

    // --- Status items (non-clickable, show current display state) ---
    for (NSDictionary *d in displays) {
        BOOL isMain = [d[@"isMain"] boolValue];
        NSString *label = [NSString stringWithFormat:@"%@%@",
            [self _labelForDisplay:d],
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
        NSMenuItem *sub = [[NSMenuItem alloc] initWithTitle:[self _labelForDisplay:d]
                                                     action:@selector(setMainDisplay:)
                                              keyEquivalent:@""];
        sub.target = self;
        sub.representedObject = d[@"id"];
        [setMainMenu addItem:sub];
    }
    setMainItem.submenu = setMainMenu;
    [menu addItem:setMainItem];

    // --- Unmirror / Extend ---
    // Top level: pick which display gets the menu bar.
    // Sub-submenu: all 6 physical orderings, with the chosen display marked (★).
    NSMenuItem *unmirrorItem = [[NSMenuItem alloc] initWithTitle:@"Unmirror (Extended Desktop)"
                                                          action:nil
                                                   keyEquivalent:@""];
    NSMenu *unmirrorMenu = [[NSMenu alloc] init];
    for (NSDictionary *mainDisplay in displays) {
        NSMenuItem *mainItem = [[NSMenuItem alloc] initWithTitle:[self _shortNameForDisplay:mainDisplay]
                                                          action:nil
                                                   keyEquivalent:@""];
        NSMenu *orderMenu = [[NSMenu alloc] init];
        for (NSArray<NSDictionary *> *perm in [self _permutations:displays]) {
            NSMutableArray *names = [NSMutableArray array];
            NSMutableArray *ids   = [NSMutableArray array];
            for (NSDictionary *d in perm) {
                NSString *name = [self _shortNameForDisplay:d];
                if ([d[@"id"] isEqual:mainDisplay[@"id"]]) name = [name stringByAppendingString:@"★"];
                [names addObject:name];
                [ids addObject:d[@"id"]];
            }
            NSMenuItem *orderItem = [[NSMenuItem alloc] initWithTitle:[names componentsJoinedByString:@" → "]
                                                               action:@selector(unmirrorOrdered:)
                                                        keyEquivalent:@""];
            orderItem.target = self;
            orderItem.representedObject = @{@"main": mainDisplay[@"id"], @"order": ids};
            [orderMenu addItem:orderItem];
        }
        mainItem.submenu = orderMenu;
        [unmirrorMenu addItem:mainItem];
    }
    unmirrorItem.submenu = unmirrorMenu;
    [menu addItem:unmirrorItem];

    // --- Dry Run submenu ---
    NSMenuItem *dryRunItem = [[NSMenuItem alloc] initWithTitle:@"Dry Run"
                                                        action:nil
                                                 keyEquivalent:@""];
    NSMenu *dryRunMenu = [[NSMenu alloc] init];
    for (NSDictionary *d in displays) {
        NSMenuItem *sub = [[NSMenuItem alloc] initWithTitle:[self _labelForDisplay:d]
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

- (void)unmirrorOrdered:(NSMenuItem *)sender {
    NSDictionary *config = sender.representedObject;
    NSArray<NSNumber *> *orderedIDs = config[@"order"];
    CGDirectDisplayID mainID = [config[@"main"] unsignedIntValue];
    NSString *err = nil;
    BOOL ok = [self.displayManager unmirrorOrdered:orderedIDs mainID:mainID error:&err];
    if (!ok) [self showAlert:@"Failed to unmirror displays." informative:err ?: @""];
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
        task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
        task.arguments = @[@"bootout", [NSString stringWithFormat:@"gui/%@", uid], agentPlist];
        [task launchAndReturnError:nil];
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
