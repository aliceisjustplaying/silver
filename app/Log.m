#import "Log.h"
#include <mach/mach_time.h>

void Log(NSString *fmt, ...) {
    static FILE *f;
    if (!f) f = fopen("/tmp/silver.log", "a");
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"Silver: %@", s);
    if (f) { fprintf(f, "%.3f %s\n", NowMs() / 1000.0, [s UTF8String]); fflush(f); }
    [s release];
}

double NowMs(void) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}
