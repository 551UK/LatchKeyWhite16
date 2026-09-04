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

static char LKWThemedViewKey;
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
        NSString *path = @"/var/jb/Library/Application Support/LatchKeyWhite16/Face_ID_White.bundle";
        bundle = [NSBundle bundleWithPath:path];
    });
    return bundle;
}

static BOOL LKWStateIs(id state, NSString *name) {
    return [state isKindOfClass:[NSString class]] &&
           [(NSString *)state caseInsensitiveCompare:name] == NSOrderedSame;
}

static BOOL LKWIsThemedView(id view) {
    return [objc_getAssociatedObject(view, &LKWThemedViewKey) boolValue];
}

static BOOL LKWHoldUnlocked(id view) {
    return [objc_getAssociatedObject(view, &LKWHoldUnlockedKey) boolValue];
}

static void LKWSetHoldUnlocked(id view, BOOL hold) {
    objc_setAssociatedObject(view, &LKWHoldUnlockedKey, @(hold), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL LKWHandlePackageState(id view, id state, id completion) {
    if (!enabled || !LKWIsThemedView(view)) return NO;

    if (LKWStateIs(state, @"Unlocked")) {
        LKWSetHoldUnlocked(view, YES);
        return NO;
    }

    if (LKWStateIs(state, @"Locked") || LKWStateIs(state, @"Error")) {
        LKWSetHoldUnlocked(view, NO);
        return NO;
    }

    if (LKWStateIs(state, @"Sleep") && LKWHoldUnlocked(view)) {
        if (completion) {
            void (^block)(BOOL) = completion;
            block(YES);
        }
        return YES;
    }

    return NO;
}

%hook SBUIProudLockIconView

// Same state remap used by the original LatchKey.
- (void)setState:(long long)state animated:(BOOL)animated options:(long long)options completion:(id)completion {
    if (enabled && (state == 19 || state == 16)) {
        state = 1;
    }
    %orig(state, animated, options, completion);
}

- (void)layoutSubviews {
    %orig;

    if (!enabled) return;

    // Default means exactly that: leave Apple's original frame/transform alone.
    if (positionOption == 0) return;

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
        objc_setAssociatedObject(view, &LKWThemedViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LKWSetHoldUnlocked(view, NO);
    }
    return view;
}

// iOS 16 uses this selector for CA package state changes.
- (BOOL)setState:(id)state animated:(BOOL)animated transitionSpeed:(double)speed completion:(id)completion {
    if (LKWHandlePackageState(self, state, completion)) return YES;
    return %orig(state, animated, speed, completion);
}

- (BOOL)setState:(id)state onLayer:(id)layer animated:(BOOL)animated transitionSpeed:(double)speed completion:(id)completion {
    if (LKWHandlePackageState(self, state, completion)) return YES;
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
