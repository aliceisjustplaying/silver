// Silver: a black-and-white camera for the original iPhone (iPhone OS 3.1.3).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "Camera.h"
#import "Film.h"
#import "Log.h"
#import "Private.h"
#import "Roll.h"
#import "ShareServer.h"
#import "Views.h"
#import "Viewer.h"

enum { kSharePort = 8080 };

@interface App : NSObject <UIApplicationDelegate, CameraDelegate> {
    UIWindow *window;
    UIView *preview;
    GridView *grid;
    UIView *flash;
    UILabel *status;
    ShutterButton *shutter;
    ThumbButton *thumb;
    FilmCard *card;
    IconButton *gridButton, *shareButton;
    TextButton *stockLabel;
    UIView *shareView; QRView *qr; UILabel *shareURL, *shareInfo;
    Viewer *viewer;
    Camera *camera;
    ShareServer *server;
    int stock;
    BOOL developing;
    float shutterMean;
}
@end

@interface App (Private)
- (void)developed:(NSString *)name;
- (void)closeViewer;
@end

@implementation App

- (void)showStatus:(NSString *)text {
    status.text = text;
    status.hidden = text == nil;
}

- (void)applyStock {
    const FilmStock *f = &kFilmStocks[stock];
    uint32_t table[256];
    FilmPreviewTable(f, table);
    [camera setPreviewTable:table];
    NSString *name = [NSString stringWithUTF8String:f->name];
    [card setIndex:stock];
    [stockLabel setTitle:name];
    [[NSUserDefaults standardUserDefaults] setInteger:stock forKey:@"stock"];
}

- (void)loadThumb {
    NSArray *names = [Roll photoNames];
    [thumb setImage:[names count] ? [UIImage imageWithContentsOfFile:[Roll pathForThumb:[names objectAtIndex:0]]] : nil];
}

- (void)buildUI {
    window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    window.backgroundColor = [UIColor blackColor];

    preview = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 421)];
    preview.backgroundColor = [UIColor blackColor];
    preview.layer.contentsGravity = kCAGravityResize;
    [window addSubview:preview];
    grid = [[GridView alloc] initWithFrame:preview.frame];
    grid.hidden = ![[NSUserDefaults standardUserDefaults] boolForKey:@"grid"];
    [window addSubview:grid];
    flash = [[UIView alloc] initWithFrame:preview.frame];
    flash.backgroundColor = [UIColor whiteColor]; flash.alpha = 0; flash.userInteractionEnabled = NO;
    [window addSubview:flash];

    UIView *top = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 30)] autorelease];
    top.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35f];
    [window addSubview:top];
    stockLabel = [[TextButton alloc] initWithFrame:CGRectMake(4, 0, 210, 30) title:@""];
    [stockLabel setLeftAligned:YES];
    [stockLabel addTarget:self action:@selector(nextStock) forControlEvents:UIControlEventTouchUpInside];
    [top addSubview:stockLabel];
    gridButton = [[IconButton alloc] initWithFrame:CGRectMake(232, 0, 40, 30) kind:kIconGrid];
    [gridButton setOn:!grid.hidden];
    [gridButton addTarget:self action:@selector(toggleGrid) forControlEvents:UIControlEventTouchUpInside];
    [top addSubview:gridButton];
    shareButton = [[IconButton alloc] initWithFrame:CGRectMake(276, 0, 40, 30) kind:kIconShare];
    [shareButton addTarget:self action:@selector(openShare) forControlEvents:UIControlEventTouchUpInside];
    [top addSubview:shareButton];

    status = [[UILabel alloc] initWithFrame:CGRectMake(60, 40, 200, 22)];
    status.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6f];
    status.textColor = GoldColor(); status.font = [UIFont systemFontOfSize:12];
    status.textAlignment = UITextAlignmentCenter; status.hidden = YES;
    [window addSubview:status];

    UIView *bottom = [[[UIView alloc] initWithFrame:CGRectMake(0, 421, 320, 59)] autorelease];
    bottom.backgroundColor = [UIColor blackColor];
    [window addSubview:bottom];
    thumb = [[ThumbButton alloc] initWithFrame:CGRectMake(20, 428, 33, 44)];   // 3:4 like the photos
    [thumb addTarget:self action:@selector(openViewer) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:thumb];
    card = [[FilmCard alloc] initWithFrame:CGRectMake(272, 427, 32, 46)];
    [card addTarget:self action:@selector(nextStock) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:card];
    shutter = [[ShutterButton alloc] initWithFrame:CGRectMake(136, 427, 48, 48)];
    [shutter addTarget:self action:@selector(shoot) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:shutter];

    [window makeKeyAndVisible];
}

- (void)buildShareView {
    shareView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    shareView.backgroundColor = [UIColor blackColor];
    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(0, 24, 320, 24)] autorelease];
    title.text = @"S H A R E"; title.textColor = GoldColor(); title.backgroundColor = [UIColor clearColor];
    title.textAlignment = UITextAlignmentCenter; title.font = [UIFont systemFontOfSize:15];
    [shareView addSubview:title];
    qr = [[QRView alloc] initWithFrame:CGRectMake(50, 64, 220, 220)];
    [shareView addSubview:qr];
    shareURL = [[UILabel alloc] initWithFrame:CGRectMake(0, 296, 320, 24)];
    shareURL.textColor = [UIColor whiteColor]; shareURL.backgroundColor = [UIColor clearColor];
    shareURL.textAlignment = UITextAlignmentCenter; shareURL.font = [UIFont boldSystemFontOfSize:16];
    [shareView addSubview:shareURL];
    shareInfo = [[UILabel alloc] initWithFrame:CGRectMake(24, 324, 272, 90)];
    shareInfo.textColor = [UIColor grayColor]; shareInfo.backgroundColor = [UIColor clearColor];
    shareInfo.textAlignment = UITextAlignmentCenter; shareInfo.font = [UIFont systemFontOfSize:13];
    shareInfo.numberOfLines = 0;
    [shareView addSubview:shareInfo];
    TextButton *done = [[[TextButton alloc] initWithFrame:CGRectMake(110, 424, 100, 40) title:@"DONE"] autorelease];
    [done addTarget:self action:@selector(closeShare) forControlEvents:UIControlEventTouchUpInside];
    [shareView addSubview:done];
}

- (void)openShare {
    [self closeViewer];
    if (!shareView) [self buildShareView];
    NSString *ip = [ShareServer wifiAddress];
    NSUInteger count = [[Roll photoNames] count];
    if (ip && [server startOnPort:kSharePort]) {
        NSString *url = [NSString stringWithFormat:@"http://%@:%d/", ip, kSharePort];
        [qr setText:url]; qr.hidden = NO;
        shareURL.text = [url substringWithRange:NSMakeRange(7, [url length] - 8)];
        shareInfo.text = [NSString stringWithFormat:@"%lu photo%@. Scan with another phone's camera. "
                          "Both phones need the same Wi-Fi, or join that phone's Personal Hotspot.",
                          (unsigned long)count, count == 1 ? @"" : @"s"];
    } else {
        qr.hidden = YES; shareURL.text = @"No Wi-Fi";
        shareInfo.text = @"Join a Wi-Fi network (or another phone's Personal Hotspot) to share photos.";
    }
    [window addSubview:shareView];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

- (void)closeShare {
    [server stop];
    [shareView removeFromSuperview];
}

- (void)toggleGrid {
    grid.hidden = !grid.hidden;
    [gridButton setOn:!grid.hidden];
    [[NSUserDefaults standardUserDefaults] setBool:!grid.hidden forKey:@"grid"];
}

- (void)nextStock {
    stock = (stock + 1) % kFilmStockCount;
    [self applyStock];
}

- (void)openViewer {
    NSArray *names = [Roll photoNames];
    if (![names count]) return;
    if (!viewer) viewer = [[Viewer alloc] initWithFrame:CGRectMake(0, 0, 320, 480) closeTarget:self action:@selector(closeViewer)];
    [viewer showPhoto:[names objectAtIndex:0]];
    [window addSubview:viewer];
}

- (void)closeViewer {
    [viewer removeFromSuperview];
}

- (void)shoot {
    if (developing || ![camera takePhoto]) return;
    developing = YES;
    shutterMean = camera->previewMean;
    shutter.enabled = NO;
    flash.alpha = 0.9f;
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.35];
    flash.alpha = 0;
    [UIView commitAnimations];
    [self showStatus:@"DEVELOPING"];
}

- (void)camera:(Camera *)c tookPhoto:(NSData *)jpeg {
    if (!jpeg) { [self developed:nil]; return; }
    [Roll develop:jpeg stock:&kFilmStocks[stock] previewMean:shutterMean target:self action:@selector(developed:)];
}

- (void)developed:(NSString *)name {
    developing = NO;
    shutter.enabled = YES;
    [self showStatus:name ? nil : @"PHOTO FAILED"];
    if (!name) { [self performSelector:@selector(showStatus:) withObject:nil afterDelay:2]; return; }
    [self loadThumb];
    // Also put a copy in the Camera Roll.
    UIImageWriteToSavedPhotosAlbum([UIImage imageWithContentsOfFile:[Roll pathForPhoto:name]], nil, NULL, NULL);
}

- (void)cameraFailed:(Camera *)c reason:(NSString *)reason {
    Log(@"camera failed: %@", reason);
    [self showStatus:[reason uppercaseString]];
}

- (void)screenshot {
    CGImageRef img = UIGetScreenImage();
    [UIImagePNGRepresentation([UIImage imageWithCGImage:img]) writeToFile:@"/tmp/silver-screen.png" atomically:YES];
    CGImageRelease(img);
    Log(@"screenshot saved");
}

// Development hooks: silver://shutter, silver://share, silver://unshare, silver://grid,
// silver://stock, silver://viewer, silver://zoom (double-tap the viewer's center), silver://screenshot.
- (BOOL)application:(UIApplication *)app handleOpenURL:(NSURL *)url {
    NSString *cmd = [url host];
    Log(@"url command %@", cmd);
    if ([cmd isEqualToString:@"shutter"]) [self shoot];
    else if ([cmd isEqualToString:@"share"]) [self openShare];
    else if ([cmd isEqualToString:@"unshare"]) [self closeShare];
    else if ([cmd isEqualToString:@"grid"]) [self toggleGrid];
    else if ([cmd isEqualToString:@"stock"]) [self nextStock];
    else if ([cmd isEqualToString:@"viewer"]) [self openViewer];
    else if ([cmd isEqualToString:@"zoom"]) [viewer performSelector:@selector(doubleTapAt:) withObject:[NSValue valueWithCGPoint:CGPointMake(160, 213)]];
    else if ([cmd isEqualToString:@"screenshot"]) [self performSelector:@selector(screenshot) withObject:nil afterDelay:0.5];
    return YES;
}

- (void)applicationDidFinishLaunching:(UIApplication *)app {
    Log(@"launch");
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    server = [[ShareServer alloc] init];
    stock = [[NSUserDefaults standardUserDefaults] integerForKey:@"stock"] % kFilmStockCount;
    [self buildUI];
    camera = [[Camera alloc] initWithLayer:preview.layer delegate:self];
    [self applyStock];
    [self loadThumb];
    [camera start];
}

- (void)applicationWillTerminate:(UIApplication *)app {
    [server stop];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    int r = UIApplicationMain(argc, argv, nil, @"App");
    [pool release];
    return r;
}
