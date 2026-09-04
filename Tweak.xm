#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

@interface BSUICAPackageView : UIView
- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle;
- (BOOL)setState:(NSString *)state onLayer:(id)layer animated:(BOOL)animated transitionSpeed:(double)speed completion:(void (^)(BOOL finished))completion;
@end

@interface SBUIProudLockIconView : UIView
- (NSArray *)_activeViewsForState:(long long)state;
- (void)setState:(long long)state animated:(BOOL)animated updateText:(BOOL)updateText options:(long long)options completion:(id)completion;
- (void)_transitionToState:(long long)state animated:(BOOL)animated updateText:(BOOL)updateText options:(long long)options completion:(id)completion;
@end

static NSString * const LKWPrefsDomain = @"com.551.latchkeywhite16";
static NSString * const LKWPrefsChanged = @"com.551.latchkeywhite16/preferences.changed";

static BOOL lkwEnabled = YES;
static CGFloat lkwXOffset = 0.0;
static CGFloat lkwYOffset = 0.0;
static CGFloat lkwScale = 1.0;
static NSHashTable<SBUIProudLockIconView *> *lkwLockViews = nil;
static char LKWThemeMarkerKey;
static char LKWHoldUnlockedKey;

static id LKWPreferenceValue(NSString *key) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LKWPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)LKWPrefsDomain);
    return value ? CFBridgingRelease(value) : nil;
}

static CGFloat LKWClampedValue(id value, CGFloat fallback, CGFloat minimum, CGFloat maximum) {
    if (![value respondsToSelector:@selector(doubleValue)]) return fallback;
    CGFloat result = (CGFloat)[value doubleValue];
    if (!isfinite(result)) return fallback;
    return MAX(minimum, MIN(maximum, result));
}

static void LKWLoadPrefs(void) {
    id enabled = LKWPreferenceValue(@"Enabled");
    lkwEnabled = enabled ? [enabled boolValue] : YES;
    lkwXOffset = LKWClampedValue(LKWPreferenceValue(@"XOffset"), 0.0, -600.0, 600.0);
    lkwYOffset = LKWClampedValue(LKWPreferenceValue(@"YOffset"), 0.0, -900.0, 900.0);
    lkwScale = LKWClampedValue(LKWPreferenceValue(@"Scale"), 1.0, 0.20, 3.00);
}

static NSBundle *LKWWhiteThemeBundle(void) {
    static NSBundle *cachedBundle = nil;
    if (cachedBundle) return cachedBundle;

    NSString *path = @"/var/jb/Library/Application Support/LatchKeyWhite16/Face_ID_White.bundle";
    NSString *animation = [path stringByAppendingPathComponent:@"Face_ID_White.ca/main.caml"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:animation]) return nil;

    cachedBundle = [NSBundle bundleWithPath:path];
    return cachedBundle;
}

static BOOL LKWStateEquals(NSString *state, NSString *wanted) {
    return [state isKindOfClass:[NSString class]] &&
           [state caseInsensitiveCompare:wanted] == NSOrderedSame;
}

static long long LKWRemapProudLockState(long long state) {
    // Original LatchKey behavior: states 16/19 are Face ID coaching/post-auth states.
    // Keeping them at state 1 prevents SpringBoard from replacing/hiding the proud lock.
    if (lkwEnabled && (state == 16 || state == 19)) return 1;
    return state;
}

static BOOL LKWIsThemedPackage(BSUICAPackageView *view) {
    return [objc_getAssociatedObject(view, &LKWThemeMarkerKey) boolValue];
}

static BOOL LKWHoldingUnlocked(BSUICAPackageView *view) {
    return [objc_getAssociatedObject(view, &LKWHoldUnlockedKey) boolValue];
}

static void LKWSetHoldingUnlocked(BSUICAPackageView *view, BOOL hold) {
    objc_setAssociatedObject(view,
                             &LKWHoldUnlockedKey,
                             @(hold),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *LKWIconContainerForView(SBUIProudLockIconView *view) {
    if (!view) return nil;
    @try {
        id container = [view valueForKey:@"_iconContainerView"];
        return [container isKindOfClass:[UIView class]] ? container : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BSUICAPackageView *LKWLockContentForView(SBUIProudLockIconView *view) {
    if (!view) return nil;
    @try {
        id lockView = [view valueForKey:@"_lockView"];
        return [lockView isKindOfClass:[BSUICAPackageView class]] ? lockView : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void LKWForceVisible(SBUIProudLockIconView *view) {
    if (!lkwEnabled || !view) return;

    UIView *container = LKWIconContainerForView(view);
    BSUICAPackageView *lockView = LKWLockContentForView(view);

    view.hidden = NO;
    view.alpha = 1.0;
    view.layer.opacity = 1.0f;

    if (container) {
        container.hidden = NO;
        container.alpha = 1.0;
        container.layer.opacity = 1.0f;
    }

    if (lockView && LKWIsThemedPackage(lockView)) {
        lockView.hidden = NO;
        lockView.alpha = 1.0;
        lockView.layer.opacity = 1.0f;
    }
}

static void LKWApplyPosition(SBUIProudLockIconView *view) {
    UIView *container = LKWIconContainerForView(view);
    if (!container) return;

    if (!lkwEnabled) {
        container.transform = CGAffineTransformIdentity;
        return;
    }

    LKWForceVisible(view);

    CGPoint center = container.center;
    center.x += lkwXOffset;
    center.y += lkwYOffset;
    container.center = center;
    container.transform = CGAffineTransformMakeScale(lkwScale, lkwScale);
}

static void LKWRefreshVisibleLocks(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (SBUIProudLockIconView *view in lkwLockViews.allObjects) {
            [view setNeedsLayout];
            [view layoutIfNeeded];
            LKWForceVisible(view);
        }
    });
}

static void LKWPrefsChangedCallback(CFNotificationCenterRef center,
                                    void *observer,
                                    CFStringRef name,
                                    const void *object,
                                    CFDictionaryRef userInfo) {
    LKWLoadPrefs();
    LKWRefreshVisibleLocks();
}

%hook BSUICAPackageView

- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle {
    if (lkwEnabled &&
        [packageName isKindOfClass:[NSString class]] &&
        [packageName rangeOfString:@"lock" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        NSBundle *theme = LKWWhiteThemeBundle();
        if (theme) {
            BSUICAPackageView *view = %orig(@"Face_ID_White", theme);
            if (view) {
                objc_setAssociatedObject(view,
                                         &LKWThemeMarkerKey,
                                         @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                LKWSetHoldingUnlocked(view, NO);
                view.hidden = NO;
                view.alpha = 1.0;
                view.layer.opacity = 1.0f;
            }
            return view;
        }
    }

    return %orig;
}

- (void)setHidden:(BOOL)hidden {
    if (lkwEnabled && LKWIsThemedPackage(self)) {
        %orig(NO);
        return;
    }
    %orig;
}

- (void)setAlpha:(CGFloat)alpha {
    if (lkwEnabled && LKWIsThemedPackage(self)) {
        %orig(1.0);
        self.layer.opacity = 1.0f;
        return;
    }
    %orig;
}

- (BOOL)setState:(NSString *)state onLayer:(id)layer animated:(BOOL)animated transitionSpeed:(double)speed completion:(void (^)(BOOL finished))completion {
    if (!lkwEnabled || !LKWIsThemedPackage(self)) {
        return %orig;
    }

    if (LKWStateEquals(state, @"Unlocked")) {
        LKWSetHoldingUnlocked(self, YES);
    } else if (LKWStateEquals(state, @"Locked") || LKWStateEquals(state, @"Error")) {
        LKWSetHoldingUnlocked(self, NO);
    } else if (LKWStateEquals(state, @"Sleep") && LKWHoldingUnlocked(self)) {
        self.hidden = NO;
        self.alpha = 1.0;
        self.layer.opacity = 1.0f;
        if (completion) completion(YES);
        return YES;
    }

    BOOL result = %orig;
    self.hidden = NO;
    self.alpha = 1.0;
    self.layer.opacity = 1.0f;
    return result;
}

%end

%hook SBUIProudLockIconView

- (instancetype)initWithFrame:(CGRect)frame {
    SBUIProudLockIconView *view = %orig;
    if (view) {
        if (!lkwLockViews) lkwLockViews = [NSHashTable weakObjectsHashTable];
        [lkwLockViews addObject:view];
    }
    return view;
}

- (void)setHidden:(BOOL)hidden {
    if (lkwEnabled) {
        %orig(NO);
        return;
    }
    %orig;
}

- (void)setAlpha:(CGFloat)alpha {
    if (lkwEnabled) {
        %orig(1.0);
        self.layer.opacity = 1.0f;
        return;
    }
    %orig;
}

- (void)setState:(long long)state animated:(BOOL)animated updateText:(BOOL)updateText options:(long long)options completion:(id)completion {
    state = LKWRemapProudLockState(state);
    %orig(state, animated, updateText, options, completion);
    LKWForceVisible(self);
}

- (void)_transitionToState:(long long)state animated:(BOOL)animated updateText:(BOOL)updateText options:(long long)options completion:(id)completion {
    state = LKWRemapProudLockState(state);
    %orig(state, animated, updateText, options, completion);
    LKWForceVisible(self);
}

- (NSArray *)_activeViewsForState:(long long)state {
    state = LKWRemapProudLockState(state);
    NSArray *original = %orig(state);
    if (!lkwEnabled) return original;

    BSUICAPackageView *lockView = LKWLockContentForView(self);
    if (!lockView || !LKWIsThemedPackage(lockView)) return original;

    NSMutableArray *views = original ? [original mutableCopy] : [NSMutableArray array];
    if (![views containsObject:lockView]) {
        [views addObject:lockView];
    }
    return views;
}

- (void)layoutSubviews {
    %orig;
    LKWApplyPosition(self);
}

%end

%ctor {
    @autoreleasepool {
        lkwLockViews = [NSHashTable weakObjectsHashTable];
        LKWLoadPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        LKWPrefsChangedCallback,
                                        (__bridge CFStringRef)LKWPrefsChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);
    }
}
