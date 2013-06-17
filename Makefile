ARCHS = armv7
ADDITIONAL_OBJCCFLAGS = -fvisibility=hidden

TWEAK_NAME = DoubleTap
DoubleTap_FILES = DoubleTap.xm
DoubleTap_FRAMEWORKS = CoreFoundation Foundation CoreGraphics UIKit
DoubleTap_PRIVATE_FRAMEWORKS = Celestial

include theos/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 backboardd"