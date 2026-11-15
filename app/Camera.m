#import "Camera.h"
#import "Private.h"
#import "Log.h"

extern void gray_bgra(const uint32_t *src, uint32_t *dst, int npix, const uint32_t *lut);

enum { kWidth = 304, kHeight = 400 };

// Preview auto-exposure limit (MT9D112 ae.maxIndex, var 2.0x0C). Apple's default is 0x12,
// which lets frames lengthen to about 5 fps in dim light; 4 keeps the preview near 15 fps.
enum { kPreviewMaxIndex = 4 };

static CSBuf makeDisplaySurface(void) {
    int bpr = kWidth * 4;
    CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int vals[] = {kWidth, kHeight, 'BGRA', 4, bpr, bpr * kHeight};
    CFStringRef keys[] = {kCoreSurfaceBufferWidth, kCoreSurfaceBufferHeight, kCoreSurfaceBufferPixelFormat,
                          kCoreSurfaceBufferBytesPerElement, kCoreSurfaceBufferBytesPerRow, kCoreSurfaceBufferAllocSize};
    for (int i = 0; i < 6; i++) {
        CFNumberRef n = CFNumberCreate(NULL, kCFNumberSInt32Type, &vals[i]);
        CFDictionarySetValue(d, keys[i], n); CFRelease(n);
    }
    CFDictionarySetValue(d, kCoreSurfaceBufferMemoryRegion, CFSTR("PurpleGfxMem"));
    CSBuf b = CoreSurfaceBufferCreate(d);
    CFRelease(d);
    return b;
}

@interface Camera (Callbacks)
- (void)frame:(CSBuf)s;
- (void)photo:(CFDataRef)jpeg;
@end

static void clientCallback(CameraDeviceRef dev, int event, CSBuf s, void *refcon) {
    Camera *c = (Camera *)refcon;
    if (event == kCameraEventPreviewFrame && s) {
        [c frame:s];
        CameraDeviceRecycleSurface(dev, s);
    } else {
        Log(@"camera event %d", event);
    }
}

static void photoCallback(CameraDeviceRef dev, int event, CFDataRef jpeg, CFDictionaryRef props, CGImageRef thumb, void *refcon) {
    Log(@"photo event 0x%x jpeg %p (%ld bytes)", event, jpeg, jpeg ? (long)CFDataGetLength(jpeg) : 0L);
    [(Camera *)refcon photo:jpeg];
}

@implementation Camera

- (id)initWithLayer:(CALayer *)l delegate:(id<CameraDelegate>)d {
    if ((self = [super init])) { layer = [l retain]; delegate = d; }
    return self;
}

- (BOOL)start {
    if (PrivateLoad()) { [delegate cameraFailed:self reason:@"camera frameworks missing"]; return NO; }
    disp[0] = makeDisplaySurface(); disp[1] = makeDisplaySurface();
    if (!disp[0] || !disp[1]) { [delegate cameraFailed:self reason:@"no display surfaces"]; return NO; }
    int err = CameraDeviceCreate(kCFAllocatorDefault, NULL, &dev);
    if (err || !dev) {
        [delegate cameraFailed:self reason:[NSString stringWithFormat:@"camera unavailable (0x%08x)", err]];
        return NO;
    }
    CameraDeviceSetClient(dev, clientCallback, self);
    CameraDeviceSetCaptureCallback(dev, photoCallback, self);
    CameraDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    SensorWrite(dev, 0x2000c, 8, kPreviewMaxIndex);
    SensorWrite(dev, 0x10003, 8, 5);                       // seq.cmd = refresh
    err = CameraDeviceStartPreview(dev);
    Log(@"camera started (0x%08x)", err);
    windowStart = NowMs();
    return err == 0;
}

- (void)setPreviewTable:(const uint32_t *)t { memcpy(table, t, sizeof table); }

- (void)frame:(CSBuf)s {
    double t0 = NowMs();
    CSBuf d = disp[dispIndex]; dispIndex ^= 1;
    CoreSurfaceBufferLock(s, 3); CoreSurfaceBufferLock(d, 3);
    const uint32_t *src = CoreSurfaceBufferGetBaseAddress(s);
    gray_bgra(src, CoreSurfaceBufferGetBaseAddress(d), kWidth * kHeight, table);
    uint32_t sum = 0, n = 0;                               // sampled raw luma, for matching photos
    for (int i = 0; i < kWidth * kHeight; i += 61, n++) {
        uint32_t p = src[i];
        sum += (29 * (p & 0xff) + 150 * ((p >> 8) & 0xff) + 77 * ((p >> 16) & 0xff)) >> 8;
    }
    previewMean = (float)sum / n;
    CoreSurfaceBufferUnlock(d, 3); CoreSurfaceBufferUnlock(s, 3);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    layer.contents = (id)d;
    [CATransaction commit];
    double t1 = NowMs();
    workMs += t1 - t0; frames++;
    if (t1 - windowStart >= 2000) {
        fps = frames * 1000.0f / (t1 - windowStart); msPerFrame = workMs / frames;
        Log(@"preview %.1f fps, %.2f ms/frame", fps, msPerFrame);
        frames = 0; workMs = 0; windowStart = t1;
    }
}

- (BOOL)takePhoto {
    if (photoPending) return NO;
    photoPending = YES;
    int err = CameraDeviceTakePhoto(dev);
    Log(@"take photo (0x%08x)", err);
    if (err) photoPending = NO;
    return err == 0;
}

- (void)photo:(CFDataRef)jpeg {
    photoPending = NO;
    [delegate camera:self tookPhoto:jpeg ? [NSData dataWithData:(NSData *)jpeg] : nil];
}

@end
