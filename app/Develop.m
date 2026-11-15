#import "Develop.h"
#import "ImageIO.h"
#import "Log.h"

static void shrink3(const uint8_t *src, int sw, int sh, int srb, uint8_t *dst, int drb) {
    for (int y = 0; y < sh / 3; y++) {
        const uint8_t *r0 = src + 3 * y * srb, *r1 = r0 + srb, *r2 = r1 + srb;
        uint8_t *d = dst + y * drb;
        for (int x = 0; x < sw / 3; x++, r0 += 3, r1 += 3, r2 += 3)
            d[x] = (r0[0] + r0[1] + r0[2] + r1[0] + r1[1] + r1[2] + r2[0] + r2[1] + r2[2] + 4) / 9;
    }
}

static void freePixels(void *info, const void *data, size_t size) { free((void *)data); }

// Takes ownership of pixels (CGBitmapContextCreateImage may share them copy-on-write).
static CGImageRef grayImage(uint8_t *pixels, size_t w, size_t h, size_t rowBytes) {
    CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, pixels, rowBytes * h, freePixels);
    CGColorSpaceRef gs = CGColorSpaceCreateDeviceGray();
    CGImageRef img = CGImageCreate(w, h, 8, 8, rowBytes, gs, kCGImageAlphaNone, dp, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(gs); CGDataProviderRelease(dp);
    return img;
}

// Same luma weights as the live view (gray.s): Y = (29 B + 150 G + 77 R) >> 8.
static inline int luma(uint32_t p) { return (29 * (p & 0xff) + 150 * ((p >> 8) & 0xff) + 77 * ((p >> 16) & 0xff)) >> 8; }

// The camera's landscape frame turned a quarter clockwise: dst[y][x] = src[sh-1-x][y], in tiles.
static void lumaRotateCW(const uint32_t *src, int sw, int sh, uint8_t *dst, int dstRowBytes, const uint8_t table[256]) {
    enum { T = 16 };
    for (int y0 = 0; y0 < sw; y0 += T)
        for (int x0 = 0; x0 < sh; x0 += T)
            for (int y = y0; y < y0 + T && y < sw; y++) {
                uint8_t *d = dst + y * dstRowBytes;
                for (int x = x0; x < x0 + T && x < sh; x++) d[x] = table[luma(src[(sh - 1 - x) * sw + y])];
            }
}

@implementation Develop

+ (void)develop:(NSData *)jpeg stock:(const FilmStock *)stock previewMean:(float)previewMean target:(id)target action:(SEL)action {
    NSDictionary *job = [NSDictionary dictionaryWithObjectsAndKeys:jpeg, @"jpeg",
        [NSValue valueWithPointer:stock], @"stock", [NSNumber numberWithFloat:previewMean], @"previewMean",
        target, @"target", NSStringFromSelector(action), @"action", nil];
    [NSThread detachNewThreadSelector:@selector(developJob:) toTarget:self withObject:job];
}

+ (void)developJob:(NSDictionary *)job {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSDictionary *result = nil;
    double t0 = NowMs();
    const FilmStock *stock = [[job objectForKey:@"stock"] pointerValue];
    float previewMean = [[job objectForKey:@"previewMean"] floatValue];
    CGDataProviderRef dp = CGDataProviderCreateWithCFData((CFDataRef)[job objectForKey:@"jpeg"]);
    CGImageRef src = CGImageCreateWithJPEGDataProvider(dp, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(dp);
    size_t sw = src ? CGImageGetWidth(src) : 0, sh = src ? CGImageGetHeight(src) : 0;
    uint32_t *rgb = src ? malloc(sw * sh * 4) : NULL;
    if (rgb && ImageIOAvailable()) {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef dc = CGBitmapContextCreate(rgb, sw, sh, 8, sw * 4, cs, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(cs);
        CGContextDrawImage(dc, CGRectMake(0, 0, sw, sh), src);
        CGContextRelease(dc);
        double t1 = NowMs();

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

        CGImageRef out = grayImage(gray, w, h, rowBytes);
        size_t sw3 = w / 3, sh3 = h / 3, srb = (sw3 + 15) & ~15;
        uint8_t *small = calloc(srb, sh3);
        shrink3(gray, w, h, rowBytes, small, srb);
        CGImageRef screen = grayImage(small, sw3, sh3, srb);
        NSData *jpg = JPEGData(out, 0.9f);
        double t4 = NowMs();
        if (jpg) result = [NSDictionary dictionaryWithObjectsAndKeys:jpg, @"jpeg",
            [UIImage imageWithCGImage:out], @"image", [UIImage imageWithCGImage:screen], @"preview", nil];
        CGImageRelease(screen); CGImageRelease(out);
        Log(@"developed %zux%zu: preview mean %.1f, photo mean %.1f, gain %.2f; decode %.0f ms, luma+rotate %.0f ms, "
            "grain %.0f ms, encode %.0f ms, total %.0f ms", w, h, previewMean, photoMean, gain,
            t1 - t0, t2 - t1, t3 - t2, t4 - t3, NowMs() - t0);
    } else {
        Log(@"develop failed: decode %p, ImageIO %d", src, ImageIOAvailable());
    }
    free(rgb);
    if (src) CGImageRelease(src);
    [[job objectForKey:@"target"] performSelectorOnMainThread:NSSelectorFromString([job objectForKey:@"action"])
                                                   withObject:result waitUntilDone:NO];
    [pool release];
}

@end
