TARGET = iphone:clang:latest:16.0
# INSTALL_TARGET_PROCESSES = OBD
# THEOS_PACKAGE_SCHEME = roothide

PACKAGE_FORMAT = ipa
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = OBD

OBD_FILES = $(shell find Src -name '*.swift' | grep -v '/Package.swift$$')
OBD_FRAMEWORKS = UIKit SwiftUI Charts Network
OBD_RESOURCE_DIRS = Resources

# $(wildcard Src/App/*.swift) $(wildcard Src/Models/*.swift) $(wildcard Src/Networking/*.swift) $(wildcard Src/Services/*.swift) $(wildcard Src/Utilities/*.swift) $(wildcard Src/ViewModels/*.swift) $(wildcard Src/Views/*.swift)

include $(THEOS_MAKE_PATH)/application.mk
