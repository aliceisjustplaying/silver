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
    BOOL photoPending, paused;
    NSString *dumpDir;
    int anomalies;
    int frames; double windowStart, workMs;
@public
    float fps, msPerFrame;
    float previewMean;   // mean luma (0..255) of the latest frame, before the tone curve
}
- (id)initWithLayer:(CALayer *)layer delegate:(id<CameraDelegate>)delegate;
- (BOOL)start;
- (void)setPreviewTable:(const uint32_t *)table;
- (BOOL)takePhoto;   // NO if a photo is already in progress
// Stop and restart the preview (while the Camera Roll is open). Restarting rebuilds the
// capture surfaces, which also clears a garbled preview.
- (void)pause;
- (void)resume;
// Debugging: on the next frame, writes into dir the raw camera frame (camera.png), the
// displayed frame (display.png) and camera.txt (Camera.framework state, the frame's surface
// properties and the sensor's variables).
- (void)dumpNextFrameTo:(NSString *)dir;
// Text describing the sensor's preview-related variables, for the log.
- (NSString *)sensorSummary;
@end
