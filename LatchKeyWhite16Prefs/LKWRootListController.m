#import "LKWRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <spawn.h>
#import <unistd.h>

extern char **environ;

static NSString * const LKWPrefsDomain = @"com.551.latchkeywhite16";
static NSString * const LKWPrefsChanged = @"com.551.latchkeywhite16/preferences.changed";

static BOOL LKWSpawnTool(const char *tool, char * const argv[]) {
    if (!tool || access(tool, X_OK) != 0) return NO;
    pid_t pid = 0;
    return posix_spawn(&pid, tool, NULL, NULL, argv, environ) == 0;
}

@implementation LKWRootListController

- (void)viewDidLoad {
    [super viewDidLoad];

    UIImage *image = [UIImage systemImageNamed:@"lock.open.fill"];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:image];
    iconView.tintColor = UIColor.labelColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = @"LatchKey White 16";
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    titleLabel.textColor = UIColor.labelColor;

    UIStackView *titleView = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, titleLabel]];
    titleView.axis = UILayoutConstraintAxisHorizontal;
    titleView.alignment = UIStackViewAlignmentCenter;
    titleView.spacing = 6.0;

    [NSLayoutConstraint activateConstraints:@[
        [iconView.widthAnchor constraintEqualToConstant:18.0],
        [iconView.heightAnchor constraintEqualToConstant:18.0]
    ]];

    self.navigationItem.titleView = titleView;
}

- (PSSpecifier *)preferenceSpecifierNamed:(NSString *)name
                                      key:(NSString *)key
                             defaultValue:(id)defaultValue
                                     cell:(PSCellType)cell {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:cell
                                                              edit:nil];
    [specifier setProperty:LKWPrefsDomain forKey:@"defaults"];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:defaultValue forKey:@"default"];
    [specifier setProperty:LKWPrefsChanged forKey:@"PostNotification"];
    return specifier;
}

- (NSArray *)manualSpecifiers {
    NSMutableArray *specifiers = [NSMutableArray array];

    PSSpecifier *mainGroup = [PSSpecifier groupSpecifierWithName:@"LatchKey White 16"];
    [mainGroup setProperty:@"The original LatchKey Face ID White lock animation, adapted for rootless iOS 16." forKey:@"footerText"];
    [specifiers addObject:mainGroup];

    [specifiers addObject:[self preferenceSpecifierNamed:@"Enable"
                                                     key:@"Enabled"
                                            defaultValue:@YES
                                                    cell:PSSwitchCell]];

    PSSpecifier *positionGroup = [PSSpecifier groupSpecifierWithName:@"Custom Position"];
    [positionGroup setProperty:@"Offsets are relative to Apple's normal lock position. Positive X moves right. Positive Y moves down. Scale 1.0 is the original size." forKey:@"footerText"];
    [specifiers addObject:positionGroup];

    PSSpecifier *xOffset = [self preferenceSpecifierNamed:@"X Offset"
                                                       key:@"XOffset"
                                              defaultValue:@0.0
                                                      cell:PSEditTextCell];
    [xOffset setProperty:@YES forKey:@"isNumeric"];
    [xOffset setProperty:@"0" forKey:@"placeholder"];
    [specifiers addObject:xOffset];

    PSSpecifier *yOffset = [self preferenceSpecifierNamed:@"Y Offset"
                                                       key:@"YOffset"
                                              defaultValue:@0.0
                                                      cell:PSEditTextCell];
    [yOffset setProperty:@YES forKey:@"isNumeric"];
    [yOffset setProperty:@"0" forKey:@"placeholder"];
    [specifiers addObject:yOffset];

    PSSpecifier *scale = [self preferenceSpecifierNamed:@"Scale"
                                                     key:@"Scale"
                                            defaultValue:@1.0
                                                    cell:PSEditTextCell];
    [scale setProperty:@YES forKey:@"isDecimalPad"];
    [scale setProperty:@"1.0" forKey:@"placeholder"];
    [specifiers addObject:scale];

    PSSpecifier *reset = [PSSpecifier preferenceSpecifierNamed:@"Reset Position"
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSButtonCell
                                                           edit:nil];
    [reset setButtonAction:@selector(resetPosition)];
    [reset setProperty:NSStringFromSelector(@selector(resetPosition)) forKey:@"action"];
    [specifiers addObject:reset];

    [specifiers addObject:[PSSpecifier groupSpecifierWithName:@"Actions"]];

    PSSpecifier *respring = [PSSpecifier preferenceSpecifierNamed:@"Respring"
                                                            target:self
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                              cell:PSButtonCell
                                                              edit:nil];
    [respring setButtonAction:@selector(respring)];
    [respring setProperty:NSStringFromSelector(@selector(respring)) forKey:@"action"];
    [specifiers addObject:respring];

    PSSpecifier *repo = [PSSpecifier preferenceSpecifierNamed:@"GitHub Repo"
                                                        target:self
                                                           set:nil
                                                           get:nil
                                                        detail:nil
                                                          cell:PSButtonCell
                                                          edit:nil];
    [repo setButtonAction:@selector(openRepo)];
    [repo setProperty:NSStringFromSelector(@selector(openRepo)) forKey:@"action"];
    [specifiers addObject:repo];

    return specifiers;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self manualSpecifiers] copy];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *defaults = [specifier propertyForKey:@"defaults"] ?: LKWPrefsDomain;
    NSString *key = [specifier propertyForKey:@"key"];
    id defaultValue = [specifier propertyForKey:@"default"];

    if (!key) return defaultValue;

    CFPreferencesAppSynchronize((__bridge CFStringRef)defaults);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)defaults);
    return value ? CFBridgingRelease(value) : defaultValue;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *defaults = [specifier propertyForKey:@"defaults"] ?: LKWPrefsDomain;
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *notification = [specifier propertyForKey:@"PostNotification"];

    if (!key) return;

    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)defaults);
    CFPreferencesAppSynchronize((__bridge CFStringRef)defaults);

    if (notification.length > 0) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             (__bridge CFStringRef)notification,
                                             NULL,
                                             NULL,
                                             true);
    }
}

- (void)postPreferencesChanged {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LKWPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)LKWPrefsChanged,
                                         NULL,
                                         NULL,
                                         true);
}

- (void)resetPosition {
    CFPreferencesSetAppValue(CFSTR("XOffset"), (__bridge CFPropertyListRef)@0.0, (__bridge CFStringRef)LKWPrefsDomain);
    CFPreferencesSetAppValue(CFSTR("YOffset"), (__bridge CFPropertyListRef)@0.0, (__bridge CFStringRef)LKWPrefsDomain);
    CFPreferencesSetAppValue(CFSTR("Scale"), (__bridge CFPropertyListRef)@1.0, (__bridge CFStringRef)LKWPrefsDomain);
    [self postPreferencesChanged];
    [self reloadSpecifiers];
}

- (void)resetPosition:(id)sender {
    [self resetPosition];
}

- (void)openRepo {
    NSURL *url = [NSURL URLWithString:@"https://github.com/551UK/LatchKeyWhite16"];
    if (!url) return;

    UIApplication *application = UIApplication.sharedApplication;
    if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [application openURL:url options:@{} completionHandler:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [application openURL:url];
#pragma clang diagnostic pop
    }
}

- (void)openRepo:(id)sender {
    [self openRepo];
}

- (void)respring {
    const char *sbreload = "/var/jb/usr/bin/sbreload";
    if (access(sbreload, X_OK) == 0) {
        char *args[] = {(char *)sbreload, NULL};
        if (LKWSpawnTool(sbreload, args)) return;
    }

    const char *rootlessKillall = "/var/jb/usr/bin/killall";
    if (access(rootlessKillall, X_OK) == 0) {
        char *args[] = {(char *)rootlessKillall, (char *)"-9", (char *)"SpringBoard", NULL};
        if (LKWSpawnTool(rootlessKillall, args)) return;
    }

    const char *systemKillall = "/usr/bin/killall";
    char *args[] = {(char *)systemKillall, (char *)"-9", (char *)"SpringBoard", NULL};
    LKWSpawnTool(systemKillall, args);
}

- (void)respring:(id)sender {
    [self respring];
}

@end
