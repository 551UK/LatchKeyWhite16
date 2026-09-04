#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

@interface BSUICAPackageView : UIView
- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle;
@end

@interface SBUIProudLockIconView : UIView
- (long long)state;
- (void)setState:(long long)state animated:(BOOL)animated options:(long long)options completion:(id)completion;
@end

@interface SBUIProudLockContainerViewController : UIViewController
- (long long)_actualIconState;
@end

static NSString * const LKWPrefsDomain = @"com.551.latchkeywhite16";
static NSString * const LKWPrefsChanged = @"com.551.latchkeywhite16/preferences.changed";

static BOOL enabled = YES;
static NSInteger positionOption = 0;
static CGFloat xPos = 176.0;
static CGFloat yPos = 53.0;
static CGFloat scale = 1.0;

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

static void LKWCompleteStateRequest(id completion) {
    if (!completion) return;
    void (^block)(BOOL) = completion;
    block(NO);
}

%hook SBUIProudLockContainerViewController

// iOS 16 clears the proud-lock icon by moving from state 2 (Unlocked)
// to state 0 (None) after Face ID succeeds. Original LatchKey leaves the
// unlocked tick visible, so keep state 2 until the lock genuinely resets.
- (void)_setIconState:(long long)state
             animated:(BOOL)animated
              options:(long long)options
                force:(BOOL)force
           completion:(id)completion {
    if (enabled && [self _actualIconState] == 2 && state == 0) {
        LKWCompleteStateRequest(completion);
        return;
    }

    %orig(state, animated, options, force, completion);
}

%end

%hook SBUIProudLockIconView

// Same coaching-state remap used by the original LatchKey.
- (void)setState:(long long)state animated:(BOOL)animated options:(long long)options completion:(id)completion {
    if (enabled && (state == 19 || state == 16)) {
        state = 1;
    }
    %orig(state, animated, options, completion);
}

- (void)layoutSubviews {
    %orig;

    if (!enabled || positionOption == 0) return;

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

    return %orig(@"Face_ID_White", themeBundle);
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
