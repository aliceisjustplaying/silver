#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// ImageIO is a private framework on iPhone OS 3.1.3, so it is looked up at runtime.
BOOL ImageIOAvailable(void);
NSData *JPEGData(CGImageRef image, float quality);
// A JPEG thumbnail of the JPEG at path, at most maxPixels on its long side. ImageIO decodes
// JPEGs at 1/2, 1/4 or 1/8 scale for this, so it's much faster than a full decode.
NSData *JPEGThumbnail(NSString *path, int maxPixels);
