ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LatchKeyWhite16
LatchKeyWhite16_FILES = Tweak.xm
LatchKeyWhite16_CFLAGS = -fobjc-arc
LatchKeyWhite16_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
