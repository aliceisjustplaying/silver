#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@class Camera;
@protocol CameraDelegate
- (void)camera:(Camera *)camera tookPhoto:(NSData *)jpeg;
- (void)cameraFailed:(Camera *)camera reason:(NSString *)reason;
@end

// Live B&W preview: camera frames go through gray_bgra straight into display surfaces used
// as the layer's contents.
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
    float previewMean;   // raw luma of the latest frame, 0..255
}
- (id)initWithLayer:(CALayer *)layer delegate:(id<CameraDelegate>)delegate;
- (BOOL)start;
- (void)setPreviewTable:(const uint32_t *)table;
- (BOOL)takePhoto;
- (void)pause;
- (void)resume;
// Writes camera.png, display.png and camera.txt for the next frame into dir.
- (void)dumpNextFrameTo:(NSString *)dir;
- (NSString *)sensorSummary;
@end
