#import <Foundation/Foundation.h>
// Logs to NSLog and /tmp/silver.log (read over SSH during development).
void Log(NSString *fmt, ...);
double NowMs(void);
