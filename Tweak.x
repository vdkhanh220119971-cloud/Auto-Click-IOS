#import <UIKit/UIKit.h>

static BOOL isRunning = NO;
static NSTimer *clickTimer = nil;
static CGPoint targetPoint = {150, 300};

static UIView *menuView = nil;
static UIButton *toggleBtn = nil;
static UIButton *targetBtn = nil;
static UIView *targetPin = nil;

// Hàm helper lấy UIWindow tương thích mọi phiên bản iOS
static UIWindow* getKeyWindow() {
    UIWindow *foundWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in scene.windows) {
                    if (window.isKeyWindow) {
                        return window;
                    }
                }
            }
        }
    }
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    foundWindow = [UIApplication sharedApplication].keyWindow;
    #pragma clang diagnostic pop
    return foundWindow;
}

@interface AutoClickEngine : NSObject
+ (void)setupOverlay;
+ (void)toggleAction;
+ (void)toggleTargetPin;
+ (void)performClick;
@end

@implementation AutoClickEngine

+ (void)setupOverlay {
    UIWindow *window = getKeyWindow();
    if (!window) return;

    targetPin = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    targetPin.center = targetPoint;
    targetPin.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.6];
    targetPin.layer.cornerRadius = 15;
    targetPin.layer.borderWidth = 2;
    targetPin.layer.borderColor = [UIColor whiteColor].CGColor;
    targetPin.hidden = YES;
    
    UIPanGestureRecognizer *pinPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPin:)];
    [targetPin addGestureRecognizer:pinPan];
    [window addSubview:targetPin];

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
    if (!targetPin.hidden) {
        targetBtn.backgroundColor = [UIColor systemBlueColor];
    } else {
        targetBtn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    }
}

+ (void)toggleAction {
    isRunning = !isRunning;

    if (isRunning) {
        [toggleBtn setTitle:@"⏸ DỪNG" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemRedColor];
        
        targetPin.hidden = YES;
        targetBtn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];

        clickTimer = [NSTimer timerWithTimeInterval:0.1 
                                             target:self 
                                           selector:@selector(performClick) 
                                           userInfo:nil 
                                            repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:clickTimer forMode:NSRunLoopCommonModes];
        
    } else {
        [toggleBtn setTitle:@"▶ TIẾP TỤC" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemGreenColor];

        [clickTimer invalidate];
        clickTimer = nil;
    }
}

+ (void)performClick {
    UIWindow *window = getKeyWindow();
    if (!window) return;

    UIView *hitView = [window hitTest:targetPoint withEvent:nil];
    if (hitView) {
        if ([hitView isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)hitView;
            [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
        } else {
            UITouch *touch = [[UITouch alloc] init];
            SEL touchBegan = @selector(touchesBegan:withEvent:);
            SEL touchEnded = @selector(touchesEnded:withEvent:);
            
            if ([hitView respondsToSelector:touchBegan]) {
                [hitView touchesBegan:[NSSet setWithObject:touch] withEvent:nil];
            }
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if ([hitView respondsToSelector:touchEnded]) {
                    [hitView touchesEnded:[NSSet setWithObject:touch] withEvent:nil];
                }
            });
        }
    }
}

@end

%hook UIApplication
- (void)applicationDidBecomeActive:(id)application {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [AutoClickEngine setupOverlay];
        });
    });
}
%end
