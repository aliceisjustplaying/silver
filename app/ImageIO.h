#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// ImageIO is a private framework on iPhone OS 3.1.3, so it is looked up at runtime.
BOOL ImageIOAvailable(void);
NSData *JPEGData(CGImageRef image, float quality);
// Uses ImageIO's reduced-scale JPEG decode, much faster than a full decode.
NSData *JPEGThumbnail(NSString *path, int maxPixels);
