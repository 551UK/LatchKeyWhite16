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
static char LKWRootUnlockedKey;

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

static BOOL LKWRootHoldingUnlocked(id view) {
    return [objc_getAssociatedObject(view, &LKWRootUnlockedKey) boolValue];
}

static void LKWSetRootHoldingUnlocked(id view, BOOL holding) {
    objc_setAssociatedObject(view,
                             &LKWRootUnlockedKey,
                             @(holding),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *LKWGetViewForKey(id root, NSString *key) {
    @try {
        id value = [root valueForKey:key];
        return [value isKindOfClass:[UIView class]] ? value : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void LKWForceUnlockedVisibility(id root) {
    if (!enabled || positionOption == 4 || !LKWRootHoldingUnlocked(root)) return;

    UIView *rootView = [root isKindOfClass:[UIView class]] ? root : nil;
    UIView *iconContainer = LKWGetViewForKey(root, @"_iconContainerView");
    UIView *lockView = LKWGetViewForKey(root, @"_lockView");

    rootView.hidden = NO;
    rootView.alpha = 1.0;

    if (iconContainer) {
        iconContainer.hidden = NO;
        iconContainer.alpha = 1.0;
    }

    if (lockView) {
        lockView.hidden = NO;
        lockView.alpha = 1.0;
        if (iconContainer && lockView.superview == iconContainer) {
            [iconContainer bringSubviewToFront:lockView];
        }
    }
}

static BOOL LKWShouldBlockPackageState(id view, id state) {
    if (!enabled || !LKWIsThemedPackage(view) || !LKWHoldingUnlocked(view)) {
        return NO;
    }

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
        LKWSetHoldingUnlocked(view, YES);
    }
}

static BOOL LKWCompleteBlockedState(id completion) {
    if (completion) {
        void (^block)(BOOL) = (void (^)(BOOL))completion;
        block(NO);
    }
    return YES;
}

static void LKWCompleteBlockedRootTransition(id completion) {
    if (completion) {
        void (^block)(BOOL) = (void (^)(BOOL))completion;
        block(NO);
    }
}

%hook SBUIProudLockIconView

- (void)_transitionToState:(long long)state
                  animated:(BOOL)animated
                   options:(long long)options
                completion:(id)completion {
    if (!enabled) {
        %orig(state, animated, options, completion);
        return;
    }

    // Once Face ID has successfully reached the Unlocked state, keep the
    // actual proud-lock view on state 2. iOS 16 can send later coaching/
    // transient states that cause the active lock view to be faded out.
    // Ignore those until SpringBoard genuinely asks for Locked again.
    if (LKWRootHoldingUnlocked(self)) {
        if (state == 1 || state == 0) {
            LKWSetRootHoldingUnlocked(self, NO);
        } else if (state != 2) {
            NSLog(@"[LatchKeyWhite16] keeping proud-lock state 2; blocked outer state %lld", state);
            LKWForceUnlockedVisibility(self);
            LKWCompleteBlockedRootTransition(completion);
            return;
        }
    }

    if (!LKWRootHoldingUnlocked(self) && (state == 19 || state == 16)) {
        state = 1;
    }

    if (state == 2) {
        LKWSetRootHoldingUnlocked(self, YES);
    }

    %orig(state, animated, options, completion);

    if (LKWRootHoldingUnlocked(self)) {
        LKWForceUnlockedVisibility(self);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (LKWRootHoldingUnlocked(self)) {
                LKWForceUnlockedVisibility(self);
            }
        });
    }
}

- (void)setAlpha:(CGFloat)alpha {
    if (enabled && positionOption != 4 && LKWRootHoldingUnlocked(self)) {
        %orig(1.0);
    } else {
        %orig(alpha);
    }
}

- (void)setHidden:(BOOL)hidden {
    if (enabled && positionOption != 4 && LKWRootHoldingUnlocked(self)) {
        %orig(NO);
    } else {
        %orig(hidden);
    }
}

- (void)layoutSubviews {
    %orig;

    if (!enabled) return;

    UIView *lock = LKWGetViewForKey(self, @"_lockView");
    UIView *coachingView = nil;

    if (LKWRootHoldingUnlocked(self)) {
        LKWForceUnlockedVisibility(self);
    }

    if (positionOption == 0) {
        self.hidden = NO;
        return;
    }

    coachingView = LKWGetViewForKey(self, @"_lazy_faceIDCoachingView");
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

    if (LKWRootHoldingUnlocked(self)) {
        LKWForceUnlockedVisibility(self);
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

- (void)setAlpha:(CGFloat)alpha {
    if (enabled && positionOption != 4 && LKWIsThemedPackage(self) && LKWHoldingUnlocked(self)) {
        %orig(1.0);
    } else {
        %orig(alpha);
    }
}

- (void)setHidden:(BOOL)hidden {
    if (enabled && positionOption != 4 && LKWIsThemedPackage(self) && LKWHoldingUnlocked(self)) {
        %orig(NO);
    } else {
        %orig(hidden);
    }
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
