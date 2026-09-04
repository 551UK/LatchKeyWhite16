#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

@interface BSUICAPackageView : UIView
- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle;
@end

@interface SBUIProudLockIconView : UIView
- (void)setState:(long long)state animated:(BOOL)animated options:(long long)options completion:(id)completion;
- (id)_activeViewsForState:(long long)state;
@end

static NSString * const LKWPrefsDomain = @"com.551.latchkeywhite16";
static NSString * const LKWPrefsChanged = @"com.551.latchkeywhite16/preferences.changed";

static BOOL enabled = YES;
static NSInteger positionOption = 0;
static CGFloat xPos = 176.0;
static CGFloat yPos = 53.0;
static CGFloat scale = 1.0;

static char LKWThemedPackageKey;

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
        NSString *path = @"/var/jb/Library/Application Support/LatchKeyWhite16/Face_ID_White.bundle";
        bundle = [NSBundle bundleWithPath:path];
    });
    return bundle;
}

static BOOL LKWIsThemedPackage(id view) {
    return [objc_getAssociatedObject(view, &LKWThemedPackageKey) boolValue];
}

static UIView *LKWLockView(SBUIProudLockIconView *view) {
    @try {
        id lock = [view valueForKey:@"_lockView"];
        return [lock isKindOfClass:[UIView class]] ? lock : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

%hook SBUIProudLockIconView

// Same coaching-state remap used by the original LatchKey.
- (void)setState:(long long)state animated:(BOOL)animated options:(long long)options completion:(id)completion {
    if (enabled && (state == 19 || state == 16)) {
        state = 1;
    }
    %orig(state, animated, options, completion);
}

// iOS 16 can switch between several internal glyph views and fade any view
// that drops out of the active set. Keep our themed lock package active so it
// is never treated as an outgoing glyph after the Face ID tick completes.
- (id)_activeViewsForState:(long long)state {
    id original = %orig(state);
    if (!enabled) return original;

    UIView *lock = LKWLockView(self);
    if (!lock || !LKWIsThemedPackage(lock)) return original;

    if (!original) {
        return @[lock];
    }

    if ([original isKindOfClass:[NSArray class]]) {
        NSArray *views = (NSArray *)original;
        if ([views containsObject:lock]) return original;

        NSMutableArray *updated = [views mutableCopy];
        [updated addObject:lock];
        return updated;
    }

    return original;
}

- (void)layoutSubviews {
    %orig;

    if (!enabled) return;

    // Match original LatchKey: Default keeps Apple's frame/transform exactly
    // as-is, but never hides the proud-lock container.
    if (positionOption == 0) {
        self.hidden = NO;
        return;
    }

    UIView *lock = nil;
    UIView *coachingView = nil;

    @try {
        lock = [self valueForKey:@"_lockView"];
        coachingView = [self valueForKey:@"_lazy_faceIDCoachingView"];
    } @catch (__unused NSException *exception) {
        return;
    }

    if (![lock isKindOfClass:[UIView class]] || ![coachingView isKindOfClass:[UIView class]]) {
        return;
    }

    switch (positionOption) {
        case 1: // Status Bar
            self.hidden = NO;
            self.frame = CGRectMake(-lock.frame.origin.x + 38.0,
                                    -coachingView.frame.origin.y,
                                    self.frame.size.width,
                                    self.frame.size.height);
            lock.transform = CGAffineTransformMakeScale(0.6, 0.6);
            break;

        case 2: // Compact Status Bar (right)
            self.hidden = NO;
            self.frame = CGRectMake(-lock.frame.origin.x + 65.0,
                                    -coachingView.frame.origin.y + 3.0,
                                    self.frame.size.width,
                                    self.frame.size.height);
            lock.transform = CGAffineTransformMakeScale(0.4, 0.4);
            break;

        case 3: // Compact Status Bar (left)
            self.hidden = NO;
            self.frame = CGRectMake(-lock.frame.origin.x + 14.0,
                                    -coachingView.frame.origin.y + 3.0,
                                    self.frame.size.width,
                                    self.frame.size.height);
            lock.transform = CGAffineTransformMakeScale(0.4, 0.4);
            break;

        case 4: // Hidden
            self.hidden = YES;
            break;

        case 5: // Custom
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

// Same theme replacement method used by original LatchKey, adapted for the
// rootless theme path. Mark only the package instance that we replace.
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
    }
    return view;
}

// Modern SBUIProudLockIconView fades outgoing active views by setting the
// UIView alpha to zero. LockGlyph-style tweaks avoid that system-owned fade;
// do the same only for our marked Face ID White package.
- (void)setAlpha:(CGFloat)alpha {
    if (enabled && LKWIsThemedPackage(self) && alpha < 1.0) {
        %orig(1.0);
        return;
    }
    %orig(alpha);
}

- (void)setHidden:(BOOL)hidden {
    if (enabled && LKWIsThemedPackage(self) && hidden) {
        %orig(NO);
        return;
    }
    %orig(hidden);
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
