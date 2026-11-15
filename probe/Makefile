# Builds on the Snow Leopard VM with Xcode 3.2.6.
DEV = /Developer/Platforms/iPhoneOS.platform/Developer
SDK = $(DEV)/SDKs/iPhoneOS4.3.sdk
CC  = $(DEV)/usr/bin/gcc-4.2
CFLAGS = -arch armv6 -isysroot $(SDK) -miphoneos-version-min=3.1 -mno-thumb -O2 -std=gnu99 -Wall
LIBS = -framework IOKit -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore

CamProbe.app: main.m gray.s Info.plist
	mkdir -p $@
	$(CC) $(CFLAGS) -o $@/CamProbe main.m gray.s $(LIBS)
	cp Info.plist $@/Info.plist
	printf 'APPL????' > $@/PkgInfo

clean:
	rm -rf CamProbe.app
