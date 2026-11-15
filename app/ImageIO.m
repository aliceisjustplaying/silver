#import "ImageIO.h"
#include <dlfcn.h>

typedef void *CGImageDestinationRef, *CGImageSourceRef;
static CGImageDestinationRef (*pDestCreate)(CFMutableDataRef, CFStringRef, size_t, CFDictionaryRef);
static void (*pDestAdd)(CGImageDestinationRef, CGImageRef, CFDictionaryRef);
static bool (*pDestFinalize)(CGImageDestinationRef);
static CGImageSourceRef (*pSourceCreate)(CFURLRef, CFDictionaryRef);
static CGImageRef (*pThumb)(CGImageSourceRef, size_t, CFDictionaryRef);
static CFStringRef kQuality, kMaxPixels, kAlways, kTransform;

BOOL ImageIOAvailable(void) {
    static int state;
    if (state) return state > 0;
    void *h = dlopen("/System/Library/PrivateFrameworks/ImageIO.framework/ImageIO", RTLD_NOW);
    if (!h) h = dlopen("/System/Library/Frameworks/ImageIO.framework/ImageIO", RTLD_NOW);
    if (h) {
        *(void **)&pDestCreate = dlsym(h, "CGImageDestinationCreateWithData");
        *(void **)&pDestAdd = dlsym(h, "CGImageDestinationAddImage");
        *(void **)&pDestFinalize = dlsym(h, "CGImageDestinationFinalize");
        *(void **)&pSourceCreate = dlsym(h, "CGImageSourceCreateWithURL");
        *(void **)&pThumb = dlsym(h, "CGImageSourceCreateThumbnailAtIndex");
        CFStringRef *k;
        if ((k = dlsym(h, "kCGImageDestinationLossyCompressionQuality"))) kQuality = *k;
        if ((k = dlsym(h, "kCGImageSourceThumbnailMaxPixelSize"))) kMaxPixels = *k;
        if ((k = dlsym(h, "kCGImageSourceCreateThumbnailFromImageAlways"))) kAlways = *k;
        if ((k = dlsym(h, "kCGImageSourceCreateThumbnailWithTransform"))) kTransform = *k;
    }
    state = (pDestCreate && pDestAdd && pDestFinalize && pSourceCreate && pThumb && kQuality && kMaxPixels && kAlways) ? 1 : -1;
    return state > 0;
}

NSData *JPEGData(CGImageRef image, float quality) {
    if (!ImageIOAvailable()) return nil;
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef d = pDestCreate((CFMutableDataRef)data, CFSTR("public.jpeg"), 1, NULL);
    if (!d) return nil;
    NSDictionary *props = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:quality] forKey:(id)kQuality];
    pDestAdd(d, image, (CFDictionaryRef)props);
    BOOL ok = pDestFinalize(d);
    CFRelease(d);
    return ok ? data : nil;
}

NSData *JPEGThumbnail(NSString *path, int maxPixels) {
    if (!ImageIOAvailable()) return nil;
    CGImageSourceRef src = pSourceCreate((CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!src) return nil;
    NSMutableDictionary *opts = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:maxPixels], (id)kMaxPixels, (id)kCFBooleanTrue, (id)kAlways, nil];
    if (kTransform) [opts setObject:(id)kCFBooleanTrue forKey:(id)kTransform];
    CGImageRef t = pThumb(src, 0, (CFDictionaryRef)opts);
    CFRelease(src);
    if (!t) return nil;
    NSData *d = JPEGData(t, 0.8f);
    CGImageRelease(t);
    return d;
}
