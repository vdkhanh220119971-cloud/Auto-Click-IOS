DEBUG = 0
FINALPACKAGE = 1

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoClicker

# Biên dịch cùng lúc Tweak.x và GCDAsyncSocket.m
AutoClicker_FILES = Tweak.x GCDAsyncSocket.m
AutoClicker_FRAMEWORKS = UIKit CoreGraphics CFNetwork IOKit
AutoClicker_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-error

include $(THEOS_MAKE_PATH)/tweak.mk
