#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

@interface BSUICAPackageView : UIView
- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle;
- (BOOL)setState:(id)state animated:(BOOL)animated transitionSpeed:(double)speed completion:(id)completion;
- (BOOL)setState:(id)state onLayer:(id)layer animated:(BOOL)animated transitionSpeed:(double)speed completion:(id)completion;
@end

@interface SBUIProudLockIconView : UIView
- (void)setState:(long long)state animated:(BOOL)animated options:(long long)options completion:(id)completion;
@end

static NSString * const LKWPrefsDomain = @"com.551.latchkeywhite16";
static NSString * const LKWPrefsChanged = @"com.551.latchkeywhite16/preferences.changed";

static BOOL enabled = YES;
static NSInteger positionOption = 0;
static CGFloat xPos = 176.0;
static CGFloat yPos = 53.0;
static CGFloat scale = 1.0;

static char LKWThemedPackageKey;
static char LKWPinPendingKey;
static char LKWPinnedOverlayKey;

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

static void LKWSetPinPending(id package, BOOL pending) {
    objc_setAssociatedObject(package, &LKWPinPendingKey, @(pending), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL LKWPinPending(id package) {
    return [objc_getAssociatedObject(package, &LKWPinPendingKey) boolValue];
}

static SBUIProudLockIconView *LKWFindProudLockAncestor(UIView *view) {
    Class proudClass = NSClassFromString(@"SBUIProudLockIconView");
    UIView *node = view;
    while (node) {
        if (proudClass && [node isKindOfClass:proudClass]) {
            return (SBUIProudLockIconView *)node;
        }
        node = node.superview;
    }
    return nil;
}

static UIView *LKWLockView(SBUIProudLockIconView *view) {
    @try {
        id lock = [view valueForKey:@"_lockView"];
        return [lock isKindOfClass:[UIView class]] ? lock : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void LKWRemovePinnedTick(SBUIProudLockIconView *root) {
    if (!root) return;
    UIView *overlay = objc_getAssociatedObject(root, &LKWPinnedOverlayKey);
    if (overlay) {
        [overlay removeFromSuperview];
        objc_setAssociatedObject(root, &LKWPinnedOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void LKWPositionPinnedTick(SBUIProudLockIconView *root, UIView *source) {
    if (!root || !source || !source.superview) return;
    UIView *overlay = objc_getAssociatedObject(root, &LKWPinnedOverlayKey);
    if (!overlay) return;

    CGRect frame = [root convertRect:source.bounds fromView:source];
    overlay.transform = CGAffineTransformIdentity;
    overlay.frame = frame;
    overlay.hidden = NO;
    overlay.alpha = 1.0;
    overlay.userInteractionEnabled = NO;
    [root bringSubviewToFront:overlay];
}

static void LKWShowPinnedTickForPackage(BSUICAPackageView *source) {
    if (!enabled || !source || !LKWIsThemedPackage(source) || !LKWPinPending(source)) return;

    SBUIProudLockIconView *root = LKWFindProudLockAncestor(source);
    if (!root) return;

    UIView *existing = objc_getAssociatedObject(root, &LKWPinnedOverlayKey);
    if (existing) {
        LKWPositionPinnedTick(root, source);
        return;
    }

    Class packageClass = NSClassFromString(@"BSUICAPackageView");
    NSBundle *themeBundle = LKWFaceIDWhiteBundle();
    if (!packageClass || !themeBundle) return;

    BSUICAPackageView *overlay = [[packageClass alloc] initWithPackageName:@"Face_ID_White" inBundle:themeBundle];
    if (!overlay) return;

    overlay.backgroundColor = UIColor.clearColor;
    overlay.userInteractionEnabled = NO;
    overlay.clipsToBounds = NO;
    [overlay setState:@"Unlocked" animated:NO transitionSpeed:1.0 completion:nil];

    [root addSubview:overlay];
    objc_setAssociatedObject(root, &LKWPinnedOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LKWPositionPinnedTick(root, source);
}

static BOOL LKWStateIs(id state, NSString *name) {
    return [state isKindOfClass:[NSString class]] &&
           [(NSString *)state caseInsensitiveCompare:name] == NSOrderedSame;
}

static void LKWHandlePackageState(BSUICAPackageView *package, id state, BOOL animated, double speed) {
    if (!enabled || !LKWIsThemedPackage(package)) return;

    if (LKWStateIs(state, @"Unlocked")) {
        LKWSetPinPending(package, YES);

        // The original Face ID White Unlocked transition is exactly 1 second.
        // Once it finishes, pin a separate already-Unlocked package over it.
        double safeSpeed = speed > 0.01 ? speed : 1.0;
        double delay = animated ? (1.02 / safeSpeed) : 0.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            LKWShowPinnedTickForPackage(package);
        });
        return;
    }

    if (LKWStateIs(state, @"Locked") || LKWStateIs(state, @"Error")) {
        LKWSetPinPending(package, NO);
        LKWRemovePinnedTick(LKWFindProudLockAncestor(package));
    }
}

%hook SBUIProudLockIconView

- (void)setState:(long long)state animated:(BOOL)animated options:(long long)options completion:(id)completion {
    // Same coaching-state remap as original LatchKey.
    if (enabled && (state == 19 || state == 16)) {
        state = 1;
    }

    // A real Locked state starts a fresh cycle, so remove the pinned tick.
    if (enabled && state == 1) {
        LKWRemovePinnedTick(self);
    }

    %orig(state, animated, options, completion);
}

- (void)setAlpha:(CGFloat)alpha {
    if (enabled && positionOption != 4 && alpha < 1.0) {
        %orig(1.0);
        return;
    }
    %orig(alpha);
}

- (void)setHidden:(BOOL)hidden {
    if (enabled && positionOption != 4 && hidden) {
        %orig(NO);
        return;
    }
    %orig(hidden);
}

- (void)layoutSubviews {
    %orig;

    if (!enabled) return;

    UIView *lock = LKWLockView(self);

    if (positionOption == 0) {
        self.hidden = NO;
        if (lock) LKWPositionPinnedTick(self, lock);
        return;
    }

    UIView *coachingView = nil;
    @try {
        coachingView = [self valueForKey:@"_lazy_faceIDCoachingView"];
    } @catch (__unused NSException *exception) {
        coachingView = nil;
    }

    if (![lock isKindOfClass:[UIView class]] || ![coachingView isKindOfClass:[UIView class]]) {
        if (lock) LKWPositionPinnedTick(self, lock);
        return;
    }

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
            LKWRemovePinnedTick(self);
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

    if (positionOption != 4) {
        LKWPositionPinnedTick(self, lock);
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
        objc_setAssociatedObject(view, &LKWThemedPackageKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LKWSetPinPending(view, NO);
    }
    return view;
}

- (BOOL)setState:(id)state animated:(BOOL)animated transitionSpeed:(double)speed completion:(id)completion {
    LKWHandlePackageState(self, state, animated, speed);
    return %orig(state, animated, speed, completion);
}

- (BOOL)setState:(id)state onLayer:(id)layer animated:(BOOL)animated transitionSpeed:(double)speed completion:(id)completion {
    LKWHandlePackageState(self, state, animated, speed);
    return %orig(state, layer, animated, speed, completion);
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
