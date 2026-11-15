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
        Log(@"camera event %d; %@", event, [c sensorSummary]);
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

static void writePNG(const uint32_t *bgra, int w, int h, int rowBytes, NSString *path) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, bgra, rowBytes * h, NULL);
    CGImageRef img = CGImageCreate(w, h, 8, 32, rowBytes, cs, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst,
                                   dp, NULL, false, kCGRenderingIntentDefault);
    [UIImagePNGRepresentation([UIImage imageWithCGImage:img]) writeToFile:path atomically:NO];
    CGImageRelease(img); CGDataProviderRelease(dp); CGColorSpaceRelease(cs);
}

- (NSString *)sensorSummary {
    if (!dev) return @"no camera";
    // MT9D112: seq.mode 1.02, seq.state 1.04, ae.maxIndex 2.0C, ae.index 2.0D (8-bit);
    // mode vars (16-bit): 7.03/7.05 preview output size, 7.0F-7.15 preview window (raw values,
    // names not confirmed), 7.23/7.25 frame lines/line length.
    static const struct { uint32_t var; int bits; const char *name; } vars[] = {
        {0x10002, 8, "seq.mode"}, {0x10004, 8, "seq.state"}, {0x2000c, 8, "ae.maxIndex"}, {0x2000d, 8, "ae.index"},
        {0x70003, 16, "outW.A"}, {0x70005, 16, "outH.A"}, {0x7000f, 16, "7.0F"}, {0x70011, 16, "7.11"},
        {0x70013, 16, "7.13"}, {0x70015, 16, "7.15"}, {0x70023, 16, "frameLines.A"}, {0x70025, 16, "lineLength.A"},
    };
    NSMutableString *out = [NSMutableString string];
    for (unsigned i = 0; i < sizeof vars / sizeof vars[0]; i++) {
        uint64_t v = 0; int e = SensorRead(dev, vars[i].var, vars[i].bits, &v);
        [out appendFormat:e ? @"%s=err%x " : @"%s=%llu ", vars[i].name, e ? (uint64_t)e : v];
    }
    char *d = dev;   // Camera.framework's CameraDevice: state at +0xa4, captures in flight at +0xa8
    [out appendFormat:@"state=%d inflight=%d", *(int *)(d + 0xa4), *(int *)(d + 0xa8)];
    return out;
}

- (void)dumpNextFrameTo:(NSString *)dir { [dumpDir release]; dumpDir = [dir copy]; }

- (void)dump:(CSBuf)s display:(CSBuf)d {
    [[NSFileManager defaultManager] createDirectoryAtPath:dumpDir withIntermediateDirectories:YES attributes:nil error:NULL];
    int w = CoreSurfaceBufferGetWidth(s), h = CoreSurfaceBufferGetHeight(s), rb = CoreSurfaceBufferGetBytesPerRow(s);
    CoreSurfaceBufferLock(s, 3);
    writePNG(CoreSurfaceBufferGetBaseAddress(s), w, h, rb, [dumpDir stringByAppendingPathComponent:@"camera.png"]);
    CoreSurfaceBufferUnlock(s, 3);
    CoreSurfaceBufferLock(d, 3);
    writePNG(CoreSurfaceBufferGetBaseAddress(d), kWidth, kHeight, kWidth * 4, [dumpDir stringByAppendingPathComponent:@"display.png"]);
    CoreSurfaceBufferUnlock(d, 3);
    NSMutableString *t = [NSMutableString string];
    [t appendFormat:@"frame surface %p: %dx%d rowBytes %d format %08x\n", s, w, h, rb, CoreSurfaceBufferGetPixelFormatType(s)];
    char *dv = dev;
    [t appendString:@"surfaces (dev+0x58):"];
    for (int i = 0; i < 6; i++) [t appendFormat:@" %p", *(void **)(dv + 0x58 + 4 * i)];
    [t appendString:@"\nfree list (dev+0x70):"];
    for (int i = 0; i < 6; i++) [t appendFormat:@" %p", *(void **)(dv + 0x70 + 4 * i)];
    [t appendFormat:@"\n%@\nfps %.1f, %.2f ms/frame, anomalies %d\n", [self sensorSummary], fps, msPerFrame, anomalies];
    [t writeToFile:[dumpDir stringByAppendingPathComponent:@"camera.txt"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    Log(@"debug dump written to %@", dumpDir);
    [dumpDir release]; dumpDir = nil;
}

- (void)frame:(CSBuf)s {
    double t0 = NowMs();
    if (CoreSurfaceBufferGetWidth(s) != kWidth || CoreSurfaceBufferGetHeight(s) != kHeight ||
        CoreSurfaceBufferGetBytesPerRow(s) != kWidth * 4) {
        if (anomalies++ < 20)
            Log(@"unexpected frame surface %p: %zux%zu rowBytes %zu", s, CoreSurfaceBufferGetWidth(s),
                CoreSurfaceBufferGetHeight(s), CoreSurfaceBufferGetBytesPerRow(s));
        return;
    }
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
    if (dumpDir) [self dump:s display:d];
    double t1 = NowMs();
    workMs += t1 - t0; frames++;
    if (t1 - windowStart >= 2000) {
        fps = frames * 1000.0f / (t1 - windowStart); msPerFrame = workMs / frames;
        Log(@"preview %.1f fps, %.2f ms/frame", fps, msPerFrame);
        frames = 0; workMs = 0; windowStart = t1;
    }
}

- (void)pause {
    if (paused || !dev) return;
    paused = YES;
    Log(@"pause preview (0x%08x)", CameraDeviceStopPreview(dev));
}

// StartPreview fails (0xe00002d5) until the stop has drained the in-flight captures; retry.
- (void)resume {
    if (!paused || !dev) return;
    int err = CameraDeviceStartPreview(dev);
    Log(@"resume preview (0x%08x)", err);
    if (err) [self performSelector:@selector(resume) withObject:nil afterDelay:0.1];
    else paused = NO;
}

- (BOOL)takePhoto {
    if (photoPending || paused) return NO;
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
