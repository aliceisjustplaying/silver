#import <Foundation/Foundation.h>

// Serves the Camera Roll over Wi-Fi while the Share screen is open:
//   /, /?page=N   gallery, 60 per page, newest first
//   /p/<name>     full photo or screenshot     /t/<name>.jpg  240 px thumbnail
// where <name> is like 100APPLE-IMG_0032.
@interface ShareServer : NSObject {
    int listenFd;
    BOOL running;
}
+ (NSString *)wifiAddress;
- (BOOL)startOnPort:(int)port;
- (void)stop;
@end
