// SBSettings toggle for RotationLock. SBSettings calls these C functions; "enabled" (green)
// means rotation is allowed, as with SBSettings' other toggles.
#import <Foundation/Foundation.h>

static NSString *const kPrefs = @"/var/mobile/Library/Preferences/com.aliceisjustplaying.rotationlock.plist";

static BOOL locked(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    BOOL l = [[[NSDictionary dictionaryWithContentsOfFile:kPrefs] objectForKey:@"Locked"] boolValue];
    [pool release];
    return l;
}

BOOL isCapable(void) { return YES; }
BOOL isEnabled(void) { return !locked(); }
BOOL getStateFast(void) { return !locked(); }
float getDelayTime(void) { return 0.1f; }

void setState(BOOL enable) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:!enable] forKey:@"Locked"] writeToFile:kPrefs atomically:YES];
    [pool release];
}
