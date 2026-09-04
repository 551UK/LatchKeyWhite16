#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

@interface BSUICAPackageView : UIView
- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle;
@end

@interface SBUIProudLockIconView : UIView
- (void)setState:(long long)state
        animated:(BOOL)animated
      updateText:(BOOL)updateText
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

%hook SBUIProudLockIconView

// Original LatchKey remaps the Face ID coaching states back to Locked.
// iOS 16 moved the real state path to this updateText: selector.
- (void)setState:(long long)state
        animated:(BOOL)animated
      updateText:(BOOL)updateText
         options:(long long)options
      completion:(id)completion {
    if (enabled && (state == 19 || state == 16)) {
        state = 1;
    }

    %orig(state, animated, updateText, options, completion);
}

- (void)layoutSubviews {
    %orig;

    if (!enabled) return;

    UIView *lock = nil;
    UIView *coachingView = nil;

    @try {
        id lockObject = [self valueForKey:@"_lockView"];
        if ([lockObject isKindOfClass:[UIView class]]) {
            lock = (UIView *)lockObject;
        }
    } @catch (__unused NSException *exception) {
        return;
    }

    // This is exactly the original LatchKey Default behavior: keep the
    // system proud-lock view visible and do not alter its frame/transform.
    if (positionOption == 0) {
        self.hidden = NO;
        return;
    }

    @try {
        id coachingObject = [self valueForKey:@"_lazy_faceIDCoachingView"];
        if ([coachingObject isKindOfClass:[UIView class]]) {
            coachingView = (UIView *)coachingObject;
        }
    } @catch (__unused NSException *exception) {
        return;
    }

    if (!lock || !coachingView) return;

    switch (positionOption) {
        case 1: // Status Bar
            self.hidden = NO;
            self.frame = CGRectMake(-lock.frame.origin.x + 38.0,
                                    -coachingView.frame.origin.y,
                                    self.frame.size.width,
                                    self.frame.size.height);
            lock.transform = CGAffineTransformMakeScale(0.6, 0.6);
            break;

        case 2: // Compact Status Bar - right
            self.hidden = NO;
            self.frame = CGRectMake(-lock.frame.origin.x + 65.0,
                                    -coachingView.frame.origin.y + 3.0,
                                    self.frame.size.width,
                                    self.frame.size.height);
            lock.transform = CGAffineTransformMakeScale(0.4, 0.4);
            break;

        case 3: // Compact Status Bar - left
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

// Same theme replacement technique as original LatchKey's iOS 13 hook.
// SpringBoard still owns and drives its real _lockView; only the package
// name/bundle are substituted.
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
