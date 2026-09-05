#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

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
static CGFloat xOffset = 0.0;
static CGFloat yOffset = 0.0;
static CGFloat glyphScale = 1.0;
static UIColor *animationColor = nil;
static NSHashTable *LKWRootViews = nil;

static char LKWThemedPackageKey;
static char LKWHoldUnlockedKey;
static char LKWRootUnlockedKey;

static UIView *LKWGetViewForKey(id root, NSString *key);
static void LKWApplyGeometry(id root);
static void LKWApplyAnimationColorToPackage(id view);

static id LKWCopyPreference(NSString *key) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LKWPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)LKWPrefsDomain);
    return value ? CFBridgingRelease(value) : nil;
}

static CGFloat LKWClampedScale(CGFloat value) {
    if (value < 0.25) return 0.25;
    if (value > 2.0) return 2.0;
    return value;
}

static CGFloat LKWClampedOffset(CGFloat value) {
    if (value < -300.0) return -300.0;
    if (value > 300.0) return 300.0;
    return value;
}

static UIColor *LKWColorFromHexString(NSString *string) {
    if (![string isKindOfClass:[NSString class]]) return UIColor.whiteColor;

    NSString *hex = [[string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6) return UIColor.whiteColor;

    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&rgb]) return UIColor.whiteColor;

    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static BOOL LKWColorIsWhite(UIColor *color) {
    if (!color) return YES;
    CGFloat red = 1.0, green = 1.0, blue = 1.0, alpha = 1.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) return NO;
    return red >= 0.999 && green >= 0.999 && blue >= 0.999;
}

static void LKWRefreshPrefs(void) {
    id value = LKWCopyPreference(@"enabled");
    enabled = value ? [value boolValue] : YES;

    value = LKWCopyPreference(@"xOffset");
    xOffset = LKWClampedOffset(value ? [value doubleValue] : 0.0);

    value = LKWCopyPreference(@"yOffset");
    yOffset = LKWClampedOffset(value ? [value doubleValue] : 0.0);

    value = LKWCopyPreference(@"glyphScale");
    glyphScale = LKWClampedScale(value ? [value doubleValue] : 1.0);

    value = LKWCopyPreference(@"animationColor");
    animationColor = LKWColorFromHexString([value isKindOfClass:[NSString class]] ? value : @"#FFFFFF");
}

static void LKWRefreshVisibleRoots(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (id root in [LKWRootViews allObjects]) {
            LKWApplyGeometry(root);
            if ([root respondsToSelector:@selector(setNeedsLayout)]) {
                [root setNeedsLayout];
            }
        }
    });
}

static void LKWPrefsChangedCallback(CFNotificationCenterRef center,
                                    void *observer,
                                    CFStringRef name,
                                    const void *object,
                                    CFDictionaryRef userInfo) {
    LKWRefreshPrefs();
    LKWRefreshVisibleRoots();
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

static void LKWRegisterRoot(id root) {
    if (!root) return;
    if (!LKWRootViews) LKWRootViews = [NSHashTable weakObjectsHashTable];
    [LKWRootViews addObject:root];
}

static void LKWApplyAnimationColorToPackage(id view) {
    if (!view || !LKWIsThemedPackage(view) || ![view isKindOfClass:[UIView class]]) return;

    @try {
        CALayer *layer = ((UIView *)view).layer;
        if (!enabled || LKWColorIsWhite(animationColor)) {
            [layer setValue:nil forKey:@"filters"];
            return;
        }

        Class filterClass = NSClassFromString(@"CAFilter");
        SEL selector = NSSelectorFromString(@"filterWithType:");
        if (!filterClass || ![filterClass respondsToSelector:selector]) return;

        id filter = ((id (*)(id, SEL, id))objc_msgSend)(filterClass, selector, @"colorMonochrome");
        if (!filter) return;

        [filter setValue:(__bridge id)animationColor.CGColor forKey:@"inputColor"];
        [filter setValue:@1.0 forKey:@"inputAmount"];
        [layer setValue:@[filter] forKey:@"filters"];
    } @catch (__unused NSException *exception) {
    }
}

static void LKWApplyGeometry(id root) {
    UIView *lockView = LKWGetViewForKey(root, @"_lockView");
    if (!lockView) return;

    if (!enabled) {
        lockView.transform = CGAffineTransformIdentity;
        LKWApplyAnimationColorToPackage(lockView);
        return;
    }

    CGAffineTransform transform = CGAffineTransformMakeScale(glyphScale, glyphScale);
    transform.tx = xOffset;
    transform.ty = yOffset;
    lockView.transform = transform;
    LKWApplyAnimationColorToPackage(lockView);
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

    LKWApplyGeometry(root);
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
    LKWRegisterRoot(self);
    long long filtered = LKWFilteredRootState(self, state);
    LKWUpdateRootState(self, filtered);
    %orig(filtered, animated, updateText, options, completion);
    LKWApplyGeometry(self);
    LKWForceUnlockedVisibility(self);
}

- (void)_transitionToState:(long long)state
                  animated:(BOOL)animated
                updateText:(BOOL)updateText
                   options:(long long)options
                completion:(id)completion {
    LKWRegisterRoot(self);
    long long filtered = LKWFilteredRootState(self, state);
    LKWUpdateRootState(self, filtered);
    %orig(filtered, animated, updateText, options, completion);
    LKWApplyGeometry(self);
    LKWForceUnlockedVisibility(self);

    if (LKWRootHoldingUnlocked(self)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            LKWApplyGeometry(self);
            LKWForceUnlockedVisibility(self);
        });
    }
}

- (void)_transitionToState:(long long)state
                  animated:(BOOL)animated
                   options:(long long)options
                completion:(id)completion {
    LKWRegisterRoot(self);
    long long filtered = LKWFilteredRootState(self, state);
    LKWUpdateRootState(self, filtered);
    %orig(filtered, animated, options, completion);
    LKWApplyGeometry(self);
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
    LKWRegisterRoot(self);
    LKWApplyGeometry(self);
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
        LKWApplyAnimationColorToPackage(view);
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
    LKWApplyAnimationColorToPackage(self);
    return accepted;
}

- (BOOL)setState:(id)state animated:(BOOL)animated {
    if (LKWShouldBlockPackageState(self, state)) return YES;
    BOOL accepted = %orig(state, animated);
    LKWDidAcceptPackageState(self, state, accepted);
    LKWApplyAnimationColorToPackage(self);
    return accepted;
}

- (BOOL)setState:(id)state
        animated:(BOOL)animated
 transitionSpeed:(double)speed
      completion:(id)completion {
    if (LKWShouldBlockPackageState(self, state)) return LKWCompleteBlockedState(completion);
    BOOL accepted = %orig(state, animated, speed, completion);
    LKWDidAcceptPackageState(self, state, accepted);
    LKWApplyAnimationColorToPackage(self);
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
        LKWRootViews = [NSHashTable weakObjectsHashTable];
        LKWRefreshPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        LKWPrefsChangedCallback,
                                        (__bridge CFStringRef)LKWPrefsChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);
    }
}
