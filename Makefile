DEBUG = 0
FINALPACKAGE = 1

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClicker
AutoClicker_FILES = Tweak.x
AutoClicker_FRAMEWORKS = UIKit CoreGraphics IOKit
AutoClicker_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-error -Wno-implicit-function-declaration

include $(THEOS_MAKE_PATH)/tweak.mk
