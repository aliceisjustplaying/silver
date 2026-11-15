#import "ShareServer.h"
#import "Roll.h"
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

static void sendResponse(int fd, int status, const char *type, NSData *body, BOOL head) {
    const char *reason = status == 200 ? "OK" : status == 404 ? "Not Found" : "Bad Request";
    NSString *h = [NSString stringWithFormat:@"HTTP/1.0 %d %s\r\nContent-Type: %s\r\nContent-Length: %lu\r\n"
                   "Cache-Control: no-cache\r\nConnection: close\r\n\r\n", status, reason, type, (unsigned long)[body length]];
    NSData *hd = [h dataUsingEncoding:NSUTF8StringEncoding];
    sendAll(fd, [hd bytes], [hd length]);
    if (!head) sendAll(fd, [body bytes], [body length]);
}

static NSData *galleryPage(void) {
    NSArray *names = [Roll photoNames];
    NSMutableString *html = [NSMutableString stringWithString:
        @"<!doctype html><html><head><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'><title>Silver</title><style>"
        "body{margin:0;background:#000;color:#ddd;font:15px -apple-system,Helvetica,sans-serif}"
        "h1{font-weight:400;letter-spacing:.3em;font-size:15px;margin:18px 14px 4px;color:#e5b83b}"
        "p{margin:0 14px 14px;color:#888}"
        ".g{display:grid;grid-template-columns:repeat(3,1fr);gap:2px}"
        ".g a{display:block;aspect-ratio:3/4;background:#111}"
        ".g img{width:100%;height:100%;object-fit:cover;display:block}"
        "</style></head><body><h1>SILVER</h1>"];
    [html appendFormat:@"<p>%lu photo%@. Tap one, then touch and hold it to save it to Photos.</p><div class=g>",
        (unsigned long)[names count], [names count] == 1 ? @"" : @"s"];
    for (NSString *n in names)
        [html appendFormat:@"<a href='/p/%@.jpg'><img src='/t/%@.jpg' loading=lazy></a>", n, n];
    [html appendString:@"</div></body></html>"];
    return [html dataUsingEncoding:NSUTF8StringEncoding];
}

static void handle(int fd) {
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
        sendResponse(fd, 400, "text/plain", [NSData dataWithBytes:"bad request\n" length:12], NO);
    } else {
        BOOL head = !strcmp(method, "HEAD");
        NSString *p = [NSString stringWithUTF8String:path];
        NSData *body = nil; const char *type = "image/jpeg";
        if ([p isEqualToString:@"/"]) {
            body = galleryPage(); type = "text/html; charset=utf-8";
        } else if (([p hasPrefix:@"/p/"] || [p hasPrefix:@"/t/"]) && [p hasSuffix:@".jpg"]) {
            NSString *name = [[p substringFromIndex:3] stringByDeletingPathExtension];
            if ([[Roll photoNames] containsObject:name])     // only names we wrote: no path traversal
                body = [NSData dataWithContentsOfFile:[p hasPrefix:@"/p/"] ? [Roll pathForPhoto:name] : [Roll pathForThumb:name]];
        }
        if (body) sendResponse(fd, 200, type, body, head);
        else sendResponse(fd, 404, "text/plain", [NSData dataWithBytes:"not found\n" length:10], head);
        Log(@"http %s %s -> %d", method, path, body ? 200 : 404);
    }
    close(fd);
    [pool release];
}

static void *serve(void *arg) {
    int lfd = (int)(intptr_t)arg;
    for (;;) {
        int fd = accept(lfd, NULL, NULL);
        if (fd < 0) break;                                  // listening socket closed: stop
        struct timeval tv = {5, 0};
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
        int one = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        handle(fd);
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
    running = YES;
    Log(@"share server listening on %d", port);
    return YES;
}

- (void)stop {
    if (!running) return;
    shutdown(listenFd, SHUT_RDWR);
    close(listenFd);
    running = NO;
    Log(@"share server stopped");
}

@end
