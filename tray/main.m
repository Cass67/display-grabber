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

// APPDELEGATE_PLACEHOLDER
// MAIN_PLACEHOLDER
