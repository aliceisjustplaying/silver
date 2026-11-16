DEV = /Developer/Platforms/iPhoneOS.platform/Developer
SDK = $(DEV)/SDKs/iPhoneOS4.3.sdk
CC = $(DEV)/usr/bin/gcc-4.2 -arch armv6 -isysroot $(SDK) -miphoneos-version-min=3.1 -dynamiclib -O2
all: RotationLock.dylib Toggle.dylib
RotationLock.dylib: RotationLock.m
	$(CC) -o $@ RotationLock.m -framework Foundation -framework UIKit -lobjc
Toggle.dylib: Toggle.m
	$(CC) -o $@ Toggle.m -framework Foundation
