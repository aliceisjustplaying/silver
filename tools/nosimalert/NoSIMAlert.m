// NoSIMAlert: a MobileSubstrate tweak for iPhone OS 3 that stops SpringBoard showing
// "No SIM Card Installed" (an SBSIMLockAlertItem) on a phone used without a SIM.
#import <Foundation/Foundation.h>
#include <objc/runtime.h>

static IMP origActivate;

static void activateAlertItem(id self, SEL _cmd, id item) {
    if ([item isKindOfClass:objc_getClass("SBSIMLockAlertItem")]) return;
    ((void (*)(id, SEL, id))origActivate)(self, _cmd, item);
}

__attribute__((constructor)) static void init(void) {
    Method m = class_getInstanceMethod(objc_getClass("SBAlertItemsController"), @selector(activateAlertItem:));
    if (m) origActivate = method_setImplementation(m, (IMP)activateAlertItem);
}
