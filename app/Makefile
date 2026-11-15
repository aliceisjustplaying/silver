# Builds on the Snow Leopard VM with Xcode 3.2.6 (see docs/build-vm.md).
DEV = /Developer/Platforms/iPhoneOS.platform/Developer
SDK = $(DEV)/SDKs/iPhoneOS4.3.sdk
CC  = $(DEV)/usr/bin/gcc-4.2
CFLAGS = -arch armv6 -isysroot $(SDK) -miphoneos-version-min=3.1 -mno-thumb -O2 -std=gnu99 -Wall -Ivendor
LIBS = -framework IOKit -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore
SRC = main.m Viewer.m Camera.m Roll.m ShareServer.m Views.m Private.m Log.m Film.c gray.s vendor/qrcodegen.c

Silver.app: $(SRC) *.h Info.plist Icon.png
	mkdir -p $@
	$(CC) $(CFLAGS) -o $@/Silver $(SRC) $(LIBS)
	cp Info.plist Icon.png $@/
	printf 'APPL????' > $@/PkgInfo

clean:
	rm -rf Silver.app
