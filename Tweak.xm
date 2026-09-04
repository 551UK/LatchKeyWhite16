#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

@interface BSUICAPackageView : UIView
- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle;
- (BOOL)setState:(NSString *)state onLayer:(id)layer animated:(BOOL)animated transitionSpeed:(double)speed completion:(void (^)(BOOL finished))completion;
@end

@interface SBUIProudLockIconView : UIView
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

static UIView *LKWLockContentForView(SBUIProudLockIconView *view) {
    if (!view) return nil;
    @try {
        id lockView = [view valueForKey:@"_lockView"];
        return [lockView isKindOfClass:[UIView class]] ? lockView : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void LKWApplyPosition(SBUIProudLockIconView *view) {
    UIView *container = LKWIconContainerForView(view);
    if (!container) return;

    if (!lkwEnabled) {
        container.transform = CGAffineTransformIdentity;
        return;
    }

    view.hidden = NO;
    view.alpha = 1.0;
    container.hidden = NO;
    container.alpha = 1.0;

    UIView *lockView = LKWLockContentForView(view);
    if (lockView) {
        lockView.hidden = NO;
        lockView.alpha = 1.0;
    }

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
            }
            return view;
        }
    }

    return %orig;
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
        if (completion) completion(YES);
        return YES;
    }

    return %orig;
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
