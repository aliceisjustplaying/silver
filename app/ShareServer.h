#import <Foundation/Foundation.h>

// A small HTTP server for getting photos onto other phones over Wi-Fi.
// Runs only while the Share screen is open. Pages:
//   /            gallery (newest first)
//   /p/<name>.jpg  full photo     /t/<name>.jpg  thumbnail
@interface ShareServer : NSObject {
    int listenFd;
    BOOL running;
}
+ (NSString *)wifiAddress;   // en0 IPv4 address, or nil without Wi-Fi
- (BOOL)startOnPort:(int)port;
- (void)stop;
@end
