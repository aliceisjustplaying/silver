#import <UIKit/UIKit.h>

// Full-screen photo viewer. Opens instantly with the 400x533 screen copy, swaps in the
// full 1200x1600 photo (decoded on a background thread) when you zoom in.
// Pinch or double-tap to zoom; single tap closes.
@interface Viewer : UIView <UIScrollViewDelegate> {
    UIScrollView *scroll;
    UIImageView *imageView;
    NSString *name;
    BOOL fullLoaded, fullLoading;
    id closeTarget; SEL closeAction;
}
- (id)initWithFrame:(CGRect)frame closeTarget:(id)target action:(SEL)action;
- (void)showPhoto:(NSString *)name;
@end
