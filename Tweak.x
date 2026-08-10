#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL isRunning = NO;
static NSTimer *clickTimer = nil;
static CGPoint targetPoint = {150, 300};

static UIView *menuView = nil;
static UIButton *toggleBtn = nil;
static UIButton *targetBtn = nil;
static UIView *targetPin = nil;

static UIEvent *lastRealEvent = nil;

// HOOK TRỰC TIẾP VÀO LƯỒNG EVENT CỦA APP ĐỂ BẮT VÀ NHÂN BẢN EVENT THẬT
%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypeTouches) {
        NSSet *touches = [event allTouches];
        UITouch *touch = [touches anyObject];
        // Lưu lại sự kiện thật gần nhất do người dùng tự bấm (không phải do Tweak tạo)
        if (touch && touch.view != menuView && touch.view != targetPin && ![touch.view isDescendantOfView:menuView]) {
            lastRealEvent = event;
        }
    }
    %orig;
}
%end

@interface AutoClickEngine : NSObject
+ (void)setupOverlay;
+ (void)toggleAction;
+ (void)toggleTargetPin;
+ (void)performInternalClick;
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

        // 2. Menu Điều Khiển
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

        clickTimer = [NSTimer timerWithTimeInterval:0.25 
                                             target:self 
                                           selector:@selector(performInternalClick) 
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

+ (void)performInternalClick {
    UIWindow *keyWin = menuView.window;
    if (!keyWin) return;

    menuView.hidden = YES;
    targetPin.hidden = YES;

    UIView *hitView = [keyWin hitTest:targetPoint withEvent:nil];

    menuView.hidden = NO;
    targetPin.hidden = NO;

    if (!hitView) return;

    // Kích hoạt direct responder nếu là UIControl
    if ([hitView isKindOfClass:[UIControl class]]) {
        [(UIControl *)hitView sendActionsForControlEvents:UIControlEventTouchUpInside];
    }

    // Tạo giả lập touch tương thích tối đa với Sandbox
    UITouch *touch = [[UITouch alloc] init];
    [touch setValue:@(UITouchPhaseBegan) forKey:@"phase"];
    [touch setValue:keyWin forKey:@"window"];
    [touch setValue:hitView forKey:@"view"];
    [touch setValue:[NSValue valueWithCGPoint:targetPoint] forKey:@"locationInWindow"];
    [touch setValue:@1 forKey:@"tapCount"];

    // Gửi sự kiện qua Responder Chain
    [hitView touchesBegan:[NSSet setWithObject:touch] withEvent:lastRealEvent];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [touch setValue:@(UITouchPhaseEnded) forKey:@"phase"];
        [hitView touchesEnded:[NSSet setWithObject:touch] withEvent:lastRealEvent];
    });
}

@end

__attribute__((constructor)) static void initializeAutoClicker() {
    %init;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification 
                                                      object:nil 
                                                       queue:[NSOperationQueue mainQueue] 
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [AutoClickEngine setupOverlay];
        });
    }];
}
