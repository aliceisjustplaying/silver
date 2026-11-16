#import <UIKit/UIKit.h>

// The Camera Roll via the private PhotoLibrary framework. Silver keeps photos only there.
@interface CameraRoll : NSObject
+ (BOOL)available;
// Saves like the Camera app: JPEG written as-is, preview handed over so Photos can show it at once.
+ (BOOL)saveJPEG:(NSData *)jpeg image:(UIImage *)image preview:(UIImage *)preview;
// Small JPEG of the newest photo or screenshot, or nil if the Camera Roll is empty. Slow (~0.5 s).
+ (NSData *)newestThumbnailJPEG;
// JPG photos and PNG screenshots, newest first.
+ (NSArray *)photoPaths;

// Camera Roll grid (PLAlbumViewController); a tap opens PLPhotoScrollerViewController.
+ (UINavigationController *)navigationControllerWithDoneTarget:(id)target action:(SEL)done;
+ (void)showNewestIn:(UINavigationController *)nav;
@end
