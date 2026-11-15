#import "Viewer.h"
#import "Roll.h"
#import "Log.h"

// Keeps the zoomed view centered when it is smaller than the screen
// (iPhone OS 3.1 has no scrollViewDidZoom:).
@interface CenteringScrollView : UIScrollView
@end
@implementation CenteringScrollView
- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *v = [self.delegate viewForZoomingInScrollView:self];
    CGRect f = v.frame; CGSize b = self.bounds.size;
    f.origin.x = f.size.width < b.width ? (b.width - f.size.width) / 2 : 0;
    f.origin.y = f.size.height < b.height ? (b.height - f.size.height) / 2 : 0;
    v.frame = f;
}
@end

// Image view that reports single and double taps (no gesture recognizers before 3.2).
@interface TapImageView : UIImageView
@end
@implementation TapImageView
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    Viewer *viewer = (Viewer *)self.superview.superview;
    if ([touches count] != 1 || [[event allTouches] count] != 1) return;
    if (t.tapCount == 1) [viewer performSelector:@selector(singleTap) withObject:nil afterDelay:0.3];
    else if (t.tapCount == 2) {
        [NSObject cancelPreviousPerformRequestsWithTarget:viewer selector:@selector(singleTap) object:nil];
        [viewer performSelector:@selector(doubleTapAt:) withObject:[NSValue valueWithCGPoint:[t locationInView:self]]];
    }
}
@end

static UIImage *decoded(NSString *path) {
    // Decode now (UIImage decodes lazily on first draw, which made opening slow).
    CGDataProviderRef dp = CGDataProviderCreateWithFilename([path fileSystemRepresentation]);
    if (!dp) return nil;
    CGImageRef jpg = CGImageCreateWithJPEGDataProvider(dp, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(dp);
    if (!jpg) return nil;
    size_t w = CGImageGetWidth(jpg), h = CGImageGetHeight(jpg), rb = (w + 15) & ~15;
    void *px = malloc(rb * h);
    CGColorSpaceRef gs = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, rb, gs, kCGImageAlphaNone);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), jpg);
    CGImageRelease(jpg);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx); CGColorSpaceRelease(gs);
    UIImage *u = [UIImage imageWithCGImage:img];
    CGImageRelease(img);
    free(px);
    return u;
}

@implementation Viewer

- (id)initWithFrame:(CGRect)f closeTarget:(id)target action:(SEL)action {
    if ((self = [super initWithFrame:f])) {
        closeTarget = target; closeAction = action;
        self.backgroundColor = [UIColor blackColor];
        scroll = [[CenteringScrollView alloc] initWithFrame:self.bounds];
        scroll.delegate = self;
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4;
        scroll.showsHorizontalScrollIndicator = scroll.showsVerticalScrollIndicator = NO;
        scroll.bouncesZoom = YES;
        [self addSubview:scroll];
        // 3:4 photo fitted to the 320-wide screen
        imageView = [[TapImageView alloc] initWithFrame:CGRectMake(0, 0, 320, 427)];
        imageView.userInteractionEnabled = YES;
        [scroll addSubview:imageView];
        scroll.contentSize = imageView.frame.size;
    }
    return self;
}

- (void)dealloc { [scroll release]; [imageView release]; [name release]; [super dealloc]; }

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)s { return imageView; }

- (void)showPhoto:(NSString *)n {
    double t0 = NowMs();
    [name release]; name = [n copy];
    fullLoaded = fullLoading = NO;
    scroll.zoomScale = 1;
    imageView.image = decoded([Roll pathForScreen:n]) ?: decoded([Roll pathForPhoto:n]);
    [scroll setNeedsLayout];
    Log(@"viewer opened %@ in %.0f ms", n, NowMs() - t0);
}

- (void)loadFull {
    if (fullLoaded || fullLoading) return;
    fullLoading = YES;
    [NSThread detachNewThreadSelector:@selector(loadFullThread:) toTarget:self withObject:[[name copy] autorelease]];
}

- (void)loadFullThread:(NSString *)n {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    double t0 = NowMs();
    UIImage *full = decoded([Roll pathForPhoto:n]);
    Log(@"viewer full-size decode %.0f ms", NowMs() - t0);
    [self performSelectorOnMainThread:@selector(fullLoaded:) withObject:[NSArray arrayWithObjects:n, full, nil] waitUntilDone:NO];
    [pool release];
}

- (void)fullLoaded:(NSArray *)a {
    fullLoading = NO;
    if ([a count] < 2 || ![[a objectAtIndex:0] isEqualToString:name] || !self.superview) return;
    imageView.image = [a objectAtIndex:1];
    fullLoaded = YES;
}

- (void)scrollViewDidEndZooming:(UIScrollView *)s withView:(UIView *)v atScale:(float)scale {
    if (scale > 1.05f) [self loadFull];
}

- (void)singleTap {
    [closeTarget performSelector:closeAction];
}

- (void)doubleTapAt:(NSValue *)p {
    if (scroll.zoomScale > 1.05f) { [scroll setZoomScale:1 animated:YES]; return; }
    CGPoint c = [p CGPointValue];
    CGFloat z = 3;
    CGSize s = CGSizeMake(scroll.bounds.size.width / z, scroll.bounds.size.height / z);
    [scroll zoomToRect:CGRectMake(c.x - s.width / 2, c.y - s.height / 2, s.width, s.height) animated:YES];
    [self loadFull];
}

@end
