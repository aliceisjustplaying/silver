#import "Views.h"
#include "qrcodegen.h"

UIColor *GoldColor(void) { return [UIColor colorWithRed:0.90f green:0.72f blue:0.23f alpha:1]; }

CGFloat SpacedWidth(NSString *text, UIFont *font, CGFloat spacing) {
    CGFloat w = 0;
    for (NSUInteger i = 0; i < [text length]; i++)
        w += [[text substringWithRange:NSMakeRange(i, 1)] sizeWithFont:font].width + spacing;
    return [text length] ? w - spacing : 0;
}

CGFloat DrawSpaced(NSString *text, CGPoint at, UIFont *font, CGFloat spacing) {
    CGFloat x = at.x;
    for (NSUInteger i = 0; i < [text length]; i++) {
        NSString *c = [text substringWithRange:NSMakeRange(i, 1)];
        x += [c drawAtPoint:CGPointMake(x, at.y) withFont:font].width + spacing;
    }
    return x - at.x - spacing;
}

@implementation ShutterButton
- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.opaque = NO; self.backgroundColor = [UIColor clearColor]; }
    return self;
}
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)setEnabled:(BOOL)e { [super setEnabled:e]; [self setNeedsDisplay]; }
// A thin gold ring around a flat gold crescent moon.
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    float k = (self.highlighted || !self.enabled) ? 0.5f : 1.0f;
    CGContextSetRGBStrokeColor(c, 0.90f * k, 0.72f * k, 0.23f * k, 1);
    CGContextSetRGBFillColor(c, 0.90f * k, 0.72f * k, 0.23f * k, 1);
    CGContextSetLineWidth(c, 1.5f);
    CGContextStrokeEllipseInRect(c, CGRectInset(self.bounds, 1, 1));
    CGRect moon = CGRectInset(self.bounds, 6, 6);
    CGFloat d = moon.size.width;
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, moon); CGContextClip(c);     // clipping consumes the path
    CGContextAddEllipseInRect(c, moon);
    CGContextAddEllipseInRect(c, CGRectOffset(moon, d * 0.30f, -d * 0.22f));
    CGContextEOFillPath(c);                                    // disk minus offset disk = crescent
    CGContextRestoreGState(c);
}
@end

@implementation TextButton
- (id)initWithFrame:(CGRect)f title:(NSString *)t {
    if ((self = [super initWithFrame:f])) { title = [t copy]; self.opaque = NO; self.backgroundColor = [UIColor clearColor]; }
    return self;
}
- (void)dealloc { [title release]; [super dealloc]; }
- (void)setTitle:(NSString *)t { [title release]; title = [t copy]; [self setNeedsDisplay]; }
- (void)setOn:(BOOL)o { on = o; [self setNeedsDisplay]; }
- (void)setLeftAligned:(BOOL)l { left = l; [self setNeedsDisplay]; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    UIFont *f = [UIFont systemFontOfSize:12];
    [(on || self.highlighted ? GoldColor() : [UIColor whiteColor]) set];
    CGFloat w = SpacedWidth(title, f, 3);
    DrawSpaced(title, CGPointMake(left ? 10 : (self.bounds.size.width - w) / 2, (self.bounds.size.height - 15) / 2), f, 3);
}
@end

@implementation FilmCard
- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.opaque = NO; self.backgroundColor = [UIColor clearColor]; }
    return self;
}
- (void)setIndex:(int)i { index = i; [self setNeedsDisplay]; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    float k = self.highlighted ? 0.6f : 1.0f;
    CGRect card = CGRectInset(self.bounds, 1, 1);
    CGContextSetRGBFillColor(c, 0.90f * k, 0.72f * k, 0.23f * k, 1);
    CGContextFillRect(c, card);
    const float ink[3] = {0.10f, 0.09f, 0.16f};
    CGContextSetRGBStrokeColor(c, ink[0], ink[1], ink[2], 1);
    CGContextSetRGBFillColor(c, ink[0], ink[1], ink[2], 1);
    CGContextSetLineWidth(c, 1);
    CGContextStrokeRect(c, CGRectInset(card, 2.5f, 2.5f));
    CGPoint m = CGPointMake(CGRectGetMidX(card), card.origin.y + card.size.height * 0.40f);
    CGContextSetLineWidth(c, 1.2f);
    if (index == 0) {                                   // I: sun
        CGContextFillEllipseInRect(c, CGRectMake(m.x - 4, m.y - 4, 8, 8));
        for (int i = 0; i < 12; i++) {
            float a = i * (float)M_PI / 6;
            CGContextMoveToPoint(c, m.x + cosf(a) * 6, m.y + sinf(a) * 6);
            CGContextAddLineToPoint(c, m.x + cosf(a) * 9, m.y + sinf(a) * 9);
        }
        CGContextStrokePath(c);
    } else if (index == 2) {                            // III: new moon (a full dark disk)
        CGContextFillEllipseInRect(c, CGRectMake(m.x - 7, m.y - 7, 14, 14));
    } else {                                            // II: ash haze (three wavy lines)
        for (int l = -1; l <= 1; l++) {
            CGFloat y = m.y + l * 5;
            CGContextMoveToPoint(c, m.x - 9, y);
            CGContextAddCurveToPoint(c, m.x - 5, y - 3, m.x - 1, y + 3, m.x + 2, y);
            CGContextAddCurveToPoint(c, m.x + 5, y - 3, m.x + 8, y + 1, m.x + 9, y);
        }
        CGContextStrokePath(c);
    }
    static NSString *const numerals[] = {@"I", @"II", @"III", @"IV", @"V"};
    NSString *num = numerals[index % 5];
    UIFont *f = [UIFont systemFontOfSize:8];
    [[UIColor colorWithRed:ink[0] green:ink[1] blue:ink[2] alpha:1] set];
    CGFloat w = SpacedWidth(num, f, 1);
    DrawSpaced(num, CGPointMake(m.x - w / 2, card.origin.y + card.size.height - 15), f, 1);
}
@end

@implementation IconButton
- (id)initWithFrame:(CGRect)f kind:(IconKind)k {
    if ((self = [super initWithFrame:f])) { kind = k; self.opaque = NO; self.backgroundColor = [UIColor clearColor]; }
    return self;
}
- (void)setOn:(BOOL)o { on = o; [self setNeedsDisplay]; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    if (on || self.highlighted) CGContextSetRGBStrokeColor(c, 0.90f, 0.72f, 0.23f, 1);
    else CGContextSetRGBStrokeColor(c, 1, 1, 1, 1);
    CGContextSetLineWidth(c, 1.2f);
    CGPoint m = CGPointMake(floorf(CGRectGetMidX(self.bounds)) + 0.5f, floorf(CGRectGetMidY(self.bounds)) + 0.5f);
    if (kind == kIconGrid) {                            // 3x3 grid in a 15 px square
        CGRect sq = CGRectMake(m.x - 7.5f, m.y - 7.5f, 15, 15);
        CGContextStrokeRect(c, sq);
        for (int i = 1; i < 3; i++) {
            CGContextMoveToPoint(c, sq.origin.x + i * 5, sq.origin.y); CGContextAddLineToPoint(c, sq.origin.x + i * 5, sq.origin.y + 15);
            CGContextMoveToPoint(c, sq.origin.x, sq.origin.y + i * 5); CGContextAddLineToPoint(c, sq.origin.x + 15, sq.origin.y + i * 5);
        }
        CGContextStrokePath(c);
    } else {                                            // box with an up arrow
        CGContextMoveToPoint(c, m.x - 3, m.y - 3);
        CGContextAddLineToPoint(c, m.x - 7, m.y - 3);
        CGContextAddLineToPoint(c, m.x - 7, m.y + 8);
        CGContextAddLineToPoint(c, m.x + 7, m.y + 8);
        CGContextAddLineToPoint(c, m.x + 7, m.y - 3);
        CGContextAddLineToPoint(c, m.x + 3, m.y - 3);
        CGContextMoveToPoint(c, m.x, m.y + 3); CGContextAddLineToPoint(c, m.x, m.y - 9);
        CGContextMoveToPoint(c, m.x - 3.5f, m.y - 5.5f); CGContextAddLineToPoint(c, m.x, m.y - 9);
        CGContextAddLineToPoint(c, m.x + 3.5f, m.y - 5.5f);
        CGContextStrokePath(c);
    }
}
@end

@implementation ThumbButton
- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.opaque = NO; self.backgroundColor = [UIColor clearColor]; }
    return self;
}
- (void)dealloc { [image release]; [super dealloc]; }
- (void)setImage:(UIImage *)i { [image release]; image = [i retain]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    if (!image) return;
    CGRect b = CGRectInset(self.bounds, 1, 1);
    [image drawInRect:b];
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetRGBStrokeColor(c, 1, 1, 1, self.highlighted ? 0.5f : 1);
    CGContextSetLineWidth(c, 1.5f);
    CGContextStrokeRect(c, b);
}
@end

@implementation GridView
- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.opaque = NO; self.backgroundColor = [UIColor clearColor]; self.userInteractionEnabled = NO; }
    return self;
}
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetRGBStrokeColor(c, 1, 1, 1, 0.45f);
    CGContextSetLineWidth(c, 1);
    CGSize s = self.bounds.size;
    for (int i = 1; i < 3; i++) {
        CGFloat x = floorf(s.width * i / 3) + 0.5f, y = floorf(s.height * i / 3) + 0.5f;
        CGContextMoveToPoint(c, x, 0); CGContextAddLineToPoint(c, x, s.height);
        CGContextMoveToPoint(c, 0, y); CGContextAddLineToPoint(c, s.width, y);
    }
    CGContextStrokePath(c);
}
@end

@implementation QRView
- (void)dealloc { free(qr); [super dealloc]; }
- (void)setText:(NSString *)text {
    free(qr);
    qr = malloc(qrcodegen_BUFFER_LEN_MAX);
    uint8_t *tmp = malloc(qrcodegen_BUFFER_LEN_MAX);
    if (!qrcodegen_encodeText([text UTF8String], tmp, qr, qrcodegen_Ecc_MEDIUM, qrcodegen_VERSION_MIN,
                              qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true)) { free(qr); qr = NULL; }
    free(tmp);
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, self.bounds);
    if (!qr) return;
    int n = qrcodegen_getSize(qr);
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat m = floorf(side / (n + 8));                       // 4-module quiet zone each side
    CGFloat ox = floorf((self.bounds.size.width - m * n) / 2), oy = floorf((self.bounds.size.height - m * n) / 2);
    CGContextSetRGBFillColor(c, 0, 0, 0, 1);
    for (int y = 0; y < n; y++)
        for (int x = 0; x < n; x++)
            if (qrcodegen_getModule(qr, x, y)) CGContextFillRect(c, CGRectMake(ox + x * m, oy + y * m, m, m));
}
@end

@implementation HoldView
- (id)initWithFrame:(CGRect)f target:(id)t action:(SEL)a {
    if ((self = [super initWithFrame:f])) { target = t; action = a; self.backgroundColor = [UIColor clearColor]; }
    return self;
}
- (void)fire { [target performSelector:action]; }
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event { [self performSelector:@selector(fire) withObject:nil afterDelay:1.5]; }
- (void)cancelHold { [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fire) object:nil]; }
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event { [self cancelHold]; }
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event { [self cancelHold]; }
@end
