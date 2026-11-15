#import <UIKit/UIKit.h>
#import "Film.h"

@interface Develop : NSObject
// On a background thread; then calls action on the main thread with nil or a dictionary of
// @"jpeg" (1200x1600 NSData), @"image" and @"preview" (400x533) UIImages. The photo's
// brightness is matched to previewMean, the live view's at the shutter.
+ (void)develop:(NSData *)jpeg stock:(const FilmStock *)stock previewMean:(float)previewMean target:(id)target action:(SEL)action;
@end
