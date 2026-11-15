#import "Private.h"
#include <dlfcn.h>
#import "Log.h"

int (*CameraDeviceCreate)(CFAllocatorRef, void *, CameraDeviceRef *);
void (*CameraDeviceSetClient)(CameraDeviceRef, CameraClientCB, void *);
void (*CameraDeviceSetCaptureCallback)(CameraDeviceRef, CameraPhotoCB, void *);
void (*CameraDeviceScheduleWithRunLoop)(CameraDeviceRef, CFRunLoopRef, CFStringRef);
int (*CameraDeviceStartPreview)(CameraDeviceRef);
int (*CameraDeviceStopPreview)(CameraDeviceRef);
int (*CameraDeviceRecycleSurface)(CameraDeviceRef, CSBuf);
int (*CameraDeviceTakePhoto)(CameraDeviceRef);
CSBuf (*CoreSurfaceBufferCreate)(CFDictionaryRef);
int (*CoreSurfaceBufferLock)(CSBuf, unsigned);
int (*CoreSurfaceBufferUnlock)(CSBuf, unsigned);
void *(*CoreSurfaceBufferGetBaseAddress)(CSBuf);
CFStringRef kCoreSurfaceBufferWidth, kCoreSurfaceBufferHeight, kCoreSurfaceBufferPixelFormat,
    kCoreSurfaceBufferBytesPerElement, kCoreSurfaceBufferBytesPerRow, kCoreSurfaceBufferAllocSize,
    kCoreSurfaceBufferMemoryRegion;

// The iOS SDK ships IOKit.framework without headers.
extern kern_return_t IOConnectCallScalarMethod(mach_port_t, uint32_t, const uint64_t *, uint32_t, uint64_t *, uint32_t *);

int SensorWrite(CameraDeviceRef dev, uint32_t var, int bits, uint64_t value) {
    uint64_t in[4] = {var, bits, value, bits == 16 ? 0xffff : 0xff};
    return IOConnectCallScalarMethod(*(mach_port_t *)((char *)dev + 0xac), 4, in, 4, NULL, NULL);
}
int SensorRead(CameraDeviceRef dev, uint32_t var, int bits, uint64_t *value) {
    uint64_t in[2] = {var, bits}; uint32_t n = 1;
    return IOConnectCallScalarMethod(*(mach_port_t *)((char *)dev + 0xac), 3, in, 2, value, &n);
}

#define SYM(h, var, name) do { *(void **)&var = dlsym(h, name); if (!var) { Log(@"missing %s", name); return -1; } } while (0)
#define KEY(h, var, name) do { CFStringRef *k_ = dlsym(h, name); if (!k_) { Log(@"missing %s", name); return -1; } var = *k_; } while (0)

int PrivateLoad(void) {
    void *c = dlopen("/System/Library/PrivateFrameworks/Camera.framework/Camera", RTLD_NOW);
    void *cs = dlopen("/System/Library/PrivateFrameworks/CoreSurface.framework/CoreSurface", RTLD_NOW);
    if (!c || !cs) { Log(@"dlopen failed: %s", dlerror()); return -1; }
    SYM(c, CameraDeviceCreate, "CameraDeviceCreate");
    SYM(c, CameraDeviceSetClient, "CameraDeviceSetClient");
    SYM(c, CameraDeviceSetCaptureCallback, "CameraDeviceSetCaptureCallback");
    SYM(c, CameraDeviceScheduleWithRunLoop, "CameraDeviceScheduleWithRunLoop");
    SYM(c, CameraDeviceStartPreview, "CameraDeviceStartPreview");
    SYM(c, CameraDeviceStopPreview, "CameraDeviceStopPreview");
    SYM(c, CameraDeviceRecycleSurface, "CameraDeviceRecycleSurface");
    SYM(c, CameraDeviceTakePhoto, "CameraDeviceTakePhoto");
    SYM(cs, CoreSurfaceBufferCreate, "CoreSurfaceBufferCreate");
    SYM(cs, CoreSurfaceBufferLock, "CoreSurfaceBufferLock");
    SYM(cs, CoreSurfaceBufferUnlock, "CoreSurfaceBufferUnlock");
    SYM(cs, CoreSurfaceBufferGetBaseAddress, "CoreSurfaceBufferGetBaseAddress");
    KEY(cs, kCoreSurfaceBufferWidth, "kCoreSurfaceBufferWidth");
    KEY(cs, kCoreSurfaceBufferHeight, "kCoreSurfaceBufferHeight");
    KEY(cs, kCoreSurfaceBufferPixelFormat, "kCoreSurfaceBufferPixelFormat");
    KEY(cs, kCoreSurfaceBufferBytesPerElement, "kCoreSurfaceBufferBytesPerElement");
    KEY(cs, kCoreSurfaceBufferBytesPerRow, "kCoreSurfaceBufferBytesPerRow");
    KEY(cs, kCoreSurfaceBufferAllocSize, "kCoreSurfaceBufferAllocSize");
    KEY(cs, kCoreSurfaceBufferMemoryRegion, "kCoreSurfaceBufferMemoryRegion");
    return 0;
}
