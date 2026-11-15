// Silver: a black-and-white camera for the original iPhone (iPhone OS 3.1.3).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "Camera.h"
#import "Film.h"
#import "Log.h"
#import "Private.h"
#import "Develop.h"
#import "ShareServer.h"
#import "Views.h"
#import "CameraRoll.h"

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
    UINavigationController *roll;
    Camera *camera;
    ShareServer *server;
    int stock;
    BOOL developing;
    float shutterMean;
}
@end

@interface App (Private)
- (void)developed:(NSDictionary *)result;
- (void)closeRoll;
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
    [thumb setImage:[CameraRoll wellImage]];
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
    [thumb addTarget:self action:@selector(openRoll) forControlEvents:UIControlEventTouchUpInside];
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
    [self closeRoll];
    if (!shareView) [self buildShareView];
    NSString *ip = [ShareServer wifiAddress];
    NSUInteger count = [[CameraRoll photoPaths] count];
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

- (void)openRoll {
    [roll release];
    roll = [[CameraRoll navigationControllerWithDoneTarget:self action:@selector(closeRoll)] retain];
    if (!roll) return;
    // The Photos UI is laid out full screen under a translucent status bar (that's what it
    // switches to on appearing). Show the status bar before the navigation bar lays out so it
    // sits below it, as in the Photos app.
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackTranslucent animated:NO];
    [[UIApplication sharedApplication] setStatusBarHidden:NO animated:NO];
    roll.view.frame = CGRectMake(0, 0, 320, 480);
    [roll viewWillAppear:NO];
    [window addSubview:roll.view];
    [roll viewDidAppear:NO];
}

- (void)closeRoll {
    if (!roll) return;
    [roll viewWillDisappear:NO];
    [roll.view removeFromSuperview];
    [roll viewDidDisappear:NO];
    [roll release]; roll = nil;
    [[UIApplication sharedApplication] setStatusBarHidden:YES animated:NO];
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
    [Develop develop:jpeg stock:&kFilmStocks[stock] previewMean:shutterMean target:self action:@selector(developed:)];
}

- (void)developed:(NSDictionary *)result {
    developing = NO;
    shutter.enabled = YES;
    BOOL ok = result && [CameraRoll saveJPEG:[result objectForKey:@"jpeg"] image:[result objectForKey:@"image"]
                                     preview:[result objectForKey:@"preview"]];
    [self showStatus:ok ? nil : @"PHOTO FAILED"];
    if (!ok) { [self performSelector:@selector(showStatus:) withObject:nil afterDelay:2]; return; }
    [thumb setImage:[result objectForKey:@"preview"]];
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
// silver://stock, silver://roll, silver://rollphoto, silver://unroll, silver://screenshot.
- (BOOL)application:(UIApplication *)app handleOpenURL:(NSURL *)url {
    NSString *cmd = [url host];
    Log(@"url command %@", cmd);
    if ([cmd isEqualToString:@"shutter"]) [self shoot];
    else if ([cmd isEqualToString:@"share"]) [self openShare];
    else if ([cmd isEqualToString:@"unshare"]) [self closeShare];
    else if ([cmd isEqualToString:@"grid"]) [self toggleGrid];
    else if ([cmd isEqualToString:@"stock"]) [self nextStock];
    else if ([cmd isEqualToString:@"roll"]) [self openRoll];
    else if ([cmd isEqualToString:@"rollphoto"]) [CameraRoll showNewestIn:roll];
    else if ([cmd isEqualToString:@"unroll"]) [self closeRoll];
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
