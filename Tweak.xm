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
- (void)setState:(long long)state animated:(BOOL)animated updateText:(BOOL)updateText options:(long long)options completion:(id)completion;
- (void)_transitionToState:(long long)state animated:(BOOL)animated updateText:(BOOL)updateText options:(long long)options completion:(id)completion;
- (void)_transitionToState:(long long)state animated:(BOOL)animated options:(long long)options completion:(id)completion;
- (id)_activeViewsForState:(long long)state;
@end

static NSString * const LKWPrefsDomain = @"com.551.latchkeywhite16";
static NSString * const LKWPrefsChanged = @"com.551.latchkeywhite16/preferences.changed";

static BOOL enabled = YES;

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
    objc_setAssociatedObject(view, &LKWHoldUnlockedKey, @(holding), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL LKWRootHoldingUnlocked(id view) {
    return [objc_getAssociatedObject(view, &LKWRootUnlockedKey) boolValue];
}

static void LKWSetRootHoldingUnlocked(id view, BOOL holding) {
    objc_setAssociatedObject(view, &LKWRootUnlockedKey, @(holding), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
    if (!enabled || !LKWRootHoldingUnlocked(root)) return;

    UIView *rootView = [root isKindOfClass:[UIView class]] ? root : nil;
    UIView *iconContainer = LKWGetViewForKey(root, @"_iconContainerView");
    UIView *lockView = LKWGetViewForKey(root, @"_lockView");

    if (rootView) {
        rootView.hidden = NO;
        rootView.alpha = 1.0;
    }

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

static void LKWUpdateRootState(id root, long long state) {
    if (state == 0 || state == 1) {
        LKWSetRootHoldingUnlocked(root, NO);
    } else if (state == 2) {
        LKWSetRootHoldingUnlocked(root, YES);
    }
}

static long long LKWFilteredRootState(id root, long long state) {
    if (!enabled) return state;

    if (LKWRootHoldingUnlocked(root)) {
        if (state == 0 || state == 1 || state == 2) return state;
        return 2;
    }

    if (state == 16 || state == 19) return 1;
    return state;
}

static id LKWViewsByKeepingLockActive(id root, id views, long long state) {
    if (!enabled || (state != 2 && !LKWRootHoldingUnlocked(root))) return views;

    UIView *lockView = LKWGetViewForKey(root, @"_lockView");
    if (!lockView) return views;

    if ([views isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)views;
        return [array containsObject:lockView] ? array : [array arrayByAddingObject:lockView];
    }

    if ([views isKindOfClass:[NSSet class]]) {
        NSSet *set = (NSSet *)views;
        if ([set containsObject:lockView]) return set;
        NSMutableSet *mutableSet = [set mutableCopy];
        [mutableSet addObject:lockView];
        return [mutableSet copy];
    }

    return views;
}

static BOOL LKWShouldBlockPackageState(id view, id state) {
    if (!enabled || !LKWIsThemedPackage(view) || !LKWHoldingUnlocked(view)) return NO;
    return !LKWIsState(state, @"Locked") && !LKWIsState(state, @"Unlocked");
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

%hook SBUIProudLockIconView

- (void)setState:(long long)state
        animated:(BOOL)animated
      updateText:(BOOL)updateText
         options:(long long)options
      completion:(id)completion {
    long long filtered = LKWFilteredRootState(self, state);
    LKWUpdateRootState(self, filtered);
    %orig(filtered, animated, updateText, options, completion);
    LKWForceUnlockedVisibility(self);
}

- (void)_transitionToState:(long long)state
                  animated:(BOOL)animated
                updateText:(BOOL)updateText
                   options:(long long)options
                completion:(id)completion {
    long long filtered = LKWFilteredRootState(self, state);
    LKWUpdateRootState(self, filtered);
    %orig(filtered, animated, updateText, options, completion);
    LKWForceUnlockedVisibility(self);

    if (LKWRootHoldingUnlocked(self)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            LKWForceUnlockedVisibility(self);
        });
    }
}

- (void)_transitionToState:(long long)state
                  animated:(BOOL)animated
                   options:(long long)options
                completion:(id)completion {
    long long filtered = LKWFilteredRootState(self, state);
    LKWUpdateRootState(self, filtered);
    %orig(filtered, animated, options, completion);
    LKWForceUnlockedVisibility(self);
}

- (id)_activeViewsForState:(long long)state {
    return LKWViewsByKeepingLockActive(self, %orig(state), state);
}

- (void)setAlpha:(CGFloat)alpha {
    %orig(enabled && LKWRootHoldingUnlocked(self) ? 1.0 : alpha);
}

- (void)setHidden:(BOOL)hidden {
    %orig(enabled && LKWRootHoldingUnlocked(self) ? NO : hidden);
}

- (void)layoutSubviews {
    %orig;
    LKWForceUnlockedVisibility(self);
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
        objc_setAssociatedObject(view, &LKWThemedPackageKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LKWSetHoldingUnlocked(view, NO);
    }
    return view;
}

- (void)setAlpha:(CGFloat)alpha {
    %orig(enabled && LKWIsThemedPackage(self) && LKWHoldingUnlocked(self) ? 1.0 : alpha);
}

- (void)setHidden:(BOOL)hidden {
    %orig(enabled && LKWIsThemedPackage(self) && LKWHoldingUnlocked(self) ? NO : hidden);
}

- (BOOL)setState:(id)state {
    if (LKWShouldBlockPackageState(self, state)) return YES;
    BOOL accepted = %orig(state);
    LKWDidAcceptPackageState(self, state, accepted);
    return accepted;
}

- (BOOL)setState:(id)state animated:(BOOL)animated {
    if (LKWShouldBlockPackageState(self, state)) return YES;
    BOOL accepted = %orig(state, animated);
    LKWDidAcceptPackageState(self, state, accepted);
    return accepted;
}

- (BOOL)setState:(id)state
        animated:(BOOL)animated
 transitionSpeed:(double)speed
      completion:(id)completion {
    if (LKWShouldBlockPackageState(self, state)) return LKWCompleteBlockedState(completion);
    BOOL accepted = %orig(state, animated, speed, completion);
    LKWDidAcceptPackageState(self, state, accepted);
    return accepted;
}

%end

%hook CSProudLockViewController

- (BOOL)_shouldApplyScaleAndBlurForAuthenticated {
    return enabled ? NO : %orig;
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
