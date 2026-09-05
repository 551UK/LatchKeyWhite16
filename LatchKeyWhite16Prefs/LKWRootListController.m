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
    self.title = @"LatchKey White 16";
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

    PSSpecifier *mainGroup = [PSSpecifier groupSpecifierWithName:@"LatchKey"];
    [mainGroup setProperty:@"Original LatchKey Face ID White animation for rootless iOS 16." forKey:@"footerText"];
    [specifiers addObject:mainGroup];

    [specifiers addObject:[self preferenceSpecifierNamed:@"Enable"
                                                     key:@"enabled"
                                            defaultValue:@YES
                                                    cell:PSSwitchCell]];

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
    NSString *key = [specifier propertyForKey:@"key"];
    id fallback = [specifier propertyForKey:@"default"];
    if (!key) return fallback;

    CFPreferencesAppSynchronize((__bridge CFStringRef)LKWPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)LKWPrefsDomain);
    return value ? CFBridgingRelease(value) : fallback;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;

    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)LKWPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)LKWPrefsDomain);

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)LKWPrefsChanged,
                                         NULL,
                                         NULL,
                                         true);
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
