#import <Foundation/Foundation.h>

// A small HTTP server for getting the Camera Roll onto other phones over Wi-Fi.
// Runs only while the Share screen is open. Pages:
//   /            gallery (newest first)
//   /p/<name>.jpg  full photo     /t/<name>.jpg  240 px thumbnail
// where <name> is like 100APPLE-IMG_0032.
@interface ShareServer : NSObject {
    int listenFd;
    BOOL running;
}
+ (NSString *)wifiAddress;   // en0 IPv4 address, or nil without Wi-Fi
- (BOOL)startOnPort:(int)port;
- (void)stop;
@end
