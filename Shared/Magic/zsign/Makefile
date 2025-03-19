# Makefile
    
    TARGET = SystemInfo
    
    include $(THEOS)/makefiles/common.mk
    
    TUSD_FRAMEWORKS = UIKit
    
    ARCHS = iphoneos-arm64
    
    include $(THEOS_MAKE_PATH)/tweak.mk
    
    $(TARGET)_FILES = InfoProvider.m CPUXLib.c
    
    $(TARGET)_PRIVATE_FRAMEWORKS = CoreGraphics
    
    INSTALL_TARGET_PROCESSES = SpringBoard