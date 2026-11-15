#import <UIKit/UIKit.h>

UIColor *GoldColor(void);
// Letter spacing by hand: UIKit on 3.x has no kerning.
CGFloat DrawSpaced(NSString *text, CGPoint at, UIFont *font, CGFloat spacing);
CGFloat SpacedWidth(NSString *text, UIFont *font, CGFloat spacing);

@interface ShutterButton : UIControl
@end

@interface TextButton : UIControl {
    NSString *title; BOOL left;
}
- (id)initWithFrame:(CGRect)frame title:(NSString *)title;
- (void)setLeftAligned:(BOOL)l;
- (void)setTitle:(NSString *)t;
@end

@interface FilmCard : UIControl {
    int index;
}
- (void)setIndex:(int)i;
@end

typedef enum { kIconGrid, kIconShare } IconKind;
@interface IconButton : UIControl {
    IconKind kind; BOOL on;
}
- (id)initWithFrame:(CGRect)frame kind:(IconKind)kind;
- (void)setOn:(BOOL)on;
@end

@interface ThumbButton : UIControl {
    UIImage *image;
}
- (void)setImage:(UIImage *)i;
@end

@interface GridView : UIView
@end

@interface QRView : UIView {
    uint8_t *qr;
}
- (void)setText:(NSString *)text;
@end

// Sends action after a 1.5 s touch and hold.
@interface HoldView : UIView {
    id target; SEL action;
}
- (id)initWithFrame:(CGRect)frame target:(id)target action:(SEL)action;
@end
