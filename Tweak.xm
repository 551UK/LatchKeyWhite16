#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

@interface BSUICAPackageView : UIView
- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle;
- (BOOL)setState:(id)state;
- (BOOL)setState:(id)state animated:(BOOL)animated;
- (BOOL)setState:(id)state animated:(BOOL)animated transitionSpeed:(double)speed completion:(id)completion;
@end

@interface SBUIProudLockIconView : UIView
- (void)_transitionToState:(long long)state
                  animated:(BOOL)animated
                   options:(long long)options
                completion:(id)completion;
@end

static NSString * const LKWPrefsDomain = @"com.551.latchkeywhite16";
static NSString * const LKWPrefsChanged = @"com.551.latchkeywhite16/preferences.changed";

static BOOL enabled = YES;
static NSInteger positionOption = 0;
static CGFloat xPos = 176.0;
static CGFloat yPos = 53.0;
static CGFloat scale = 1.0;

static char LKWThemedPackageKey;
static char LKWHoldUnlockedKey;

static id LKWCopyPreference(NSString *key) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LKWPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)LKWPrefsDomain);
    return value ? CFBridgingRelease(value) : nil;
}

static void LKWRefreshPrefs(void) {
    id value = LKWCopyPreference(@"enabled");
    enabled = value ? [value boolValue] : YES;

    value = LKWCopyPreference(@"positionOption");
    positionOption = value ? [value integerValue] : 0;

    value = LKWCopyPreference(@"xPos");
    xPos = value ? [value doubleValue] : 176.0;

    value = LKWCopyPreference(@"yPos");
    yPos = value ? [value doubleValue] : 53.0;

    value = LKWCopyPreference(@"scale");
    scale = value ? [value doubleValue] : 1.0;
}

static void LKWPrefsChangedCallback(CFNotificationCenterRef center,
                                    void *observer,
                                    CFStringRef name,
                                    const void *object,
                                    CFDictionaryRef userInfo) {
    LKWRefreshPrefs();
}

static NSBundle *LKWFaceIDWhiteBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundle = [NSBundle bundleWithPath:@"/var/jb/Library/Application Support/LatchKeyWhite16/Face_ID_White.bundle"];
    });
    return bundle;
}

static BOOL LKWIsThemedPackage(id view) {
    return [objc_getAssociatedObject(view, &LKWThemedPackageKey) boolValue];
}

static BOOL LKWIsState(id state, NSString *name) {
    return [state isKindOfClass:[NSString class]] && [(NSString *)state isEqualToString:name];
}

static BOOL LKWHoldingUnlocked(id view) {
    return [objc_getAssociatedObject(view, &LKWHoldUnlockedKey) boolValue];
}

static void LKWSetHoldingUnlocked(id view, BOOL holding) {
    objc_setAssociatedObject(view,
                             &LKWHoldUnlockedKey,
                             @(holding),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL LKWShouldBlockPackageState(id view, id state) {
    if (!enabled || !LKWIsThemedPackage(view) || !LKWHoldingUnlocked(view)) {
        return NO;
    }

    // Locked is the only state that is allowed to end the held final tick.
    if (LKWIsState(state, @"Locked") || LKWIsState(state, @"Unlocked")) {
        return NO;
    }

    return YES;
}

static void LKWDidAcceptPackageState(id view, id state, BOOL accepted) {
    if (!accepted || !LKWIsThemedPackage(view)) return;

    if (LKWIsState(state, @"Locked")) {
        LKWSetHoldingUnlocked(view, NO);
    } else if (LKWIsState(state, @"Unlocked")) {
        // Face_ID_White's Unlocked model state is Face_ID_37.png.
        // Once this state has been reached, do not let a later Sleep/coaching/
        // transient package state replace it until the phone locks again.
        LKWSetHoldingUnlocked(view, YES);
    }
}

static BOOL LKWCompleteBlockedState(id completion) {
    if (completion) {
        void (^block)(BOOL) = (void (^)(BOOL))completion;
        block(YES);
    }
    return YES;
}

%hook SBUIProudLockIconView

// iOS 16 exposes this transition path directly. Keep original LatchKey's
// 16/19 -> Locked behavior here instead of relying on a newer selector.
- (void)_transitionToState:(long long)state
                  animated:(BOOL)animated
                   options:(long long)options
                completion:(id)completion {
    if (enabled && (state == 19 || state == 16)) {
        state = 1;
    }

    %orig(state, animated, options, completion);
}

- (void)layoutSubviews {
    %orig;

    if (!enabled) return;

    UIView *lock = nil;
    UIView *coachingView = nil;

    @try {
        id lockObject = [self valueForKey:@"_lockView"];
        if ([lockObject isKindOfClass:[UIView class]]) {
            lock = (UIView *)lockObject;
        }
    } @catch (__unused NSException *exception) {
        return;
    }

    // Original LatchKey Default: visible, but do not alter Apple's geometry.
    if (positionOption == 0) {
        self.hidden = NO;
        return;
    }

    @try {
        id coachingObject = [self valueForKey:@"_lazy_faceIDCoachingView"];
        if ([coachingObject isKindOfClass:[UIView class]]) {
            coachingView = (UIView *)coachingObject;
        }
    } @catch (__unused NSException *exception) {
        return;
    }

    if (!lock || !coachingView) return;

    switch (positionOption) {
        case 1:
            self.hidden = NO;
            self.frame = CGRectMake(-lock.frame.origin.x + 38.0,
                                    -coachingView.frame.origin.y,
                                    self.frame.size.width,
                                    self.frame.size.height);
            lock.transform = CGAffineTransformMakeScale(0.6, 0.6);
            break;

        case 2:
            self.hidden = NO;
            self.frame = CGRectMake(-lock.frame.origin.x + 65.0,
                                    -coachingView.frame.origin.y + 3.0,
                                    self.frame.size.width,
                                    self.frame.size.height);
            lock.transform = CGAffineTransformMakeScale(0.4, 0.4);
            break;

        case 3:
            self.hidden = NO;
            self.frame = CGRectMake(-lock.frame.origin.x + 14.0,
                                    -coachingView.frame.origin.y + 3.0,
                                    self.frame.size.width,
                                    self.frame.size.height);
            lock.transform = CGAffineTransformMakeScale(0.4, 0.4);
            break;

        case 4:
            self.hidden = YES;
            break;

        case 5:
            self.hidden = NO;
            lock.transform = CGAffineTransformMakeScale(scale, scale);
            self.frame = CGRectMake(-lock.frame.origin.x + xPos,
                                    -coachingView.frame.origin.y + yPos,
                                    self.frame.size.width,
                                    self.frame.size.height);
            break;

        default:
            self.hidden = NO;
            break;
    }
}

%end

%hook BSUICAPackageView

- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle {
    if (!enabled ||
        ![packageName isKindOfClass:[NSString class]] ||
        [packageName rangeOfString:@"lock" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return %orig;
    }

    NSBundle *themeBundle = LKWFaceIDWhiteBundle();
    if (!themeBundle) return %orig;

    id view = %orig(@"Face_ID_White", themeBundle);
    if (view) {
        objc_setAssociatedObject(view,
                                 &LKWThemedPackageKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LKWSetHoldingUnlocked(view, NO);
    }
    return view;
}

- (BOOL)setState:(id)state {
    if (LKWShouldBlockPackageState(self, state)) {
        NSLog(@"[LatchKeyWhite16] keeping Unlocked; blocked package state %@", state);
        return YES;
    }

    BOOL accepted = %orig(state);
    LKWDidAcceptPackageState(self, state, accepted);
    return accepted;
}

- (BOOL)setState:(id)state animated:(BOOL)animated {
    if (LKWShouldBlockPackageState(self, state)) {
        NSLog(@"[LatchKeyWhite16] keeping Unlocked; blocked package state %@", state);
        return YES;
    }

    BOOL accepted = %orig(state, animated);
    LKWDidAcceptPackageState(self, state, accepted);
    return accepted;
}

- (BOOL)setState:(id)state
        animated:(BOOL)animated
 transitionSpeed:(double)speed
      completion:(id)completion {
    if (LKWShouldBlockPackageState(self, state)) {
        NSLog(@"[LatchKeyWhite16] keeping Unlocked; blocked package state %@", state);
        return LKWCompleteBlockedState(completion);
    }

    BOOL accepted = %orig(state, animated, speed, completion);
    LKWDidAcceptPackageState(self, state, accepted);
    return accepted;
}

%end

%ctor {
    @autoreleasepool {
        LKWRefreshPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        LKWPrefsChangedCallback,
                                        (__bridge CFStringRef)LKWPrefsChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);
    }
}
