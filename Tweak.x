#import <UIKit/UIKit.h>

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
+ (void)performClick;
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

        // 1. Tạo Tâm Ghim (Hiển thị mặc định ngay từ đầu)
        targetPin = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 36, 36)];
        targetPin.center = targetPoint;
        targetPin.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.5];
        targetPin.layer.cornerRadius = 18;
        targetPin.layer.borderWidth = 2;
        targetPin.layer.borderColor = [UIColor whiteColor].CGColor;
        targetPin.userInteractionEnabled = YES;
        
        // Thêm nhân tâm nhỏ ở giữa để dễ canh vị trí
        UIView *centerDot = [[UIView alloc] initWithFrame:CGRectMake(16, 16, 4, 4)];
        centerDot.backgroundColor = [UIColor whiteColor];
        centerDot.layer.cornerRadius = 2;
        [targetPin addSubview:centerDot];
        
        UIPanGestureRecognizer *pinPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPin:)];
        [targetPin addGestureRecognizer:pinPan];
        [window addSubview:targetPin];

        // 2. Tạo Menu
        menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 180, 44)];
        menuView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        menuView.layer.cornerRadius = 22;
        menuView.layer.borderWidth = 1;
        menuView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
        
        UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragMenu:)];
        [menuView addGestureRecognizer:menuPan];

        // 3. Nút Dừng / Tiếp tục
        toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        toggleBtn.frame = CGRectMake(6, 6, 110, 32);
        toggleBtn.layer.cornerRadius = 16;
        toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [toggleBtn setTitle:@"▶ TIẾP TỤC" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemGreenColor];
        [toggleBtn addTarget:self action:@selector(toggleAction) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:toggleBtn];

        // 4. Nút Ẩn/Hiện Tâm Ghim
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
    targetPoint = view.center; // Lưu vị trí tọa độ mới
}

+ (void)toggleTargetPin {
    targetPin.hidden = !targetPin.hidden;
    targetBtn.backgroundColor = !targetPin.hidden ? [UIColor systemBlueColor] : [[UIColor whiteColor] colorWithAlphaComponent:0.15];
}

+ (void)toggleAction {
    isRunning = !isRunning;
    if (isRunning) {
        // Trạng thái ĐANG CHẠY
        [toggleBtn setTitle:@"⏸ DỪNG" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemRedColor];
        
        // GIỮ NGUYÊN TÂM GHIM VÀ ĐỔI SANG MÀU XANH DƯƠNG ĐỂ BÁO ĐANG AUTO CLICK
        targetPin.hidden = NO;
        targetPin.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.6];

        clickTimer = [NSTimer timerWithTimeInterval:0.15 
                                             target:self 
                                           selector:@selector(performClick) 
                                           userInfo:nil 
                                            repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:clickTimer forMode:NSRunLoopCommonModes];
    } else {
        // Trạng thái DỪNG
        [toggleBtn setTitle:@"▶ TIẾP TỤC" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemGreenColor];
        
        // Đổi tâm ghim lại màu đỏ
        targetPin.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.5];

        [clickTimer invalidate];
        clickTimer = nil;
    }
}

// HÀM MÔ PHỎNG CLICK ĐÃ ĐƯỢC NÂNG CẤP VỚI 3 LỚP XỬ LÝ
+ (void)performClick {
    UIWindow *window = menuView.window;
    if (!window) return;

    // Tạm thời ẩn Menu và Tâm ghim cực ngắn để hitTest xuyên qua tìm đúng Nút nằm phía dưới
    menuView.hidden = YES;
    targetPin.hidden = YES;

    UIView *hitView = [window hitTest:targetPoint withEvent:nil];

    // Hiện lại Menu và Tâm ghim
    menuView.hidden = NO;
    targetPin.hidden = NO;

    if (hitView && hitView != menuView && hitView != targetPin) {
        
        // Cách 1: Nếu điểm bấm là UIButton / UIControl
        if ([hitView isKindOfClass:[UIControl class]]) {
            UIControl *control = (UIControl *)hitView;
            [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        } 
        
        // Cách 2: Kiểm tra xem View dưới điểm nhấp có Gesture Recognizer (Tap Gesture) không
        if (hitView.gestureRecognizers.count > 0) {
            for (UIGestureRecognizer *recognizer in hitView.gestureRecognizers) {
                if ([recognizer isKindOfClass:[UITapGestureRecognizer class]]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [recognizer.self performSelector:@selector(touchesBegan:withEvent:) withObject:nil];
                    #pragma clang diagnostic pop
                }
            }
        }
        
        // Cách 3: Gửi bộ Touch Event chuẩn
        UITouch *touch = [[UITouch alloc] init];
        SEL touchBegan = @selector(touchesBegan:withEvent:);
        SEL touchEnded = @selector(touchesEnded:withEvent:);
        
        if ([hitView respondsToSelector:touchBegan]) {
            [hitView touchesBegan:[NSSet setWithObject:touch] withEvent:nil];
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([hitView respondsToSelector:touchEnded]) {
                [hitView touchesEnded:[NSSet setWithObject:touch] withEvent:nil];
            }
        });
    }
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
