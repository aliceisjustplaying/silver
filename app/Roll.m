#import "Roll.h"
#import "Log.h"
#include <dlfcn.h>

enum { kThumbWidth = 150, kThumbHeight = 200 };

// Camera JPEGs are landscape (1600x1200); a quarter turn clockwise makes them upright
// (checked by comparing a photo with the live view).

// ImageIO is a private framework on iPhone OS 3.1.3, so its encoder is looked up at runtime.
typedef void *CGImageDestinationRef;
static CGImageDestinationRef (*pDestCreate)(CFURLRef, CFStringRef, size_t, CFDictionaryRef);
static void (*pDestAdd)(CGImageDestinationRef, CGImageRef, CFDictionaryRef);
static bool (*pDestFinalize)(CGImageDestinationRef);
static CFStringRef kQuality;

static BOOL loadImageIO(void) {
    if (pDestCreate) return YES;
    void *h = dlopen("/System/Library/PrivateFrameworks/ImageIO.framework/ImageIO", RTLD_NOW);
    if (!h) h = dlopen("/System/Library/Frameworks/ImageIO.framework/ImageIO", RTLD_NOW);
    if (!h) return NO;
    *(void **)&pDestAdd = dlsym(h, "CGImageDestinationAddImage");
    *(void **)&pDestFinalize = dlsym(h, "CGImageDestinationFinalize");
    CFStringRef *q = dlsym(h, "kCGImageDestinationLossyCompressionQuality");
    kQuality = q ? *q : NULL;
    *(void **)&pDestCreate = dlsym(h, "CGImageDestinationCreateWithURL");
    return pDestCreate && pDestAdd && pDestFinalize && kQuality;
}

static BOOL writeJPEG(CGImageRef img, NSString *path, float quality) {
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)path, kCFURLPOSIXPathStyle, false);
    CGImageDestinationRef d = pDestCreate(url, CFSTR("public.jpeg"), 1, NULL);
    CFRelease(url);
    if (!d) return NO;
    CFNumberRef q = CFNumberCreate(NULL, kCFNumberFloatType, &quality);
    CFDictionaryRef props = CFDictionaryCreate(NULL, (const void **)&kQuality, (const void **)&q, 1,
                                               &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    pDestAdd(d, img, props);
    BOOL ok = pDestFinalize(d);
    CFRelease(props); CFRelease(q); CFRelease(d);
    return ok;
}

// Draws img rotated by quarter turns into a new 8-bit gray context of the rotated size.
// iPhone OS 3 can't allocate bitmap context memory itself (NULL data needs iOS 4), so the
// caller frees CGBitmapContextGetData(ctx) after releasing the context.
static CGContextRef grayContext(CGImageRef img, int turns, size_t outW, size_t outH) {
    size_t rowBytes = (outW + 15) & ~15;
    void *data = calloc(rowBytes, outH);
    if (!data) return NULL;
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(data, outW, outH, 8, rowBytes, gray, kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!ctx) { free(data); return NULL; }
    CGContextSetInterpolationQuality(ctx, kCGInterpolationDefault);
    CGFloat w = outW, h = outH;
    CGContextTranslateCTM(ctx, w / 2, h / 2);
    CGContextRotateCTM(ctx, turns * M_PI_2);
    BOOL swap = turns & 1;
    CGFloat dw = swap ? h : w, dh = swap ? w : h;
    CGContextDrawImage(ctx, CGRectMake(-dw / 2, -dh / 2, dw, dh), img);
    return ctx;
}

@implementation Roll

+ (NSString *)directory {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Silver"];
    [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByAppendingPathComponent:@"thumbs"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

+ (NSArray *)photoNames {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self directory] error:NULL])
        if ([f hasSuffix:@".jpg"]) [names addObject:[f stringByDeletingPathExtension]];
    [names sortUsingSelector:@selector(compare:)];
    return [[names reverseObjectEnumerator] allObjects];
}

+ (NSString *)pathForPhoto:(NSString *)name {
    return [[[self directory] stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"jpg"];
}

+ (NSString *)pathForThumb:(NSString *)name {
    return [[[[self directory] stringByAppendingPathComponent:@"thumbs"] stringByAppendingPathComponent:name]
        stringByAppendingPathExtension:@"jpg"];
}

+ (void)develop:(NSData *)jpeg stock:(const FilmStock *)stock previewMean:(float)previewMean target:(id)target action:(SEL)action {
    NSDictionary *job = [NSDictionary dictionaryWithObjectsAndKeys:jpeg, @"jpeg",
        [NSValue valueWithPointer:stock], @"stock", [NSNumber numberWithFloat:previewMean], @"previewMean",
        target, @"target", NSStringFromSelector(action), @"action", nil];
    [NSThread detachNewThreadSelector:@selector(developJob:) toTarget:self withObject:job];
}

// Same luma weights as the live view (gray.s): Y = (29 B + 150 G + 77 R) >> 8.
static inline int luma(uint32_t p) { return (29 * (p & 0xff) + 150 * ((p >> 8) & 0xff) + 77 * ((p >> 16) & 0xff)) >> 8; }

// BGRA src (sw x sh) -> 8-bit gray dst (sh x sw), rotated a quarter turn clockwise:
// dst[y][x] = src[sh - 1 - x][y]. Tiled so both sides stay in cache.
static void lumaRotateCW(const uint32_t *src, int sw, int sh, uint8_t *dst, int dstRowBytes, const uint8_t table[256]) {
    enum { T = 16 };
    for (int y0 = 0; y0 < sw; y0 += T)
        for (int x0 = 0; x0 < sh; x0 += T)
            for (int y = y0; y < y0 + T && y < sw; y++) {
                uint8_t *d = dst + y * dstRowBytes;
                for (int x = x0; x < x0 + T && x < sh; x++) d[x] = table[luma(src[(sh - 1 - x) * sw + y])];
            }
}

+ (void)developJob:(NSDictionary *)job {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSString *name = nil;
    double t0 = NowMs();
    const FilmStock *stock = [[job objectForKey:@"stock"] pointerValue];
    float previewMean = [[job objectForKey:@"previewMean"] floatValue];
    CGDataProviderRef dp = CGDataProviderCreateWithCFData((CFDataRef)[job objectForKey:@"jpeg"]);
    CGImageRef src = CGImageCreateWithJPEGDataProvider(dp, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(dp);
    size_t sw = src ? CGImageGetWidth(src) : 0, sh = src ? CGImageGetHeight(src) : 0;
    uint32_t *rgb = src ? malloc(sw * sh * 4) : NULL;
    if (rgb && loadImageIO()) {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef dc = CGBitmapContextCreate(rgb, sw, sh, 8, sw * 4, cs, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(cs);
        CGContextDrawImage(dc, CGRectMake(0, 0, sw, sh), src);
        CGContextRelease(dc);
        double t1 = NowMs();

        // Match the photo's mean brightness to the live view's.
        uint32_t sum = 0, n = 0;
        for (size_t i = 0; i < sw * sh; i += 97, n++) sum += luma(rgb[i]);
        float photoMean = (float)sum / n;
        float gain = photoMean > 1 && previewMean > 1 ? previewMean / photoMean : 1;
        if (gain < 0.5f) gain = 0.5f;
        if (gain > 3.0f) gain = 3.0f;
        uint8_t table[256];
        for (int i = 0; i < 256; i++) { int v = (int)(i * gain + 0.5f); table[i] = v > 255 ? 255 : v; }

        size_t w = sh, h = sw, rowBytes = (w + 15) & ~15;
        uint8_t *gray = calloc(rowBytes, h);
        lumaRotateCW(rgb, sw, sh, gray, rowBytes, table);
        free(rgb); rgb = NULL;
        double t2 = NowMs();
        FilmDevelop(stock, gray, w, h, rowBytes, (uint32_t)(t0 * 1000));
        double t3 = NowMs();

        CGColorSpaceRef gs = CGColorSpaceCreateDeviceGray();
        CGContextRef ctx = CGBitmapContextCreate(gray, w, h, 8, rowBytes, gs, kCGImageAlphaNone);
        CGColorSpaceRelease(gs);
        CGImageRef out = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx); free(gray);
        NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
        [fmt setDateFormat:@"yyyyMMdd-HHmmss"];
        NSString *nm = [@"SLV-" stringByAppendingString:[fmt stringFromDate:[NSDate date]]];
        BOOL ok = writeJPEG(out, [self pathForPhoto:nm], 0.9f);
        double t4 = NowMs();
        CGContextRef tc = grayContext(out, 0, kThumbWidth, kThumbHeight);
        if (tc) {
            CGImageRef thumb = CGBitmapContextCreateImage(tc);
            void *td = CGBitmapContextGetData(tc);
            ok = ok && writeJPEG(thumb, [self pathForThumb:nm], 0.8f);
            CGImageRelease(thumb); CGContextRelease(tc); free(td);
        }
        CGImageRelease(out);
        if (ok) name = nm;
        Log(@"developed %@ %zux%zu: preview mean %.1f, photo mean %.1f, gain %.2f; decode %.0f ms, luma+rotate %.0f ms, "
            "grain %.0f ms, encode %.0f ms, total %.0f ms", nm, w, h, previewMean, photoMean, gain,
            t1 - t0, t2 - t1, t3 - t2, t4 - t3, NowMs() - t0);
    } else {
        Log(@"develop failed: decode %p, ImageIO %d", src, loadImageIO());
    }
    free(rgb);
    if (src) CGImageRelease(src);
    [[job objectForKey:@"target"] performSelectorOnMainThread:NSSelectorFromString([job objectForKey:@"action"])
                                                   withObject:name waitUntilDone:NO];
    [pool release];
}

@end
