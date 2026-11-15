// CamProbe: device benchmarks for the live black-and-white pipeline on
// iPhone OS 3.1.3 (see docs/private-camera-re.md). Runs unattended:
//   1. on the first camera frame, benchmarks reads, the ARMv6 gray kernel and
//      CoreSurfaceAccelerator transfers into several destination surface kinds;
//   2. cycles live display modes for 6 s each, saving a screenshot of each to
//      /tmp/camprobe-mode<N>.png, then stays on the last mode.
// Everything is logged to /tmp/camprobe.log.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <mach/mach_time.h>

typedef void *CameraDeviceRef, *CSBuf, *CSAccel;
typedef void (*ClientCB)(CameraDeviceRef, int, CSBuf, void *);
extern void gray_bgra(const uint32_t *src, uint32_t *dst, int npix, const uint32_t *lut);
extern CGImageRef UIGetScreenImage(void);

static int (*pCameraDeviceCreate)(CFAllocatorRef, void *, CameraDeviceRef *);
static void (*pCameraDeviceSetClient)(CameraDeviceRef, ClientCB, void *);
static void (*pCameraDeviceScheduleWithRunLoop)(CameraDeviceRef, CFRunLoopRef, CFStringRef);
static int (*pCameraDeviceStartPreview)(CameraDeviceRef);
static int (*pCameraDeviceRecycleSurface)(CameraDeviceRef, CSBuf);
static CSBuf (*pCreate)(CFDictionaryRef);
static int (*pLock)(CSBuf, unsigned);
static int (*pUnlock)(CSBuf, unsigned);
static void *(*pBase)(CSBuf);
static size_t (*pRowBytes)(CSBuf);
static size_t (*pWidth)(CSBuf);
static size_t (*pHeight)(CSBuf);
static void (*pFlush)(CSBuf);
static int (*pAccelCreate)(CFAllocatorRef, int, CSAccel *);
static int (*pTransfer)(CSAccel, CSBuf, CSBuf, CFDictionaryRef, void *, void *, void *);
static CFStringRef kW, kH, kFmt, kBPE, kBPR, kAlloc, kRegion, kCache;

#include <mach/mach.h>
// The iOS SDK ships IOKit.framework without headers.
typedef mach_port_t io_connect_t;
extern kern_return_t IOConnectCallScalarMethod(mach_port_t, uint32_t, const uint64_t *, uint32_t, uint64_t *, uint32_t *);
// Sensor "variables" via the IOCameraSensor user client (selectors from H1ISP.mediacapture:
// read = 3 {var, bits} -> value, write = 4 {var, bits, value, mask}). var = driver << 16 | offset.
static io_connect_t sensorConn(CameraDeviceRef dev) { return *(io_connect_t *)((char *)dev + 0xac); }
static int sensorReadBits(CameraDeviceRef dev, uint32_t var, int bits, uint64_t *out) {
    uint64_t in[2] = {var, bits}; uint32_t n = 1;
    return IOConnectCallScalarMethod(sensorConn(dev), 3, in, 2, out, &n);
}
static int sensorWriteBits(CameraDeviceRef dev, uint32_t var, int bits, uint64_t value) {
    uint64_t in[4] = {var, bits, value, bits == 16 ? 0xffff : 0xff};
    return IOConnectCallScalarMethod(sensorConn(dev), 4, in, 4, NULL, NULL);
}
static int sensorRead(CameraDeviceRef dev, uint32_t var, uint64_t *out) {
    uint64_t in[2] = {var, 8}; uint32_t n = 1;
    return IOConnectCallScalarMethod(sensorConn(dev), 3, in, 2, out, &n);
}
static int sensorWrite(CameraDeviceRef dev, uint32_t var, uint64_t value) {
    uint64_t in[4] = {var, 8, value, 0xff};
    return IOConnectCallScalarMethod(sensorConn(dev), 4, in, 4, NULL, NULL);
}

static FILE *logf_;
static void plog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[[NSString alloc] initWithFormat:fmt arguments:ap] autorelease];
    va_end(ap);
    NSLog(@"CamProbe: %@", s);
    if (logf_) { fprintf(logf_, "%s\n", [s UTF8String]); fflush(logf_); }
}
static double nowMs(void) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}
static void setInt(CFMutableDictionaryRef d, CFStringRef k, int v) {
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberSInt32Type, &v);
    CFDictionarySetValue(d, k, n); CFRelease(n);
}
// region: NULL for default memory; cacheMode < 0 to leave unset
static CSBuf makeSurface(int w, int h, uint32_t fmt, int bpe, CFStringRef region, int cacheMode) {
    int bpr = ((w + 15) & ~15) * bpe;
    CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    setInt(d, kW, w); setInt(d, kH, h); setInt(d, kFmt, (int)fmt); setInt(d, kBPE, bpe);
    setInt(d, kBPR, bpr); setInt(d, kAlloc, bpr * ((h + 15) & ~15));
    if (region) CFDictionarySetValue(d, kRegion, region);
    if (cacheMode >= 0) setInt(d, kCache, cacheMode);
    CSBuf b = pCreate(d);
    CFRelease(d);
    return b;
}

static uint32_t lut[256];
static void gray_c(const uint32_t *src, uint32_t *dst, int n) {
    for (int i = 0; i < n; i++) {
        uint32_t p = src[i];
        dst[i] = lut[(29 * (p & 0xff) + 150 * ((p >> 8) & 0xff) + 77 * ((p >> 16) & 0xff)) >> 8];
    }
}

@interface Probe : NSObject <UIApplicationDelegate> {
@public
    UIWindow *window; CALayer *preview; UILabel *label;
    CameraDeviceRef cam; CSAccel accel;
    CSBuf disp[2]; int dispIdx;      // display surfaces (layer contents)
    CSBuf staging;                   // cached BGRA destination for accelerator copies, if usable
    uint32_t *copy;
    int mode, frames; double windowStart, workMs, modeStart; BOOL benched, shot;
    int step; double stepStart; uint64_t lumaSum; int lumaN;
}
- (void)bench:(CSBuf)s;
- (void)sensorSetup;
- (void)experimentAt:(double)t;
- (void)frame:(CSBuf)s;
@end

static void onCamera(CameraDeviceRef dev, int event, CSBuf s, void *refcon) {
    Probe *p = (Probe *)refcon;
    if (event != 8 || !s) { plog(@"event %d", event); return; }
    if (!p->benched) { p->benched = YES; [p sensorSetup]; }
    [p frame:s];
    pCameraDeviceRecycleSurface(dev, s);
}

#define SYM(h, var, name) do { *(void **)&var = dlsym(h, name); if (!var) { plog(@"missing %s", name); return NO; } } while (0)
#define KEY(h, var, name) do { CFStringRef *k_ = dlsym(h, name); if (!k_) { plog(@"missing %s", name); return NO; } var = *k_; } while (0)

@implementation Probe
- (BOOL)loadSymbols {
    void *c = dlopen("/System/Library/PrivateFrameworks/Camera.framework/Camera", RTLD_NOW);
    void *cs = dlopen("/System/Library/PrivateFrameworks/CoreSurface.framework/CoreSurface", RTLD_NOW);
    if (!c || !cs) { plog(@"dlopen failed: %s", dlerror()); return NO; }
    SYM(c, pCameraDeviceCreate, "CameraDeviceCreate");
    SYM(c, pCameraDeviceSetClient, "CameraDeviceSetClient");
    SYM(c, pCameraDeviceScheduleWithRunLoop, "CameraDeviceScheduleWithRunLoop");
    SYM(c, pCameraDeviceStartPreview, "CameraDeviceStartPreview");
    SYM(c, pCameraDeviceRecycleSurface, "CameraDeviceRecycleSurface");
    SYM(cs, pCreate, "CoreSurfaceBufferCreate");
    SYM(cs, pLock, "CoreSurfaceBufferLock");
    SYM(cs, pUnlock, "CoreSurfaceBufferUnlock");
    SYM(cs, pBase, "CoreSurfaceBufferGetBaseAddress");
    SYM(cs, pRowBytes, "CoreSurfaceBufferGetBytesPerRow");
    SYM(cs, pWidth, "CoreSurfaceBufferGetWidth");
    SYM(cs, pHeight, "CoreSurfaceBufferGetHeight");
    SYM(cs, pFlush, "CoreSurfaceBufferFlushProcessorCaches");
    SYM(cs, pAccelCreate, "CoreSurfaceAcceleratorCreate");
    SYM(cs, pTransfer, "CoreSurfaceAcceleratorTransferSurface");
    KEY(cs, kW, "kCoreSurfaceBufferWidth");
    KEY(cs, kH, "kCoreSurfaceBufferHeight");
    KEY(cs, kFmt, "kCoreSurfaceBufferPixelFormat");
    KEY(cs, kBPE, "kCoreSurfaceBufferBytesPerElement");
    KEY(cs, kBPR, "kCoreSurfaceBufferBytesPerRow");
    KEY(cs, kAlloc, "kCoreSurfaceBufferAllocSize");
    KEY(cs, kRegion, "kCoreSurfaceBufferMemoryRegion");
    KEY(cs, kCache, "kCoreSurfaceBufferCacheMode");
    return YES;
}

- (void)bench:(CSBuf)s {
    const int n = 304 * 400, bytes = n * 4;
    uint32_t *a = malloc(bytes), *b = malloc(bytes);
    pLock(s, 3);
    const uint32_t *src = pBase(s);
    double t = nowMs(); memcpy(a, src, bytes); plog(@"bench memcpy camera->malloc: %.2f ms", nowMs() - t);
    t = nowMs(); gray_bgra(src, b, n, lut); plog(@"bench gray_bgra camera->malloc: %.2f ms", nowMs() - t);
    t = nowMs(); gray_bgra(a, b, n, lut); plog(@"bench gray_bgra malloc->malloc: %.2f ms", nowMs() - t);
    t = nowMs(); gray_c(a, a + 0, 0); gray_c(a, b, n); plog(@"bench gray_c malloc->malloc: %.2f ms", nowMs() - t);
    uint32_t *ref = malloc(bytes); gray_c(a, ref, n); gray_bgra(a, b, n, lut);
    int bad = 0; for (int i = 0; i < n; i++) bad += ref[i] != b[i];
    plog(@"gray_bgra vs C mismatches: %d of %d", bad, n);
    pUnlock(s, 3);

    // display surfaces: does a CoreSurface as CALayer contents show up? (see screenshots)
    for (int i = 0; i < 2; i++) disp[i] = makeSurface(304, 400, 'BGRA', 4, CFSTR("PurpleGfxMem"), -1);
    plog(@"display surfaces %p %p", disp[0], disp[1]);
    if (disp[0]) {
        pLock(disp[0], 3);
        t = nowMs(); gray_bgra(a, pBase(disp[0]), n, lut); plog(@"bench gray_bgra malloc->display surface: %.2f ms", nowMs() - t);
        pUnlock(disp[0], 3);
    }

    int err = pAccelCreate(NULL, 0, &accel);
    plog(@"CoreSurfaceAcceleratorCreate -> %d accel %p", err, accel);
    struct { const char *name; uint32_t fmt; int bpe; CFStringRef region; int cache; } cand[] = {
        {"BGRA default", 'BGRA', 4, NULL, -1},
        {"BGRA PurpleGfxMem", 'BGRA', 4, CFSTR("PurpleGfxMem"), -1},
        {"BGRA cache 0x300", 'BGRA', 4, NULL, 0x300},
        {"BGRA PurpleGfxMem cache 0x300", 'BGRA', 4, CFSTR("PurpleGfxMem"), 0x300},
        {"BGRA PurpleEDRAM", 'BGRA', 4, CFSTR("PurpleEDRAM"), -1},
        {"2vuy default", '2vuy', 2, NULL, -1},
        {"yuvs default", 'yuvs', 2, NULL, -1},
        {"L565 default", 'L565', 2, NULL, -1},
        {"565L default", '565L', 2, NULL, -1},
        {"L008 default", 'L008', 1, NULL, -1},
    };
    for (unsigned i = 0; accel && i < sizeof cand / sizeof cand[0]; i++) {
        CSBuf d = makeSurface(304, 400, cand[i].fmt, cand[i].bpe, cand[i].region, cand[i].cache);
        if (!d) { plog(@"[%s] create failed", cand[i].name); continue; }
        t = nowMs();
        int e = pTransfer(accel, s, d, NULL, NULL, NULL, NULL);
        double tx = nowMs() - t;
        if (e) { plog(@"[%s] transfer err 0x%08x (%.2f ms)", cand[i].name, e, tx); CFRelease(d); continue; }
        size_t rb = pRowBytes(d), sz = rb * pHeight(d);
        t = nowMs(); pFlush(d); double fl = nowMs() - t;
        pLock(d, 3);
        const uint8_t *db = pBase(d);
        t = nowMs(); memcpy(a, db, sz); double rd = nowMs() - t;
        double gr = -1; int diff = -1;
        if (cand[i].fmt == 'BGRA') {
            t = nowMs(); gray_bgra((const uint32_t *)db, b, n, lut); gr = nowMs() - t;
            pLock(s, 3); diff = 0;
            const uint32_t *sp = pBase(s), *dp = (const uint32_t *)db;
            for (int k = 0; k < n; k += 997) diff += (sp[k] & 0xffffff) != (dp[k] & 0xffffff);
            pUnlock(s, 3);
        }
        pUnlock(d, 3);
        plog(@"[%s] ok: %zux%zu rowBytes %zu, transfer %.2f ms, flush %.2f ms, read %.2f ms, gray %.2f ms, sampled pixel diffs %d",
             cand[i].name, pWidth(d), pHeight(d), rb, tx, fl, rd, gr, diff);
        if (cand[i].fmt == 'BGRA' && !staging && diff == 0 && rd < 10) { staging = d; plog(@"using [%s] as staging", cand[i].name); }
        else CFRelease(d);
    }
    free(a); free(b); free(ref);
    copy = malloc(bytes);
    modeStart = windowStart = nowMs();
}

- (void)sensorSetup {
    mode = 1; modeStart = windowStart = stepStart = nowMs();
    for (int i = 0; i < 2; i++) disp[i] = makeSurface(304, 400, 'BGRA', 4, CFSTR("PurpleGfxMem"), -1);
    copy = malloc(304 * 400 * 4);
    plog(@"sensor connection 0x%x", sensorConn(cam));
    uint64_t ll = 0, fl = 0; int e1 = sensorReadBits(cam, 0x70025, 16, &ll), e2 = sensorReadBits(cam, 0x70023, 16, &fl);
    plog(@"16-bit reads: line length %llu (0x%x), frame lines %llu (0x%x)", ll, e1, fl, e2);
    NSMutableString *line = [NSMutableString string];
    uint32_t drivers[] = {1, 2, 3, 7};
    for (int di = 0; di < 4; di++) {
        [line setString:[NSString stringWithFormat:@"driver %u:", drivers[di]]];
        for (uint32_t off = 0; off < 0x40; off++) {
            uint64_t v = 0; int e = sensorRead(cam, drivers[di] << 16 | off, &v);
            [line appendFormat:e ? @" --" : @" %02llx", v];
        }
        plog(@"%@", line);
    }
}

// Steps of 5 s each. MT9D112 context A (preview) timing: mode.sensor_frame_lines_A = var 7.0x23,
// mode.sensor_line_length_A = var 7.0x25 (16-bit); ae.maxIndex = var 2.0x0C (8-bit);
// seq.cmd = var 1.0x03 (6 = refresh mode, 5 = refresh).
- (void)experimentAt:(double)t {
    static const struct { int maxIndex, lineLength, frameLines; } plan[] = {
        {-1, -1, -1}, {4, -1, -1}, {4, 1100, -1}, {4, 1000, -1}, {4, 900, -1}, {4, 800, -1},
        {4, 1000, 640}, {18, 1250, 675},
    };
    const int steps = sizeof plan / sizeof plan[0];
    if (step >= steps - 1 || t - stepStart < 5000) return;
    step++; stepStart = t;
    int e = 0;
    if (plan[step].maxIndex >= 0) e |= sensorWriteBits(cam, 0x2000c, 8, plan[step].maxIndex);
    if (plan[step].lineLength >= 0) e |= sensorWriteBits(cam, 0x70025, 16, plan[step].lineLength);
    if (plan[step].frameLines >= 0) e |= sensorWriteBits(cam, 0x70023, 16, plan[step].frameLines);
    e |= sensorWriteBits(cam, 0x10003, 8, 6); usleep(100000);
    e |= sensorWriteBits(cam, 0x10003, 8, 5);
    uint64_t mi = 0, ll = 0, fl = 0;
    sensorReadBits(cam, 0x2000c, 8, &mi); sensorReadBits(cam, 0x70025, 16, &ll); sensorReadBits(cam, 0x70023, 16, &fl);
    plog(@"step %d: errors 0x%x; now maxIndex %llu, line length %llu, frame lines %llu", step, e, mi, ll, fl);
    shot = NO; modeStart = t;
}

- (void)frame:(CSBuf)s {
    double t0 = nowMs();
    const int n = 304 * 400;
    if (mode == 0) {   // color, CGImage from a malloc copy (the first probe's path)
        pLock(s, 3); memcpy(copy, pBase(s), n * 4); pUnlock(s, 3);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, copy, n * 4, NULL);
        CGImageRef img = CGImageCreate(304, 400, 8, 32, 1216, cs, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, dp, NULL, false, kCGRenderingIntentDefault);
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        preview.contents = (id)img;
        [CATransaction commit];
        CGImageRelease(img); CGDataProviderRelease(dp); CGColorSpaceRelease(cs);
    } else {           // gray into a display surface shown directly as layer contents
        CSBuf src = s;
        if (mode == 2 && staging) {
            pTransfer(accel, s, staging, NULL, NULL, NULL, NULL);
            pFlush(staging);
            src = staging;
        }
        CSBuf d = disp[dispIdx]; dispIdx ^= 1;
        pLock(src, 3); pLock(d, 3);
        const uint32_t *gp = pBase(d);
        gray_bgra(pBase(src), (uint32_t *)gp, n, lut);
        for (int k = 0; k < n; k += 61) { lumaSum += gp[k] & 0xff; lumaN++; }
        pUnlock(d, 3); pUnlock(src, 3);
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        preview.contents = (id)d;
        [CATransaction commit];
    }
    workMs += nowMs() - t0;
    frames++;
    double t = nowMs();
    if (t - windowStart >= 1000) {
        plog(@"step %d mode %d: %.1f fps, work %.2f ms/frame, mean luma %d", step, mode, frames * 1000.0 / (t - windowStart), workMs / frames, lumaN ? (int)(lumaSum / lumaN) : -1);
        lumaSum = 0; lumaN = 0;
        label.text = [NSString stringWithFormat:@"mode %d  %.1f fps  %.1f ms", mode, frames * 1000.0 / (t - windowStart), workMs / frames];
        frames = 0; workMs = 0; windowStart = t;
    }
    if (!shot && t - modeStart > 3000) {
        shot = YES;
        CGImageRef img = UIGetScreenImage();
        NSData *png = UIImagePNGRepresentation([UIImage imageWithCGImage:img]);
        [png writeToFile:[NSString stringWithFormat:@"/tmp/camprobe-step%d.png", step] atomically:YES];
        CGImageRelease(img);
        plog(@"saved screenshot for step %d", step);
    }
    [self experimentAt:t];
}

- (void)applicationDidFinishLaunching:(UIApplication *)app {
    logf_ = fopen("/tmp/camprobe.log", "w");
    for (int i = 0; i < 256; i++) lut[i] = 0xff000000u | (uint32_t)i * 0x010101u;
    window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    window.backgroundColor = [UIColor blackColor];
    preview = [[CALayer layer] retain];
    preview.frame = CGRectMake(8, 20, 304, 400);
    [window.layer addSublayer:preview];
    label = [[UILabel alloc] initWithFrame:CGRectMake(0, 430, 320, 30)];
    label.backgroundColor = [UIColor blackColor]; label.textColor = [UIColor whiteColor];
    label.textAlignment = UITextAlignmentCenter; label.text = @"starting";
    [window addSubview:label];
    [window makeKeyAndVisible];

    if (![self loadSymbols]) { label.text = @"symbols missing (see log)"; return; }
    int err = pCameraDeviceCreate(kCFAllocatorDefault, NULL, &cam);
    plog(@"CameraDeviceCreate -> 0x%08x", err);
    if (err || !cam) { label.text = [NSString stringWithFormat:@"create failed 0x%08x", err]; return; }
    pCameraDeviceSetClient(cam, onCamera, self);
    pCameraDeviceScheduleWithRunLoop(cam, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    err = pCameraDeviceStartPreview(cam);
    plog(@"CameraDeviceStartPreview -> 0x%08x", err);
}
@end

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    int r = UIApplicationMain(argc, argv, nil, @"Probe");
    [pool release];
    return r;
}
