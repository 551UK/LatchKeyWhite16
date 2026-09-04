#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface BSUICAPackageView : UIView
- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle;
- (BOOL)setState:(id)state animated:(BOOL)animated transitionSpeed:(double)speed completion:(id)completion;
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

static char LKWOwnedPackageKey;
static char LKWOwnedStateKey;
static char LKWFreezeGenerationKey;

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

static UIView *LKWSystemLockView(SBUIProudLockIconView *root) {
    @try {
        id lock = [root valueForKey:@"_lockView"];
        return [lock isKindOfClass:[UIView class]] ? lock : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BSUICAPackageView *LKWOwnedPackage(SBUIProudLockIconView *root) {
    id package = objc_getAssociatedObject(root, &LKWOwnedPackageKey);
    Class packageClass = NSClassFromString(@"BSUICAPackageView");
    return (packageClass && [package isKindOfClass:packageClass]) ? package : nil;
}

static NSUInteger LKWAdvanceFreezeGeneration(SBUIProudLockIconView *root) {
    NSUInteger generation = [objc_getAssociatedObject(root, &LKWFreezeGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(root, &LKWFreezeGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return generation;
}

static void LKWResumePackageLayer(BSUICAPackageView *package) {
    if (!package) return;
    CALayer *layer = package.layer;
    layer.speed = 1.0;
    layer.timeOffset = 0.0;
    layer.beginTime = 0.0;
}

static void LKWPausePackageLayer(BSUICAPackageView *package) {
    if (!package) return;
    CALayer *layer = package.layer;
    if (layer.speed == 0.0) return;

    // Freeze the complete CA package presentation tree at exactly the frame
    // currently being displayed. Because speed is set on the root layer, all
    // of the package's sublayer animations pause with it.
    CFTimeInterval pausedTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
    layer.speed = 0.0;
    layer.timeOffset = pausedTime;
}

static void LKWSyncOwnedPackage(SBUIProudLockIconView *root) {
    UIView *systemLock = LKWSystemLockView(root);
    BSUICAPackageView *owned = LKWOwnedPackage(root);
    if (!systemLock || !owned || !systemLock.superview) return;

    if (owned.superview != systemLock.superview) {
        [owned removeFromSuperview];
        [systemLock.superview addSubview:owned];
    }

    owned.transform = CGAffineTransformIdentity;
    owned.bounds = systemLock.bounds;
    owned.center = systemLock.center;
    owned.transform = systemLock.transform;
    owned.alpha = 1.0;
    owned.hidden = (positionOption == 4);
    owned.userInteractionEnabled = NO;

    systemLock.hidden = YES;
    [systemLock.superview bringSubviewToFront:owned];
}

static BSUICAPackageView *LKWEnsureOwnedPackage(SBUIProudLockIconView *root) {
    BSUICAPackageView *owned = LKWOwnedPackage(root);
    UIView *systemLock = LKWSystemLockView(root);
    if (owned) {
        LKWSyncOwnedPackage(root);
        return owned;
    }

    if (!root || !systemLock || !systemLock.superview) return nil;

    Class packageClass = NSClassFromString(@"BSUICAPackageView");
    NSBundle *themeBundle = LKWFaceIDWhiteBundle();
    if (!packageClass || !themeBundle) return nil;

    owned = [(BSUICAPackageView *)[packageClass alloc] initWithPackageName:@"Face_ID_White"
                                                                  inBundle:themeBundle];
    if (!owned) return nil;

    owned.backgroundColor = UIColor.clearColor;
    owned.userInteractionEnabled = NO;
    owned.clipsToBounds = NO;
    LKWResumePackageLayer(owned);
    [owned setState:@"Locked" animated:NO transitionSpeed:1.0 completion:nil];

    objc_setAssociatedObject(root, &LKWOwnedPackageKey, owned, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(root, &LKWOwnedStateKey, @1, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(root, &LKWFreezeGenerationKey, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [systemLock.superview addSubview:owned];
    LKWSyncOwnedPackage(root);
    return owned;
}

static void LKWDriveOwnedPackage(SBUIProudLockIconView *root, long long requestedState) {
    BSUICAPackageView *owned = LKWEnsureOwnedPackage(root);
    if (!owned) return;

    NSInteger current = [objc_getAssociatedObject(root, &LKWOwnedStateKey) integerValue];

    if (requestedState == 2) {
        if (current != 2) {
            NSUInteger generation = LKWAdvanceFreezeGeneration(root);
            LKWResumePackageLayer(owned);

            // Play the real original Face ID White CA animation.
            [owned setState:@"Unlocked" animated:YES transitionSpeed:1.0 completion:nil];
            objc_setAssociatedObject(root, &LKWOwnedStateKey, @2, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            // In the original CAML, Face_ID_37 (the final tick) becomes the
            // active keyframe at 0.60s. Pause at 0.75s: the tick is already
            // fully visible, but the transition has not yet completed and
            // therefore cannot resolve into the blurred post-animation state.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (!enabled) return;
                if (LKWOwnedPackage(root) != owned) return;
                if ([objc_getAssociatedObject(root, &LKWFreezeGenerationKey) unsignedIntegerValue] != generation) return;
                if ([objc_getAssociatedObject(root, &LKWOwnedStateKey) integerValue] != 2) return;
                LKWPausePackageLayer(owned);
            });
        }
        return;
    }

    if (requestedState == 1) {
        // Invalidate any pending freeze and return the package to a normal
        // running layer before resetting it for the next lock cycle.
        LKWAdvanceFreezeGeneration(root);
        if (current != 1) {
            LKWResumePackageLayer(owned);
            [owned setState:@"Locked" animated:NO transitionSpeed:1.0 completion:nil];
            objc_setAssociatedObject(root, &LKWOwnedStateKey, @1, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    // None/coaching/matched/reticle/spinner/etc. never reach our package.
    // After the unlock animation is frozen, nothing can advance it further.
}

%hook SBUIProudLockIconView

- (void)setState:(long long)state animated:(BOOL)animated options:(long long)options completion:(id)completion {
    long long requestedState = state;

    // Same coaching-state remap used by original LatchKey.
    if (enabled && (state == 19 || state == 16)) {
        state = 1;
    }

    %orig(state, animated, options, completion);

    if (enabled) {
        LKWDriveOwnedPackage(self, requestedState);
    }
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

    UIView *lock = LKWSystemLockView(self);

    if (!enabled) {
        if (lock) lock.hidden = NO;
        BSUICAPackageView *owned = LKWOwnedPackage(self);
        if (owned) {
            LKWResumePackageLayer(owned);
            owned.hidden = YES;
        }
        return;
    }

    LKWEnsureOwnedPackage(self);

    if (positionOption == 0) {
        self.hidden = NO;
        LKWSyncOwnedPackage(self);
        return;
    }

    UIView *coachingView = nil;
    @try {
        coachingView = [self valueForKey:@"_lazy_faceIDCoachingView"];
    } @catch (__unused NSException *exception) {
        coachingView = nil;
    }

    if (![lock isKindOfClass:[UIView class]] || ![coachingView isKindOfClass:[UIView class]]) {
        LKWSyncOwnedPackage(self);
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

    LKWSyncOwnedPackage(self);
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
