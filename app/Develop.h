#import <UIKit/UIKit.h>
#import "Film.h"

// Turns the camera's color JPEG into the finished black-and-white photo.
@interface Develop : NSObject
// Runs on a background thread, then calls [target performSelector:action withObject:result]
// on the main thread. result is nil on failure, otherwise a dictionary with
//   @"jpeg"     NSData, the finished 1200x1600 JPEG
//   @"image"    UIImage of the same pixels (already decoded)
//   @"preview"  UIImage, 400x533 (for the Camera Roll's preview and the thumbnail button)
// previewMean is the live view's mean luma when the shutter was pressed; the photo's
// brightness is matched to it.
+ (void)develop:(NSData *)jpeg stock:(const FilmStock *)stock previewMean:(float)previewMean target:(id)target action:(SEL)action;
@end
