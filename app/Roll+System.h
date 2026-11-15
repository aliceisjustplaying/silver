#import <UIKit/UIKit.h>

// The system Photos UI from the private PhotoLibrary framework (iPhone OS 3.1.3):
// the Camera Roll thumbnail grid (PLAlbumViewController) and, on tap, the swipe-and-zoom
// photo browser (PLPhotoScrollerViewController). Silver also saves every photo to the
// Camera Roll, so this shows them.
@interface SystemRoll : NSObject
// A navigation controller showing the Camera Roll grid, or nil if the classes are missing.
// done is sent to target when the user taps Done.
+ (UINavigationController *)navigationControllerWithDoneTarget:(id)target action:(SEL)done;
// Opens the photo browser at the newest photo (used by the silver://rollphoto test hook).
+ (void)showNewestIn:(UINavigationController *)nav;
@end
