#import "CameraRoll.h"
#import "Log.h"
#include <dlfcn.h>
#include <objc/runtime.h>
#include <objc/message.h>

static NSString *const kDCIM = @"/var/mobile/Media/DCIM";

static Class albumClass(void) {
    static BOOL loaded;
    if (!loaded) { dlopen("/System/Library/PrivateFrameworks/PhotoLibrary.framework/PhotoLibrary", RTLD_NOW); loaded = YES; }
    return NSClassFromString(@"PLCameraAlbum");
}

static id cameraAlbum(void) { return [albumClass() performSelector:@selector(sharedInstance)]; }

static UIViewController *photoBrowser(id album, int index) {
    id vc = [NSClassFromString(@"PLPhotoScrollerViewController") alloc];
    // -[PLPhotoScrollerViewController _initWithAlbum:lockStatusBar:currentImageIndex:]
    vc = ((id (*)(id, SEL, id, BOOL, int))objc_msgSend)(vc, @selector(_initWithAlbum:lockStatusBar:currentImageIndex:), album, YES, index);
    return [vc autorelease];
}

// -albumView:selectedPhoto: for our PLAlbumViewController subclass: open the browser at that photo.
static void albumViewSelectedPhoto(UIViewController *self, SEL _cmd, id albumView, id photo) {
    id album = cameraAlbum();
    NSUInteger i = [[album performSelector:@selector(images)] indexOfObject:photo];
    if (i != NSNotFound) [self.navigationController pushViewController:photoBrowser(album, (int)i) animated:YES];
}

@implementation CameraRoll

+ (BOOL)available {
    return albumClass() && NSClassFromString(@"PLAlbumViewController") && NSClassFromString(@"PLPhotoScrollerViewController");
}

+ (BOOL)saveJPEG:(NSData *)jpeg image:(UIImage *)image preview:(UIImage *)preview {
    if (![self available]) return NO;
    double t0 = NowMs();
    // -[PLCameraAlbum addImage:withPreview:exifProperties:date:jpegData:notifyingTarget:selector:contextInfo:]
    // (PhotoLibrary's own PLSaveImageToCameraRollWithJPEGData calls it with preview and date nil.)
    BOOL ok = ((BOOL (*)(id, SEL, id, id, id, id, CFDataRef, id, SEL, void *))objc_msgSend)(cameraAlbum(),
        @selector(addImage:withPreview:exifProperties:date:jpegData:notifyingTarget:selector:contextInfo:),
        image, preview, nil, [NSDate date], (CFDataRef)jpeg, nil, NULL, NULL);
    [albumClass() performSelector:@selector(savePreviewWellImage:) withObject:preview];
    Log(@"saved to Camera Roll (%d) in %.0f ms", ok, NowMs() - t0);
    return ok;
}

+ (UIImage *)wellImage {
    Class c = albumClass();
    return c ? [c performSelector:@selector(previewWellImage)] : nil;
}

+ (NSArray *)photoPaths {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *paths = [NSMutableArray array];
    NSArray *folders = [[fm contentsOfDirectoryAtPath:kDCIM error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *folder in folders) {
        NSString *dir = [kDCIM stringByAppendingPathComponent:folder];
        for (NSString *f in [[fm contentsOfDirectoryAtPath:dir error:NULL] sortedArrayUsingSelector:@selector(compare:)])
            if ([[f uppercaseString] hasSuffix:@".JPG"] || [[f uppercaseString] hasSuffix:@".PNG"])   // photos and screenshots
                [paths addObject:[dir stringByAppendingPathComponent:f]];
    }
    return [[paths reverseObjectEnumerator] allObjects];
}

+ (Class)albumControllerClass {
    static Class cls;
    if (cls || ![self available]) return cls;
    cls = objc_allocateClassPair(NSClassFromString(@"PLAlbumViewController"), "SilverAlbumViewController", 0);
    class_addMethod(cls, @selector(albumView:selectedPhoto:), (IMP)albumViewSelectedPhoto, "v16@0:4@8@12");
    objc_registerClassPair(cls);
    return cls;
}

+ (UINavigationController *)navigationControllerWithDoneTarget:(id)target action:(SEL)done {
    Class c = [self albumControllerClass];
    if (!c) return nil;
    UIViewController *grid = [[[c alloc] performSelector:@selector(initWithAlbum:) withObject:cameraAlbum()] autorelease];
    grid.title = @"Camera Roll";
    grid.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:target action:done] autorelease];
    UINavigationController *nav = [[[UINavigationController alloc] initWithRootViewController:grid] autorelease];
    nav.navigationBar.barStyle = UIBarStyleBlackOpaque;
    return nav;
}

+ (void)showNewestIn:(UINavigationController *)nav {
    id album = cameraAlbum();
    int n = (int)[[album performSelector:@selector(images)] count];
    if (n) [nav pushViewController:photoBrowser(album, n - 1) animated:YES];
}

@end
