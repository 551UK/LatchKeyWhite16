#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface BSUICAPackageView : UIView
- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle;
@end

static NSBundle *LKWhiteThemeBundle(void) {
    static NSBundle *themeBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = @"/var/jb/Library/Application Support/LatchKeyWhite16/Face_ID_White.bundle";
        themeBundle = [[NSBundle alloc] initWithPath:path];
    });
    return themeBundle;
}

%hook BSUICAPackageView

- (instancetype)initWithPackageName:(NSString *)packageName inBundle:(NSBundle *)bundle {
    if ([packageName isKindOfClass:[NSString class]] &&
        [packageName rangeOfString:@"lock" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        NSBundle *theme = LKWhiteThemeBundle();
        if (theme) {
            return %orig(@"Face_ID_White", theme);
        }
    }

    return %orig;
}

%end
