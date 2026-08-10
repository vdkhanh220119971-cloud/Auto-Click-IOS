#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach_time.h>

// Khai báo các Private APIs cần thiết để dựng UITouch chuẩn như ngón tay thật
@interface UITouch (Private)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTapCount:(NSUInteger)tapCount;
- (void)setIsTap:(BOOL)isTap;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)resetPrevious;
- (void)_setHidEvent:(id)hidEvent;
@end

@interface UIEvent (Private)
- (void)_addTouch:(UITouch *)touch forExtendedWithEvent:(id)event;
- (void)_clearTouches;
@end

static BOOL isRunning = NO;
static NSTimer *clickTimer = nil;
static CGPoint targetPoint = {150, 300};

static UIView *menuView = nil;
static UIButton *toggleBtn = nil;
static UIButton *targetBtn = nil;
static UIView *targetPin = nil;

@interface AutoClickEngine : NSObject
+ (void)setupOverlay;
+ (void)toggleAction;
+ (void)toggleTargetPin;
+ (void)performUniversalClick;
@end

@implementation AutoClickEngine

+ (void)setupOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) {
                        if (w.isKeyWindow) {
                            window = w;
                            break;
                        }
                    }
                }
                if (window) break;
            }
        }
        
        if (!window) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            window = [UIApplication sharedApplication].keyWindow;
            #pragma clang diagnostic pop
        }
        
        if (!window) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [AutoClickEngine setupOverlay];
            });
            return;
        }

        if (menuView) return;

        // 1. Tâm Ghim
        targetPin = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 36, 36)];
        targetPin.center = targetPoint;
        targetPin.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.5];
        targetPin.layer.cornerRadius = 18;
        targetPin.layer.borderWidth = 2;
        targetPin.layer.borderColor = [UIColor whiteColor].CGColor;
        targetPin.userInteractionEnabled = YES;
        
        UIView *centerDot = [[UIView alloc] initWithFrame:CGRectMake(16, 16, 4, 4)];
        centerDot.backgroundColor = [UIColor whiteColor];
        centerDot.layer.cornerRadius = 2;
        [targetPin addSubview:centerDot];
        
        UIPanGestureRecognizer *pinPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPin:)];
        [targetPin addGestureRecognizer:pinPan];
        [window addSubview:targetPin];

        // 2. Menu
        menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 180, 44)];
        menuView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        menuView.layer.cornerRadius = 22;
        menuView.layer.borderWidth = 1;
        menuView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
        
        UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragMenu:)];
        [menuView addGestureRecognizer:menuPan];

        toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        toggleBtn.frame = CGRectMake(6, 6, 110, 32);
        toggleBtn.layer.cornerRadius = 16;
        toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [toggleBtn setTitle:@"▶ TIẾP TỤC" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemGreenColor];
        [toggleBtn addTarget:self action:@selector(toggleAction) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:toggleBtn];

        targetBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        targetBtn.frame = CGRectMake(122, 6, 52, 32);
        targetBtn.layer.cornerRadius = 16;
        targetBtn.titleLabel.font = [UIFont systemFontOfSize:13];
        [targetBtn setTitle:@"🎯" forState:UIControlStateNormal];
        targetBtn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
        [targetBtn addTarget:self action:@selector(toggleTargetPin) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:targetBtn];

        [window addSubview:menuView];
    });
}

+ (void)dragMenu:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    CGPoint translation = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:view.superview];
}

+ (void)dragPin:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    CGPoint translation = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:view.superview];
    targetPoint = view.center;
}

+ (void)toggleTargetPin {
    targetPin.hidden = !targetPin.hidden;
    targetBtn.backgroundColor = !targetPin.hidden ? [UIColor systemBlueColor] : [[UIColor whiteColor] colorWithAlphaComponent:0.15];
}

+ (void)toggleAction {
    isRunning = !isRunning;
    if (isRunning) {
        [toggleBtn setTitle:@"⏸ DỪNG" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemRedColor];
        targetPin.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.6];

        clickTimer = [NSTimer timerWithTimeInterval:0.15 
                                             target:self 
                                           selector:@selector(performUniversalClick) 
                                           userInfo:nil 
                                            repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:clickTimer forMode:NSRunLoopCommonModes];
    } else {
        [toggleBtn setTitle:@"▶ TIẾP TỤC" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemGreenColor];
        targetPin.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.5];

        [clickTimer invalidate];
        clickTimer = nil;
    }
}

// THUẬT TOÁN BƠM EVENT DÙNG CẢ TRÊN GAME ENGINE VÀ APP TÙY BIẾN
+ (void)performUniversalClick {
    // 1. Tìm Window gốc thực tế (kể cả Window của Unity/Unreal)
    UIWindow *activeWindow = nil;
    NSArray *windows = [UIApplication sharedApplication].windows;
    for (UIWindow *w in [windows reverseObjectEnumerator]) {
        if (w != menuView.window && !w.hidden && w.alpha > 0) {
            activeWindow = w;
            break;
        }
    }
    if (!activeWindow) activeWindow = menuView.window;

    // 2. Ẩn menu & ghim tạm thời để hitTest không bị vướng
    menuView.hidden = YES;
    targetPin.hidden = YES;

    UIView *hitView = [activeWindow hitTest:targetPoint withEvent:nil];

    menuView.hidden = NO;
    targetPin.hidden = NO;

    if (!hitView) hitView = activeWindow;

    // 3. Xử lý UIControl nếu có
    if ([hitView isKindOfClass:[UIControl class]]) {
        [(UIControl *)hitView sendActionsForControlEvents:UIControlEventTouchUpInside];
    }

    // 4. Giả lập Touch theo Luồng Window SendEvent
    UIApplication *app = [UIApplication sharedApplication];
    UIEvent *event = nil;
    if ([app respondsToSelector:@selector(_touchesEvent)]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        event = [app performSelector:@selector(_touchesEvent)];
        #pragma clang diagnostic pop
    }

    UITouch *touch = [[UITouch alloc] init];
    [touch setWindow:activeWindow];
    [touch setView:hitView];
    [touch setTapCount:1];
    [touch setIsTap:YES];
    [touch setTimestamp:[[NSProcessInfo processInfo] systemUptime]];
    [touch _setLocationInWindow:targetPoint resetPrevious:YES];

    // PHÁT SỰ KIỆN TỚI WINDOW VA APPLICATION
    [touch setPhase:UITouchPhaseBegan];
    if (event && [event respondsToSelector:@selector(_addTouch:forExtendedWithEvent:)]) {
        [event _addTouch:touch forExtendedWithEvent:nil];
        [activeWindow sendEvent:event];
        [app sendEvent:event];
    } else {
        [hitView touchesBegan:[NSSet setWithObject:touch] withEvent:event];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [touch setPhase:UITouchPhaseEnded];
        [touch setTimestamp:[[NSProcessInfo processInfo] systemUptime]];

        if (event && [event respondsToSelector:@selector(_addTouch:forExtendedWithEvent:)]) {
            [activeWindow sendEvent:event];
            [app sendEvent:event];
            if ([event respondsToSelector:@selector(_clearTouches)]) {
                [event _clearTouches];
            }
        } else {
            [hitView touchesEnded:[NSSet setWithObject:touch] withEvent:event];
        }
    });
}

@end

__attribute__((constructor)) static void initializeAutoClicker() {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification 
                                                      object:nil 
                                                       queue:[NSOperationQueue mainQueue] 
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [AutoClickEngine setupOverlay];
        });
    }];
}
