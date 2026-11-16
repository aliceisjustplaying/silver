#import <Foundation/Foundation.h>

// Volume up as a shutter button. iPhone OS 3 apps get no button events, so this watches the
// system volume (Celestial's AVSystemController), fires on an increase, puts the volume back
// and hides SpringBoard's volume HUD while running.
@interface VolumeShutter : NSObject {
    id target; SEL action;
    id controller;
    float original, baseline;
    BOOL running;
}
- (id)initWithTarget:(id)target action:(SEL)action;
- (void)start;
- (void)stop;   // restores the volume and the HUD
@end
