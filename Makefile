ARCHS = arm64e
TARGET = iphone:clang:16.0:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SMSReader
SMSReader_FILES = Tweak.xm
SMSReader_CFLAGS = -fobjc-arc
SMSReader_LDFLAGS = -lsqlite3
SMSReader_FRAMEWORKS = AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"