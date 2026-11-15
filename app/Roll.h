#import <UIKit/UIKit.h>
#import "Film.h"

// Developed photos: <home>/Library/Silver/<name>.jpg (1200x1600), screen/<name>.jpg (400x533,
// for the viewer) and thumbs/<name>.jpg (150x200).
@interface Roll : NSObject
+ (NSString *)directory;
+ (NSArray *)photoNames;                 // newest first
+ (NSString *)pathForPhoto:(NSString *)name;
+ (NSString *)pathForThumb:(NSString *)name;
+ (NSString *)pathForScreen:(NSString *)name;
// Develops a camera JPEG on a background thread, then calls
// [target performSelector:action withObject:name] on the main thread (name is nil on failure).
// previewMean is the live view's mean luma when the shutter was pressed; the photo's brightness is matched to it.
+ (void)develop:(NSData *)jpeg stock:(const FilmStock *)stock previewMean:(float)previewMean target:(id)target action:(SEL)action;
@end
