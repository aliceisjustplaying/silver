#import "ShareServer.h"
#import "CameraRoll.h"
#import "ImageIO.h"
#import "Log.h"
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <pthread.h>
#include <sys/socket.h>
#include <unistd.h>

static void sendAll(int fd, const void *buf, size_t len) {
    const char *p = buf;
    while (len > 0) {
        ssize_t n = write(fd, p, len);
        if (n <= 0) return;
        p += n; len -= n;
    }
}

static void sendResponse(int fd, int status, const char *type, NSData *body, BOOL head, BOOL cacheable) {
    const char *reason = status == 200 ? "OK" : status == 404 ? "Not Found" : "Bad Request";
    NSString *h = [NSString stringWithFormat:@"HTTP/1.0 %d %s\r\nContent-Type: %s\r\nContent-Length: %lu\r\n"
                   "Cache-Control: %s\r\nConnection: close\r\n\r\n", status, reason, type, (unsigned long)[body length],
                   cacheable ? "max-age=86400" : "no-cache"];
    NSData *hd = [h dataUsingEncoding:NSUTF8StringEncoding];
    sendAll(fd, [hd bytes], [hd length]);
    if (!head) sendAll(fd, [body bytes], [body length]);
}

enum { kPerPage = 60, kThumbPixels = 240 };

// URL names for everything in the Camera Roll (photos and screenshots): "100APPLE-IMG_0032"
// -> its path, newest first.
static NSArray *photoNames(NSDictionary **pathsOut) {
    NSMutableArray *names = [NSMutableArray array];
    NSMutableDictionary *paths = [NSMutableDictionary dictionary];
    for (NSString *path in [CameraRoll photoPaths]) {
        NSString *n = [NSString stringWithFormat:@"%@-%@", [[path stringByDeletingLastPathComponent] lastPathComponent],
                       [[path lastPathComponent] stringByDeletingPathExtension]];
        [names addObject:n]; [paths setObject:path forKey:n];
    }
    if (pathsOut) *pathsOut = paths;
    return names;
}

static NSData *galleryPage(int page) {
    NSArray *names = photoNames(NULL);
    int count = (int)[names count], pages = (count + kPerPage - 1) / kPerPage;
    if (page < 1) page = 1;
    if (page > pages) page = pages ? pages : 1;
    NSMutableString *html = [NSMutableString stringWithString:
        @"<!doctype html><html><head><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'><title>Silver · Camera Roll</title><style>"
        "body{margin:0;background:#000;color:#ddd;font:15px -apple-system,Helvetica,sans-serif}"
        "h1{font-weight:400;letter-spacing:.3em;font-size:15px;margin:18px 14px 4px;color:#e5b83b}"
        "p{margin:0 14px 14px;color:#888} nav{display:flex;justify-content:space-between;margin:14px}"
        "nav a{color:#e5b83b;text-decoration:none}"
        ".g{display:grid;grid-template-columns:repeat(3,1fr);gap:2px}"
        ".g a{display:block;aspect-ratio:3/4;background:#111}"
        ".g img{width:100%;height:100%;object-fit:cover;display:block}"
        "</style></head><body><h1>SILVER</h1>"];
    [html appendFormat:@"<p>Camera Roll: %d item%@%@. Tap one, then touch and hold it to save it to Photos.</p>",
        count, count == 1 ? @"" : @"s",
        pages > 1 ? [NSString stringWithFormat:@" (page %d of %d)", page, pages] : @""];
    NSMutableString *nav = [NSMutableString stringWithString:@"<nav><span>"];
    if (page > 1) [nav appendFormat:@"<a href='/?page=%d'>&larr; Newer</a>", page - 1];
    [nav appendString:@"</span><span>"];
    if (page < pages) [nav appendFormat:@"<a href='/?page=%d'>Older &rarr;</a>", page + 1];
    [nav appendString:@"</span></nav>"];
    [html appendString:@"<div class=g>"];
    for (int i = (page - 1) * kPerPage; i < count && i < page * kPerPage; i++) {
        NSString *n = [names objectAtIndex:i];
        [html appendFormat:@"<a href='/p/%@'><img src='/t/%@.jpg' loading=lazy decoding=async></a>", n, n];
    }
    [html appendFormat:@"</div>%@</body></html>", pages > 1 ? nav : @""];
    return [html dataUsingEncoding:NSUTF8StringEncoding];
}

// Gallery thumbnails, 240 px, cached on disk in ~/Library/Caches/Silver/thumbs (about 10 KB
// each) so each is only ever made once. Making one takes about 0.6 s, so one is made at a
// time: a background thread works through the Camera Roll newest first while Share is open.
// Until a photo's thumbnail exists, the page gets the system's 75x75 one (.MISC/<name>.THM).
static pthread_mutex_t gThumbLock = PTHREAD_MUTEX_INITIALIZER;

static NSString *thumbCachePath(NSString *name, NSString *source) {
    static NSString *dir;
    if (!dir) {
        dir = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/Silver/thumbs"] retain];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    // Keyed by size too, in case a file number is reused after a deletion.
    unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:source error:NULL] fileSize];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%llu.jpg", name, size]];
}

static NSData *makeThumbnail(NSString *name, NSString *source) {
    NSString *cache = thumbCachePath(name, source);
    pthread_mutex_lock(&gThumbLock);
    NSData *d = [NSData dataWithContentsOfFile:cache];
    if (!d && (d = JPEGThumbnail(source, kThumbPixels))) [d writeToFile:cache atomically:YES];
    pthread_mutex_unlock(&gThumbLock);
    return d;
}

static NSData *thumbnailForRequest(NSString *name, NSString *source, BOOL *final) {
    NSData *d = [NSData dataWithContentsOfFile:thumbCachePath(name, source)];
    *final = d != nil;
    if (d) return d;
    NSString *thm = [[[[source stringByDeletingLastPathComponent] stringByAppendingPathComponent:@".MISC"]
        stringByAppendingPathComponent:[[source lastPathComponent] stringByDeletingPathExtension]]
        stringByAppendingPathExtension:@"THM"];
    if ((d = [NSData dataWithContentsOfFile:thm])) return d;
    *final = YES;
    return makeThumbnail(name, source);
}

static volatile int gWarmGeneration;

static void *warmThumbnails(void *arg) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    int generation = (int)(intptr_t)arg, made = 0;
    double t0 = NowMs();
    NSDictionary *paths;
    for (NSString *n in photoNames(&paths)) {
        if (generation != gWarmGeneration) break;          // sharing stopped
        NSAutoreleasePool *inner = [NSAutoreleasePool new];
        NSString *src = [paths objectForKey:n];
        if (![[NSFileManager defaultManager] fileExistsAtPath:thumbCachePath(n, src)]) { makeThumbnail(n, src); made++; }
        [inner release];
    }
    Log(@"thumbnails: made %d in %.0f ms", made, NowMs() - t0);
    [pool release];
    return NULL;
}

static void *handle(void *arg) {
    int fd = (int)(intptr_t)arg;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    char buf[2048]; size_t used = 0;
    while (used < sizeof buf - 1) {                         // read the request line and headers
        ssize_t n = read(fd, buf + used, sizeof buf - 1 - used);
        if (n <= 0) break;
        used += n; buf[used] = 0;
        if (strstr(buf, "\r\n\r\n") || strstr(buf, "\n\n")) break;
    }
    buf[used] = 0;
    char method[8] = "", path[512] = "";
    if (sscanf(buf, "%7s %511s", method, path) != 2 || (strcmp(method, "GET") && strcmp(method, "HEAD"))) {
        sendResponse(fd, 400, "text/plain", [NSData dataWithBytes:"bad request\n" length:12], NO, NO);
    } else {
        BOOL head = !strcmp(method, "HEAD"), cacheable = NO;
        NSString *p = [NSString stringWithUTF8String:path];
        NSData *body = nil; const char *type = "image/jpeg";
        if ([p isEqualToString:@"/"] || [p hasPrefix:@"/?page="]) {
            body = galleryPage([p hasPrefix:@"/?page="] ? [[p substringFromIndex:7] intValue] : 1);
            type = "text/html; charset=utf-8";
        } else if ([p hasPrefix:@"/p/"] || [p hasPrefix:@"/t/"]) {
            NSDictionary *paths;
            photoNames(&paths);
            NSString *name = [[p substringFromIndex:3] stringByDeletingPathExtension];
            NSString *file = [paths objectForKey:name];      // only Camera Roll items: no path traversal
            if (file && [p hasPrefix:@"/p/"]) {
                body = [NSData dataWithContentsOfFile:file];
                if ([[file uppercaseString] hasSuffix:@".PNG"]) type = "image/png";
                cacheable = YES;
            } else if (file) {
                body = thumbnailForRequest(name, file, &cacheable);
            }
        }
        if (body) sendResponse(fd, 200, type, body, head, cacheable);
        else sendResponse(fd, 404, "text/plain", [NSData dataWithBytes:"not found\n" length:10], head, NO);
        Log(@"http %s %s -> %d", method, path, body ? 200 : 404);
    }
    close(fd);
    [pool release];
    return NULL;
}

// One thread per connection: Safari opens several at once, and a slow thumbnail must not
// hold up the page or the other images.
static void *serve(void *arg) {
    int lfd = (int)(intptr_t)arg;
    for (;;) {
        int fd = accept(lfd, NULL, NULL);
        if (fd < 0) break;                                  // listening socket closed: stop
        struct timeval tv = {10, 0};
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
        int one = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        pthread_t t;
        if (pthread_create(&t, NULL, handle, (void *)(intptr_t)fd)) handle((void *)(intptr_t)fd);
        else pthread_detach(t);
    }
    return NULL;
}

@implementation ShareServer

+ (NSString *)wifiAddress {
    struct ifaddrs *list, *i; NSString *addr = nil;
    if (getifaddrs(&list)) return nil;
    for (i = list; i; i = i->ifa_next)
        if (i->ifa_addr && i->ifa_addr->sa_family == AF_INET && !strcmp(i->ifa_name, "en0"))
            addr = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)i->ifa_addr)->sin_addr)];
    freeifaddrs(list);
    return addr;
}

- (BOOL)startOnPort:(int)port {
    if (running) return YES;
    listenFd = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in sa = {0};
    sa.sin_len = sizeof sa; sa.sin_family = AF_INET; sa.sin_port = htons(port); sa.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(listenFd, (struct sockaddr *)&sa, sizeof sa) || listen(listenFd, 8)) {
        Log(@"share server: bind/listen on %d failed (%d)", port, errno);
        close(listenFd); return NO;
    }
    pthread_t t;
    pthread_create(&t, NULL, serve, (void *)(intptr_t)listenFd);
    pthread_detach(t);
    pthread_create(&t, NULL, warmThumbnails, (void *)(intptr_t)++gWarmGeneration);
    pthread_detach(t);
    running = YES;
    Log(@"share server listening on %d", port);
    return YES;
}

- (void)stop {
    if (!running) return;
    gWarmGeneration++;                                      // stops the warm-up thread
    shutdown(listenFd, SHUT_RDWR);
    close(listenFd);
    running = NO;
    Log(@"share server stopped");
}

@end
