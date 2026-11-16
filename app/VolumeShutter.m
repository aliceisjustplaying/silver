#import "VolumeShutter.h"
#import <UIKit/UIKit.h>
#import "Log.h"
#include <dlfcn.h>

@interface NSObject (AVSystemController)
+ (id)sharedAVSystemController;
- (BOOL)getActiveCategoryVolume:(float *)volume andName:(NSString **)name;
- (BOOL)setActiveCategoryVolumeTo:(float)volume;
@end
@interface UIApplication (HUD)
- (void)setSystemVolumeHUDEnabled:(BOOL)enabled;
@end

static NSString *notificationName, *volumeKey;

@implementation VolumeShutter

- (id)initWithTarget:(id)t action:(SEL)a {
    if ((self = [super init])) { target = t; action = a; }
    return self;
}

- (void)start {
    if (running) return;
    void *h = dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial", RTLD_NOW);
    NSString **n = h ? dlsym(h, "AVSystemController_SystemVolumeDidChangeNotification") : NULL;
    NSString **k = h ? dlsym(h, "AVSystemController_AudioVolumeNotificationParameter") : NULL;
    controller = [NSClassFromString(@"AVSystemController") sharedAVSystemController];
    if (!n || !k || !controller) { Log(@"volume shutter unavailable"); return; }
    notificationName = *n; volumeKey = *k;
    NSString *category = nil;
    [controller getActiveCategoryVolume:&original andName:&category];
    // Volume up must be able to go up, so stay below the maximum.
    baseline = original > 0.9f ? 0.875f : original;
    if (baseline != original) [controller setActiveCategoryVolumeTo:baseline];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(volumeChanged:) name:notificationName object:nil];
    [[UIApplication sharedApplication] setSystemVolumeHUDEnabled:NO];
    running = YES;
    Log(@"volume shutter on (%@ volume %.3f, baseline %.3f)", category, original, baseline);
}

- (void)volumeChanged:(NSNotification *)note {
    float v = [[[note userInfo] objectForKey:volumeKey] floatValue];
    if (fabsf(v - baseline) < 0.001f) return;            // our own reset
    Log(@"volume %.3f -> %.3f", baseline, v);
    [controller setActiveCategoryVolumeTo:baseline];
    if (v > baseline) [target performSelector:action];
}

- (void)stop {
    if (!running) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:notificationName object:nil];
    [controller setActiveCategoryVolumeTo:original];
    [[UIApplication sharedApplication] setSystemVolumeHUDEnabled:YES];
    running = NO;
}

@end
