#import "Roll+System.h"
#import "Log.h"
#include <dlfcn.h>
#include <objc/runtime.h>
#include <objc/message.h>

static id cameraAlbum(void) {
    return [NSClassFromString(@"PLCameraAlbum") performSelector:@selector(sharedInstance)];
}

static UIViewController *photoBrowser(id album, int index) {
    Class c = NSClassFromString(@"PLPhotoScrollerViewController");
    id vc = [c alloc];
    // -[PLPhotoScrollerViewController _initWithAlbum:lockStatusBar:currentImageIndex:]
    vc = ((id (*)(id, SEL, id, BOOL, int))objc_msgSend)(vc, @selector(_initWithAlbum:lockStatusBar:currentImageIndex:), album, YES, index);
    return [vc autorelease];
}

// -albumView:selectedPhoto: for our PLAlbumViewController subclass: open the browser at that photo.
static void albumViewSelectedPhoto(UIViewController *self, SEL _cmd, id albumView, id photo) {
    id album = cameraAlbum();
    NSUInteger i = [[album performSelector:@selector(images)] indexOfObject:photo];
    Log(@"roll: selected photo %lu", (unsigned long)i);
    if (i == NSNotFound) return;
    [self.navigationController pushViewController:photoBrowser(album, (int)i) animated:YES];
}

@implementation SystemRoll

+ (Class)albumControllerClass {
    static Class cls;
    if (cls) return cls;
    dlopen("/System/Library/PrivateFrameworks/PhotoLibrary.framework/PhotoLibrary", RTLD_NOW);
    Class base = NSClassFromString(@"PLAlbumViewController");
    if (!base || !NSClassFromString(@"PLPhotoScrollerViewController") || !NSClassFromString(@"PLCameraAlbum")) {
        Log(@"roll: PhotoLibrary classes missing");
        return nil;
    }
    cls = objc_allocateClassPair(base, "SilverAlbumViewController", 0);
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
