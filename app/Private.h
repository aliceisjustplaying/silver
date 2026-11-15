// Private iPhone OS 3.1.3 APIs, resolved at runtime with dlsym.
// Evidence for every signature: docs/private-camera-re.md.
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <mach/mach.h>

typedef void *CameraDeviceRef, *CSBuf, *CSAccel;
typedef void (*CameraClientCB)(CameraDeviceRef dev, int event, CSBuf surface, void *refcon);
typedef void (*CameraPhotoCB)(CameraDeviceRef dev, int event, CFDataRef jpeg, CFDictionaryRef props,
                              CGImageRef thumb, void *refcon);

enum {
    kCameraEventPreviewStarted = 1,
    kCameraEventPreviewStopped = 2,
    kCameraEventPhotoStarting = 4,
    kCameraEventPreviewFrame = 8,
    kCameraEventPhoto = 0x20,
};

extern int (*CameraDeviceCreate)(CFAllocatorRef, void *, CameraDeviceRef *);
extern void (*CameraDeviceSetClient)(CameraDeviceRef, CameraClientCB, void *);
extern void (*CameraDeviceSetCaptureCallback)(CameraDeviceRef, CameraPhotoCB, void *);
extern void (*CameraDeviceScheduleWithRunLoop)(CameraDeviceRef, CFRunLoopRef, CFStringRef);
extern int (*CameraDeviceStartPreview)(CameraDeviceRef);
extern int (*CameraDeviceStopPreview)(CameraDeviceRef);
extern int (*CameraDeviceRecycleSurface)(CameraDeviceRef, CSBuf);
extern int (*CameraDeviceTakePhoto)(CameraDeviceRef);

extern CSBuf (*CoreSurfaceBufferCreate)(CFDictionaryRef);
extern int (*CoreSurfaceBufferLock)(CSBuf, unsigned);
extern int (*CoreSurfaceBufferUnlock)(CSBuf, unsigned);
extern void *(*CoreSurfaceBufferGetBaseAddress)(CSBuf);
extern CFStringRef kCoreSurfaceBufferWidth, kCoreSurfaceBufferHeight, kCoreSurfaceBufferPixelFormat,
    kCoreSurfaceBufferBytesPerElement, kCoreSurfaceBufferBytesPerRow, kCoreSurfaceBufferAllocSize,
    kCoreSurfaceBufferMemoryRegion;

// MT9D112 sensor variables through the IOCameraSensor connection at dev + 0xac.
int SensorWrite(CameraDeviceRef dev, uint32_t var, int bits, uint64_t value);
int SensorRead(CameraDeviceRef dev, uint32_t var, int bits, uint64_t *value);

extern CGImageRef UIGetScreenImage(void);

int PrivateLoad(void);   // 0 on success
