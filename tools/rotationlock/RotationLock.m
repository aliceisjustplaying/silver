// RotationLock: rotation lock for iPhone OS 3, which has none (it arrived in iOS 4).
// Loaded into every UIKit app; while locked, the app ignores device orientation changes
// (-[UIApplication deviceOrientationChanged:] is how GraphicsServices delivers them).
// The SBSettings toggle in Toggle.m writes the setting.
#import <UIKit/UIKit.h>
#include <objc/runtime.h>

static NSString *const kPrefs = @"/var/mobile/Library/Preferences/com.aliceisjustplaying.rotationlock.plist";
static IMP origChanged;

static void deviceOrientationChanged(id self, SEL _cmd, void *event) {
    if ([[[NSDictionary dictionaryWithContentsOfFile:kPrefs] objectForKey:@"Locked"] boolValue]) return;
    ((void (*)(id, SEL, void *))origChanged)(self, _cmd, event);
}

__attribute__((constructor)) static void init(void) {
    Method m = class_getInstanceMethod([UIApplication class], @selector(deviceOrientationChanged:));
    if (m) origChanged = method_setImplementation(m, (IMP)deviceOrientationChanged);
}
