#import "ShareServer.h"
#import "CameraRoll.h"
#import "ImageIO.h"
#import "Log.h"
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <pthread.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include <zlib.h>

static int sendAll(int fd, const void *buf, size_t len) {
    const char *p = buf;
    while (len > 0) {
        ssize_t n = write(fd, p, len);
        if (n <= 0) return -1;
        p += n; len -= n;
    }
    return 0;
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

// "100APPLE-IMG_0032" -> path, newest first.
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
    NSDictionary *paths;
    NSArray *names = photoNames(&paths);
    int count = (int)[names count], pages = (count + kPerPage - 1) / kPerPage;
    unsigned long long total = 0;
    for (NSString *n in names)
        total += [[[NSFileManager defaultManager] attributesOfItemAtPath:[paths objectForKey:n] error:NULL] fileSize];
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
        ".bar{display:flex;gap:18px;margin:0 14px 14px}.bar a,.bar button{color:#e5b83b;font:inherit;"
        "background:none;border:0;padding:0;text-decoration:none}"
        ".g a{position:relative}.sel .g a.on::after{content:'\\2713';position:absolute;right:5px;bottom:5px;width:22px;"
        "height:22px;border-radius:50%;background:#e5b83b;color:#000;font-size:14px;text-align:center;line-height:22px}"
        ".sel .g a.on img{opacity:.6}#dl{display:none;position:sticky;bottom:0;background:#000;padding:14px;text-align:center}"
        ".sel #dl{display:block}#dl a{color:#e5b83b;text-decoration:none}#dl a.off{color:#555;pointer-events:none}"
        "</style></head><body><h1>SILVER</h1>"];
    [html appendFormat:@"<p>Camera Roll: %d item%@%@. Tap one, then touch and hold it to save it to Photos. "
        "Downloads come as a ZIP.</p>",
        count, count == 1 ? @"" : @"s",
        pages > 1 ? [NSString stringWithFormat:@" (page %d of %d)", page, pages] : @""];
    if (count)
        [html appendFormat:@"<div class=bar><a href='/Silver.zip' download>Download all (%.0f MB)</a>"
            "<button id=sel>Select</button></div>", total / 1048576.0];
    NSMutableString *nav = [NSMutableString stringWithString:@"<nav><span>"];
    if (page > 1) [nav appendFormat:@"<a href='/?page=%d'>&larr; Newer</a>", page - 1];
    [nav appendString:@"</span><span>"];
    if (page < pages) [nav appendFormat:@"<a href='/?page=%d'>Older &rarr;</a>", page + 1];
    [nav appendString:@"</span></nav>"];
    [html appendString:@"<div class=g>"];
    for (int i = (page - 1) * kPerPage; i < count && i < page * kPerPage; i++) {
        NSString *n = [names objectAtIndex:i];
        [html appendFormat:@"<a href='/p/%@' data-n='%@'><img src='/t/%@.jpg' loading=lazy decoding=async></a>", n, n, n];
    }
    [html appendFormat:@"</div>%@<div id=dl><a id=go class=off download>Download 0</a></div><script>"
        "var g=document.querySelector('.g'),b=document.getElementById('sel'),go=document.getElementById('go');"
        "function upd(){var n=[].map.call(g.querySelectorAll('a.on'),function(a){return a.dataset.n});"
        "go.textContent='Download '+n.length;go.href='/Silver.zip?n='+n.join(',');go.className=n.length?'':'off'}"
        "if(b)b.onclick=function(){var on=document.body.classList.toggle('sel');b.textContent=on?'Cancel':'Select';"
        "[].forEach.call(g.querySelectorAll('a.on'),function(a){a.classList.remove('on')});upd()};"
        "g.onclick=function(e){var a=e.target.closest('a');if(!a||!document.body.classList.contains('sel'))return;"
        "e.preventDefault();a.classList.toggle('on');upd()}"
        "</script></body></html>", pages > 1 ? nav : @""];
    return [html dataUsingEncoding:NSUTF8StringEncoding];
}

// A ZIP with stored (uncompressed) entries, streamed one file at a time; JPEGs don't compress.
static void put16(NSMutableData *d, unsigned v) { uint8_t b[2] = {v, v >> 8}; [d appendBytes:b length:2]; }
static void put32(NSMutableData *d, uint32_t v) { uint8_t b[4] = {v, v >> 8, v >> 16, v >> 24}; [d appendBytes:b length:4]; }

static void sendZip(int fd, NSArray *files, BOOL head) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *entries = [NSMutableArray array];
    NSMutableSet *used = [NSMutableSet set];
    unsigned long long length = 22;
    for (NSString *f in files) {
        NSDictionary *a = [fm attributesOfItemAtPath:f error:NULL];
        if (!a) continue;
        NSString *zn = [f lastPathComponent];
        if ([used containsObject:zn])
            zn = [NSString stringWithFormat:@"%@-%@", [[f stringByDeletingLastPathComponent] lastPathComponent], zn];
        [used addObject:zn];
        NSData *name = [zn dataUsingEncoding:NSUTF8StringEncoding];
        time_t t = (time_t)[[a fileModificationDate] timeIntervalSince1970];
        struct tm tm; localtime_r(&t, &tm);
        unsigned dosTime = tm.tm_hour << 11 | tm.tm_min << 5 | tm.tm_sec / 2;
        unsigned dosDate = (tm.tm_year - 80) << 9 | (tm.tm_mon + 1) << 5 | tm.tm_mday;
        [entries addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:f, @"path", name, @"name",
            [NSNumber numberWithUnsignedLongLong:[a fileSize]], @"size",
            [NSNumber numberWithUnsignedInt:dosTime], @"time", [NSNumber numberWithUnsignedInt:dosDate], @"date", nil]];
        length += 30 + 46 + 2 * [name length] + [a fileSize];
    }
    if (![entries count] || length > 0xFFFFFFFFull) {
        sendResponse(fd, 400, "text/plain", [@"Nothing to download, or more than 4 GB. Select fewer.\n"
            dataUsingEncoding:NSUTF8StringEncoding], head, NO);
        return;
    }
    NSString *h = [NSString stringWithFormat:@"HTTP/1.0 200 OK\r\nContent-Type: application/zip\r\nContent-Length: %llu\r\n"
                   "Content-Disposition: attachment; filename=\"Silver.zip\"\r\nCache-Control: no-cache\r\n"
                   "Connection: close\r\n\r\n", length];
    NSData *hd = [h dataUsingEncoding:NSUTF8StringEncoding];
    if (sendAll(fd, [hd bytes], [hd length]) || head) return;
    double t0 = NowMs();
    uint32_t offset = 0;
    for (NSMutableDictionary *e in entries) {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        NSData *data = [NSData dataWithContentsOfFile:[e objectForKey:@"path"]], *name = [e objectForKey:@"name"];
        uint32_t size = (uint32_t)[[e objectForKey:@"size"] unsignedLongLongValue];
        if ([data length] != size) { Log(@"zip: %@ changed, aborting", [e objectForKey:@"path"]); [pool release]; return; }
        uint32_t crc = (uint32_t)crc32(crc32(0, NULL, 0), [data bytes], size);
        [e setObject:[NSNumber numberWithUnsignedInt:crc] forKey:@"crc"];
        [e setObject:[NSNumber numberWithUnsignedInt:offset] forKey:@"offset"];
        NSMutableData *lh = [NSMutableData data];
        put32(lh, 0x04034b50); put16(lh, 10); put16(lh, 0); put16(lh, 0);
        put16(lh, [[e objectForKey:@"time"] unsignedIntValue]); put16(lh, [[e objectForKey:@"date"] unsignedIntValue]);
        put32(lh, crc); put32(lh, size); put32(lh, size); put16(lh, [name length]); put16(lh, 0);
        [lh appendData:name];
        int err = sendAll(fd, [lh bytes], [lh length]) || sendAll(fd, [data bytes], size);
        offset += [lh length] + size;
        [pool release];
        if (err) { Log(@"zip: client went away"); return; }
    }
    NSMutableData *cd = [NSMutableData data];
    for (NSDictionary *e in entries) {
        NSData *name = [e objectForKey:@"name"];
        uint32_t size = (uint32_t)[[e objectForKey:@"size"] unsignedLongLongValue];
        put32(cd, 0x02014b50); put16(cd, 20); put16(cd, 10); put16(cd, 0); put16(cd, 0);
        put16(cd, [[e objectForKey:@"time"] unsignedIntValue]); put16(cd, [[e objectForKey:@"date"] unsignedIntValue]);
        put32(cd, [[e objectForKey:@"crc"] unsignedIntValue]); put32(cd, size); put32(cd, size);
        put16(cd, [name length]); put16(cd, 0); put16(cd, 0); put16(cd, 0); put16(cd, 0); put32(cd, 0);
        put32(cd, [[e objectForKey:@"offset"] unsignedIntValue]);
        [cd appendData:name];
    }
    uint32_t cdSize = [cd length];
    put32(cd, 0x06054b50); put16(cd, 0); put16(cd, 0); put16(cd, [entries count]); put16(cd, [entries count]);
    put32(cd, cdSize); put32(cd, offset); put16(cd, 0);
    sendAll(fd, [cd bytes], [cd length]);
    Log(@"zip: %d files, %u bytes in %.0f ms", (int)[entries count], (unsigned)length, NowMs() - t0);
}

// 240 px thumbnails cached on disk, made one at a time (~0.6 s each) newest first while Share is
// open. Until one exists the page gets the system's 75x75 .THM.
static pthread_mutex_t gThumbLock = PTHREAD_MUTEX_INITIALIZER;

static NSString *thumbCachePath(NSString *name, NSString *source) {
    static NSString *dir;
    if (!dir) {
        dir = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/Silver/thumbs"] retain];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    // Size in the key: file numbers can be reused after a deletion.
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
        if (generation != gWarmGeneration) break;
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
    char buf[8192]; size_t used = 0;
    while (used < sizeof buf - 1) {
        ssize_t n = read(fd, buf + used, sizeof buf - 1 - used);
        if (n <= 0) break;
        used += n; buf[used] = 0;
        if (strstr(buf, "\r\n\r\n") || strstr(buf, "\n\n")) break;
    }
    buf[used] = 0;
    char method[8] = "", path[8192] = "";
    if (sscanf(buf, "%7s %8191s", method, path) != 2 || (strcmp(method, "GET") && strcmp(method, "HEAD"))) {
        sendResponse(fd, 400, "text/plain", [NSData dataWithBytes:"bad request\n" length:12], NO, NO);
    } else {
        BOOL head = !strcmp(method, "HEAD"), cacheable = NO;
        NSString *p = [NSString stringWithUTF8String:path];
        NSData *body = nil; const char *type = "image/jpeg";
        if ([p isEqualToString:@"/Silver.zip"] || [p hasPrefix:@"/Silver.zip?n="]) {
            NSDictionary *paths;
            NSArray *names = photoNames(&paths);
            if ([p hasPrefix:@"/Silver.zip?n="]) names = [[p substringFromIndex:14] componentsSeparatedByString:@","];
            NSMutableArray *files = [NSMutableArray array];
            for (NSString *n in names) if ([paths objectForKey:n]) [files addObject:[paths objectForKey:n]];
            Log(@"http %s /Silver.zip (%d files)", method, (int)[files count]);
            sendZip(fd, files, head);
            close(fd);
            [pool release];
            return NULL;
        }
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

// One thread per connection, so a slow thumbnail doesn't hold up the rest.
static void *serve(void *arg) {
    int lfd = (int)(intptr_t)arg;
    for (;;) {
        int fd = accept(lfd, NULL, NULL);
        if (fd < 0) break;
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
    gWarmGeneration++;
    shutdown(listenFd, SHUT_RDWR);
    close(listenFd);
    running = NO;
    Log(@"share server stopped");
}

@end
