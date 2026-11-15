#import <UIKit/UIKit.h>

UIColor *GoldColor(void);
// Draws text with extra letter spacing (UIKit on 3.x has no kerning API). Returns the width drawn.
CGFloat DrawSpaced(NSString *text, CGPoint at, UIFont *font, CGFloat spacing);
CGFloat SpacedWidth(NSString *text, UIFont *font, CGFloat spacing);

// The gold moon shutter.
@interface ShutterButton : UIControl
@end

// Letter-spaced text button.
@interface TextButton : UIControl {
    NSString *title; BOOL on;
}
- (id)initWithFrame:(CGRect)frame title:(NSString *)title;
- (void)setTitle:(NSString *)t;
- (void)setOn:(BOOL)on;   // shown in gold
@end

// Film stock card: tap to change stock. Shows the stock's symbol and number, tarot style.
@interface FilmCard : UIControl {
    int index;
}
- (void)setIndex:(int)i;
@end

// Line-drawn icon button.
typedef enum { kIconGrid, kIconShare } IconKind;
@interface IconButton : UIControl {
    IconKind kind; BOOL on;
}
- (id)initWithFrame:(CGRect)frame kind:(IconKind)kind;
- (void)setOn:(BOOL)on;   // shown in gold
@end

// Last-photo thumbnail.
@interface ThumbButton : UIControl {
    UIImage *image;
}
- (void)setImage:(UIImage *)i;
@end

// Rule-of-thirds grid.
@interface GridView : UIView
@end

// QR code drawn from a qrcodegen buffer.
@interface QRView : UIView {
    uint8_t *qr;
}
- (void)setText:(NSString *)text;
@end
