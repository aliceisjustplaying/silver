#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@class Camera;
@protocol CameraDelegate
- (void)camera:(Camera *)camera tookPhoto:(NSData *)jpeg;
- (void)cameraFailed:(Camera *)camera reason:(NSString *)reason;
@end

// Live black-and-white preview from the private Camera.framework API.
// Frames are converted by gray_bgra straight into display surfaces that
// are set as the layer's contents (no copies, no CGImage).
@interface Camera : NSObject {
    id<CameraDelegate> delegate;
    CALayer *layer;
    void *dev;
    void *disp[2];
    int dispIndex;
    uint32_t table[256];
    BOOL photoPending;
    int frames; double windowStart, workMs;
@public
    float fps, msPerFrame;
}
- (id)initWithLayer:(CALayer *)layer delegate:(id<CameraDelegate>)delegate;
- (BOOL)start;
- (void)setPreviewTable:(const uint32_t *)table;
- (BOOL)takePhoto;   // NO if a photo is already in progress
@end
