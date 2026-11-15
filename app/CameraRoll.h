#import <UIKit/UIKit.h>

// The phone's Camera Roll through the private PhotoLibrary framework (iPhone OS 3.1.3).
// It is the only place Silver keeps photos.
@interface CameraRoll : NSObject
+ (BOOL)available;
// Saves a developed photo the way the built-in Camera app does: the finished JPEG bytes are
// written as-is (no re-encode) and the preview is handed over so the Photos UI can show the
// photo straight away. image is the decoded full-size photo.
+ (BOOL)saveJPEG:(NSData *)jpeg image:(UIImage *)image preview:(UIImage *)preview;
// The image shown in the Camera app's "image well" (last photo taken), or nil.
+ (UIImage *)wellImage;
// Paths of the Camera Roll's photos (JPG) and screenshots (PNG), newest first.
+ (NSArray *)photoPaths;

// A navigation controller showing the Camera Roll grid (PLAlbumViewController); tapping a
// photo opens the system photo browser (PLPhotoScrollerViewController). done is sent to
// target when the user taps Done.
+ (UINavigationController *)navigationControllerWithDoneTarget:(id)target action:(SEL)done;
// Opens the photo browser at the newest photo (silver://rollphoto test hook).
+ (void)showNewestIn:(UINavigationController *)nav;
@end
