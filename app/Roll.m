#import "Roll.h"
#import "Log.h"
#include <dlfcn.h>

enum { kThumbWidth = 150, kThumbHeight = 200 };

// Camera JPEGs are landscape (1600x1200). Rotation that makes them upright, in quarter turns
// counterclockwise, chosen by comparing a photo with the live view.
static int gQuarterTurns = 3;

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

+ (void)develop:(NSData *)jpeg stock:(const FilmStock *)stock target:(id)target action:(SEL)action {
    NSDictionary *job = [NSDictionary dictionaryWithObjectsAndKeys:jpeg, @"jpeg",
        [NSValue valueWithPointer:stock], @"stock", target, @"target",
        NSStringFromSelector(action), @"action", nil];
    [NSThread detachNewThreadSelector:@selector(developJob:) toTarget:self withObject:job];
}

+ (void)developJob:(NSDictionary *)job {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSString *name = nil;
    double t0 = NowMs();
    const FilmStock *stock = [[job objectForKey:@"stock"] pointerValue];
    CGDataProviderRef dp = CGDataProviderCreateWithCFData((CFDataRef)[job objectForKey:@"jpeg"]);
    CGImageRef src = CGImageCreateWithJPEGDataProvider(dp, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(dp);
    if (src && loadImageIO()) {
        size_t sw = CGImageGetWidth(src), sh = CGImageGetHeight(src);
        size_t w = (gQuarterTurns & 1) ? sh : sw, h = (gQuarterTurns & 1) ? sw : sh;
        CGContextRef ctx = grayContext(src, gQuarterTurns, w, h);
        double t1 = NowMs();
        if (ctx) {
            FilmDevelop(stock, CGBitmapContextGetData(ctx), w, h, CGBitmapContextGetBytesPerRow(ctx), (uint32_t)(t0 * 1000));
            double t2 = NowMs();
            CGImageRef out = CGBitmapContextCreateImage(ctx);   // copies the pixels
            void *data = CGBitmapContextGetData(ctx);
            CGContextRelease(ctx); free(data);
            NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
            [fmt setDateFormat:@"yyyyMMdd-HHmmss"];
            NSString *n = [@"SLV-" stringByAppendingString:[fmt stringFromDate:[NSDate date]]];
            BOOL ok = writeJPEG(out, [self pathForPhoto:n], 0.9f);
            double t3 = NowMs();
            CGContextRef tc = grayContext(out, 0, kThumbWidth, kThumbHeight);
            if (tc) {
                CGImageRef thumb = CGBitmapContextCreateImage(tc);
                ok = ok && writeJPEG(thumb, [self pathForThumb:n], 0.8f);
                void *td = CGBitmapContextGetData(tc);
                CGImageRelease(thumb); CGContextRelease(tc); free(td);
            }
            CGImageRelease(out);
            if (ok) name = n;
            Log(@"developed %@ %zux%zu: decode+rotate %.0f ms, grain %.0f ms, encode %.0f ms, total %.0f ms",
                n, w, h, t1 - t0, t2 - t1, t3 - t2, NowMs() - t0);
        }
    } else {
        Log(@"develop failed: decode %p, ImageIO %d", src, loadImageIO());
    }
    if (src) CGImageRelease(src);
    [[job objectForKey:@"target"] performSelectorOnMainThread:NSSelectorFromString([job objectForKey:@"action"])
                                                   withObject:name waitUntilDone:NO];
    [pool release];
}

@end
