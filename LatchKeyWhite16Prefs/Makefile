ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = Preferences

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LatchKeyWhite16Prefs
LatchKeyWhite16Prefs_FILES = LKWRootListController.m
LatchKeyWhite16Prefs_FRAMEWORKS = Foundation CoreFoundation UIKit
LatchKeyWhite16Prefs_PRIVATE_FRAMEWORKS = Preferences
LatchKeyWhite16Prefs_INSTALL_PATH = /Library/PreferenceBundles
LatchKeyWhite16Prefs_INFOPLIST_FILE = Info.plist
LatchKeyWhite16Prefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
