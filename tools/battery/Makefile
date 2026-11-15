DEV = /Developer/Platforms/iPhoneOS.platform/Developer
SDK = $(DEV)/SDKs/iPhoneOS4.3.sdk
battery: battery.c
	$(DEV)/usr/bin/gcc-4.2 -arch armv6 -isysroot $(SDK) -miphoneos-version-min=3.1 -std=gnu99 -O2 -o $@ battery.c -framework CoreFoundation -framework IOKit
