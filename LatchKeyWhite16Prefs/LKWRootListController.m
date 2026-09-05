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

static NSString *LKWHexStringFromColor(UIColor *color) {
    CGFloat red = 1.0, green = 1.0, blue = 1.0, alpha = 1.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) return @"#FFFFFF";
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (unsigned int)lrint(red * 255.0),
            (unsigned int)lrint(green * 255.0),
            (unsigned int)lrint(blue * 255.0)];
}

@interface LKWRootListController () <UIColorPickerViewControllerDelegate>
@end

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

    PSSpecifier *appearanceGroup = [PSSpecifier groupSpecifierWithName:@"Appearance"];
    [appearanceGroup setProperty:@"Choose any animation colour. White restores the original animation exactly." forKey:@"footerText"];
    [specifiers addObject:appearanceGroup];

    PSSpecifier *color = [PSSpecifier preferenceSpecifierNamed:@"Animation Color"
                                                        target:self
                                                           set:nil
                                                           get:nil
                                                        detail:nil
                                                          cell:PSButtonCell
                                                          edit:nil];
    [color setButtonAction:@selector(openColorPicker)];
    [color setProperty:NSStringFromSelector(@selector(openColorPicker)) forKey:@"action"];
    [specifiers addObject:color];

    PSSpecifier *resetColor = [PSSpecifier preferenceSpecifierNamed:@"Reset Color to White"
                                                             target:self
                                                                set:nil
                                                                get:nil
                                                             detail:nil
                                                               cell:PSButtonCell
                                                               edit:nil];
    [resetColor setButtonAction:@selector(resetAnimationColor)];
    [resetColor setProperty:NSStringFromSelector(@selector(resetAnimationColor)) forKey:@"action"];
    [specifiers addObject:resetColor];

    PSSpecifier *positionGroup = [PSSpecifier groupSpecifierWithName:@"Position & Scale"];
    [positionGroup setProperty:@"Changes apply directly to the real lock glyph. Positive X moves right; positive Y moves down. Scale range: 0.25 to 2.0." forKey:@"footerText"];
    [specifiers addObject:positionGroup];

    PSSpecifier *x = [self preferenceSpecifierNamed:@"X Offset"
                                                 key:@"xOffset"
                                        defaultValue:@0.0
                                                cell:PSEditTextCell];
    [x setProperty:@"0" forKey:@"placeholder"];
    [specifiers addObject:x];

    PSSpecifier *y = [self preferenceSpecifierNamed:@"Y Offset"
                                                 key:@"yOffset"
                                        defaultValue:@0.0
                                                cell:PSEditTextCell];
    [y setProperty:@"0" forKey:@"placeholder"];
    [specifiers addObject:y];

    PSSpecifier *scale = [self preferenceSpecifierNamed:@"Scale"
                                                     key:@"glyphScale"
                                            defaultValue:@1.0
                                                    cell:PSEditTextCell];
    [scale setProperty:@"1.0" forKey:@"placeholder"];
    [specifiers addObject:scale];

    PSSpecifier *reset = [PSSpecifier preferenceSpecifierNamed:@"Reset Position & Scale"
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSButtonCell
                                                           edit:nil];
    [reset setButtonAction:@selector(resetGeometry)];
    [reset setProperty:NSStringFromSelector(@selector(resetGeometry)) forKey:@"action"];
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
    NSString *key = [specifier propertyForKey:@"key"];
    id fallback = [specifier propertyForKey:@"default"];
    if (!key) return fallback;

    CFPreferencesAppSynchronize((__bridge CFStringRef)LKWPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)LKWPrefsDomain);
    return value ? CFBridgingRelease(value) : fallback;
}

- (NSString *)currentAnimationColorHex {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LKWPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("animationColor"),
                                                        (__bridge CFStringRef)LKWPrefsDomain);
    id object = value ? CFBridgingRelease(value) : nil;
    return [object isKindOfClass:[NSString class]] ? object : @"#FFFFFF";
}

- (void)postPreferencesChanged {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LKWPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)LKWPrefsChanged,
                                         NULL,
                                         NULL,
                                         true);
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;

    if ([key isEqualToString:@"xOffset"] || [key isEqualToString:@"yOffset"]) {
        double number = [value doubleValue];
        if (number < -300.0) number = -300.0;
        if (number > 300.0) number = 300.0;
        value = @(number);
    } else if ([key isEqualToString:@"glyphScale"]) {
        double number = [value doubleValue];
        if (number < 0.25) number = 0.25;
        if (number > 2.0) number = 2.0;
        value = @(number);
    }

    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)LKWPrefsDomain);
    [self postPreferencesChanged];
}

- (void)openColorPicker {
    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.delegate = self;
    picker.selectedColor = LKWColorFromHexString([self currentAnimationColorHex]);
    if ([picker respondsToSelector:@selector(setSupportsAlpha:)]) {
        picker.supportsAlpha = NO;
    }
    picker.title = @"Animation Color";
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)openColorPicker:(id)sender {
    [self openColorPicker];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    NSString *hex = LKWHexStringFromColor(viewController.selectedColor ?: UIColor.whiteColor);
    CFPreferencesSetAppValue(CFSTR("animationColor"),
                             (__bridge CFPropertyListRef)hex,
                             (__bridge CFStringRef)LKWPrefsDomain);
    [self postPreferencesChanged];
}

- (void)resetAnimationColor {
    CFPreferencesSetAppValue(CFSTR("animationColor"),
                             (__bridge CFPropertyListRef)@"#FFFFFF",
                             (__bridge CFStringRef)LKWPrefsDomain);
    [self postPreferencesChanged];
}

- (void)resetAnimationColor:(id)sender {
    [self resetAnimationColor];
}

- (void)resetGeometry {
    CFPreferencesSetAppValue(CFSTR("xOffset"), (__bridge CFPropertyListRef)@0.0, (__bridge CFStringRef)LKWPrefsDomain);
    CFPreferencesSetAppValue(CFSTR("yOffset"), (__bridge CFPropertyListRef)@0.0, (__bridge CFStringRef)LKWPrefsDomain);
    CFPreferencesSetAppValue(CFSTR("glyphScale"), (__bridge CFPropertyListRef)@1.0, (__bridge CFStringRef)LKWPrefsDomain);
    [self postPreferencesChanged];
    [self reloadSpecifiers];
}

- (void)resetGeometry:(id)sender {
    [self resetGeometry];
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
