DEV = /Developer/Platforms/iPhoneOS.platform/Developer
SDK = $(DEV)/SDKs/iPhoneOS4.3.sdk
NoSIMAlert.dylib: NoSIMAlert.m
	$(DEV)/usr/bin/gcc-4.2 -arch armv6 -isysroot $(SDK) -miphoneos-version-min=3.1 -dynamiclib -O2 -o $@ NoSIMAlert.m -framework Foundation -lobjc
