// CamProbe: first device test of the private Camera.framework preview API
// on iPhone OS 3.1.3 (see docs/private-camera-re.md). Shows the live frames,
// and logs frame rate and per-frame read cost to /tmp/camprobe.log.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <mach/mach_time.h>

typedef void *CameraDeviceRef;
typedef void *CoreSurfaceBufferRef;
typedef void (*ClientCB)(CameraDeviceRef, int, CoreSurfaceBufferRef, void *);

static int (*pCameraDeviceCreate)(CFAllocatorRef, void *, CameraDeviceRef *);
static void (*pCameraDeviceSetClient)(CameraDeviceRef, ClientCB, void *);
static void (*pCameraDeviceScheduleWithRunLoop)(CameraDeviceRef, CFRunLoopRef, CFStringRef);
static int (*pCameraDeviceStartPreview)(CameraDeviceRef);
static int (*pCameraDeviceRecycleSurface)(CameraDeviceRef, CoreSurfaceBufferRef);
static int (*pLock)(CoreSurfaceBufferRef, unsigned);
static int (*pUnlock)(CoreSurfaceBufferRef, unsigned);
static void *(*pBase)(CoreSurfaceBufferRef);
static size_t (*pRowBytes)(CoreSurfaceBufferRef);
static size_t (*pWidth)(CoreSurfaceBufferRef);
static size_t (*pHeight)(CoreSurfaceBufferRef);
static unsigned (*pFormat)(CoreSurfaceBufferRef);

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

@interface Probe : NSObject <UIApplicationDelegate> {
@public
    UIWindow *window; CALayer *preview; UILabel *label;
    CameraDeviceRef cam; uint8_t *copy; size_t copySize;
    int frames; double windowStart, copyMsTotal; int framesTotal;
}
@end

static void onCamera(CameraDeviceRef dev, int event, CoreSurfaceBufferRef s, void *refcon) {
    Probe *p = (Probe *)refcon;
    if (event != 8 || !s) { plog(@"event %d surface %p", event, s); return; }
    if (pLock(s, 3) == 0) {
        size_t w = pWidth(s), h = pHeight(s), rb = pRowBytes(s);
        if (p->framesTotal == 0)
            plog(@"first frame: %zux%zu rowBytes %zu format %08x", w, h, rb, pFormat ? pFormat(s) : 0);
        if (p->copySize != rb * h) { free(p->copy); p->copySize = rb * h; p->copy = malloc(p->copySize); }
        double t0 = nowMs();
        memcpy(p->copy, pBase(s), p->copySize);   // measures CPU read speed of camera memory
        p->copyMsTotal += nowMs() - t0;
        pUnlock(s, 3);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, p->copy, p->copySize, NULL);
        CGImageRef img = CGImageCreate(w, h, 8, 32, rb, cs,
            kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, dp, NULL, false, kCGRenderingIntentDefault);
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        p->preview.contents = (id)img;
        [CATransaction commit];
        CGImageRelease(img); CGDataProviderRelease(dp); CGColorSpaceRelease(cs);
    }
    pCameraDeviceRecycleSurface(dev, s);
    p->frames++; p->framesTotal++;
    double t = nowMs();
    if (t - p->windowStart >= 1000) {
        double fps = p->frames * 1000.0 / (t - p->windowStart);
        double copyMs = p->copyMsTotal / p->frames;
        plog(@"%.1f fps, memcpy %.2f ms/frame", fps, copyMs);
        p->label.text = [NSString stringWithFormat:@"%.1f fps  copy %.1f ms", fps, copyMs];
        p->frames = 0; p->copyMsTotal = 0; p->windowStart = t;
    }
}

#define SYM(h, var, name) do { *(void **)&var = dlsym(h, name); if (!var) { plog(@"missing %s", name); return NO; } } while (0)

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
    SYM(cs, pLock, "CoreSurfaceBufferLock");
    SYM(cs, pUnlock, "CoreSurfaceBufferUnlock");
    SYM(cs, pBase, "CoreSurfaceBufferGetBaseAddress");
    SYM(cs, pRowBytes, "CoreSurfaceBufferGetBytesPerRow");
    SYM(cs, pWidth, "CoreSurfaceBufferGetWidth");
    SYM(cs, pHeight, "CoreSurfaceBufferGetHeight");
    *(void **)&pFormat = dlsym(cs, "CoreSurfaceBufferGetPixelFormatType");
    return YES;
}

- (void)applicationDidFinishLaunching:(UIApplication *)app {
    logf_ = fopen("/tmp/camprobe.log", "w");
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
    plog(@"CameraDeviceCreate -> 0x%08x dev %p", err, cam);
    if (err || !cam) { label.text = [NSString stringWithFormat:@"create failed 0x%08x", err]; return; }
    pCameraDeviceSetClient(cam, onCamera, self);
    pCameraDeviceScheduleWithRunLoop(cam, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    windowStart = nowMs();
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
