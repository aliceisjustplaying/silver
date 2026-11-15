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
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect disk = CGRectInset(self.bounds, 4, 4);
    float dim = (self.highlighted || !self.enabled) ? 0.55f : 1.0f;
    CGContextSetRGBStrokeColor(c, 0.90f * dim, 0.72f * dim, 0.23f * dim, 1);
    CGContextSetLineWidth(c, 1.5f);
    CGContextStrokeEllipseInRect(c, CGRectInset(self.bounds, 1, 1));
    CGContextSetRGBFillColor(c, 0.90f * dim, 0.72f * dim, 0.23f * dim, 1);
    CGContextFillEllipseInRect(c, disk);
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, disk); CGContextClip(c);
    // craters
    static const float craters[][3] = {{0.30f, 0.35f, 0.10f}, {0.55f, 0.25f, 0.07f}, {0.42f, 0.62f, 0.12f},
                                       {0.68f, 0.55f, 0.06f}, {0.25f, 0.70f, 0.05f}};
    CGContextSetRGBFillColor(c, 0.62f * dim, 0.48f * dim, 0.12f * dim, 0.6f);
    for (int i = 0; i < 5; i++) {
        float cx = disk.origin.x + craters[i][0] * disk.size.width, cy = disk.origin.y + craters[i][1] * disk.size.height;
        float rr = craters[i][2] * disk.size.width;
        CGContextFillEllipseInRect(c, CGRectMake(cx - rr, cy - rr, 2 * rr, 2 * rr));
    }
    // crescent shadow
    CGContextSetRGBFillColor(c, 0, 0, 0, 0.55f);
    CGContextFillEllipseInRect(c, CGRectOffset(disk, disk.size.width * 0.28f, -disk.size.height * 0.30f));
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
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    UIFont *f = [UIFont systemFontOfSize:12];
    [(on || self.highlighted ? GoldColor() : [UIColor whiteColor]) set];
    CGFloat w = SpacedWidth(title, f, 3);
    DrawSpaced(title, CGPointMake((self.bounds.size.width - w) / 2, (self.bounds.size.height - 15) / 2), f, 3);
}
@end

@implementation FilmCard
- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.opaque = NO; self.backgroundColor = [UIColor clearColor]; }
    return self;
}
- (void)dealloc { [name release]; [super dealloc]; }
- (void)setName:(NSString *)n { [name release]; name = [n copy]; [self setNeedsDisplay]; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    float dim = self.highlighted ? 0.6f : 1.0f;
    CGRect card = CGRectInset(self.bounds, 1, 1);
    CGContextSetRGBFillColor(c, 0.90f * dim, 0.72f * dim, 0.23f * dim, 1);
    CGContextFillRect(c, card);
    CGContextSetRGBStrokeColor(c, 0.15f, 0.12f, 0.05f, 1);
    CGContextSetLineWidth(c, 1);
    CGContextStrokeRect(c, CGRectInset(card, 2.5f, 2.5f));
    // a small sun
    CGPoint s = CGPointMake(card.origin.x + card.size.width / 2, card.origin.y + card.size.height * 0.38f);
    CGContextSetRGBFillColor(c, 0.10f, 0.10f, 0.20f, 1);
    CGContextFillEllipseInRect(c, CGRectMake(s.x - 4, s.y - 4, 8, 8));
    CGContextSetRGBStrokeColor(c, 0.10f, 0.10f, 0.20f, 1);
    for (int i = 0; i < 12; i++) {
        float a = i * (float)M_PI / 6;
        CGContextMoveToPoint(c, s.x + cosf(a) * 6, s.y + sinf(a) * 6);
        CGContextAddLineToPoint(c, s.x + cosf(a) * 9, s.y + sinf(a) * 9);
    }
    CGContextStrokePath(c);
    UIFont *f = [UIFont boldSystemFontOfSize:7];
    [[UIColor colorWithRed:0.10f green:0.10f blue:0.20f alpha:1] set];
    CGFloat w = SpacedWidth(name, f, 1);
    DrawSpaced(name, CGPointMake(card.origin.x + (card.size.width - w) / 2, card.origin.y + card.size.height - 14), f, 1);
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
