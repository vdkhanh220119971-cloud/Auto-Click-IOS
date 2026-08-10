#import <UIKit/UIKit.h>

static BOOL isRunning = NO;
static NSTimer *clickTimer = nil;
static CGPoint targetPoint = {150, 300}; // Tọa độ mặc định

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
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;

    // --- 1. TẠO TÂM GHIM (TARGET PIN) ---
    targetPin = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    targetPin.center = targetPoint;
    targetPin.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.6];
    targetPin.layer.cornerRadius = 15;
    targetPin.layer.borderWidth = 2;
    targetPin.layer.borderColor = [UIColor whiteColor].CGColor;
    targetPin.hidden = YES; // Mặc định ẩn, bật khi cần chỉnh vị trí
    
    UIPanGestureRecognizer *pinPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPin:)];
    [targetPin addGestureRecognizer:pinPan];
    [window addSubview:targetPin];

    // --- 2. TẠO MENU ĐIỀU KHIỂN TỐI ƯU ---
    menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 180, 44)];
    menuView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    menuView.layer.cornerRadius = 22; // Bo tròn dạng Capsule
    menuView.layer.borderWidth = 1;
    menuView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
    
    // Cử chỉ kéo thả Menu
    UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragMenu:)];
    [menuView addGestureRecognizer:menuPan];

    // --- 3. NÚT TIẾP TỤC / DỪNG ---
    toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    toggleBtn.frame = CGRectMake(6, 6, 110, 32);
    toggleBtn.layer.cornerRadius = 16;
    toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [toggleBtn setTitle:@"▶ TIẾP TỤC" forState:UIControlStateNormal];
    toggleBtn.backgroundColor = [UIColor systemGreenColor];
    [toggleBtn addTarget:self action:@selector(toggleAction) forControlEvents:UIControlEventTouchUpInside];
    [menuView addSubview:toggleBtn];

    // --- 4. NÚT CHỈNH VỊ TRÍ ---
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

// Kéo thả Menu
+ (void)dragMenu:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    CGPoint translation = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:view.superview];
}

// Kéo thả Tâm ghim vị trí
+ (void)dragPin:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    CGPoint translation = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:view.superview];
    
    targetPoint = view.center; // Lưu vị trí mới
}

// Bật/Ẩn Tâm ghim chọn vị trí
+ (void)toggleTargetPin {
    targetPin.hidden = !targetPin.hidden;
    if (!targetPin.hidden) {
        targetBtn.backgroundColor = [UIColor systemBlueColor];
    } else {
        targetBtn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    }
}

// Bật / Dừng Auto Click
+ (void)toggleAction {
    isRunning = !isRunning;

    if (isRunning) {
        // Chuyển giao diện sang trạng thái ĐANG CHẠY
        [toggleBtn setTitle:@"⏸ DỪNG" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemRedColor];
        
        // Ẩn tâm ghim cho gọn màn hình khi đang chạy
        targetPin.hidden = YES;
        targetBtn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];

        // Khởi tạo Timer tối ưu độ trễ (Mặc định 0.1s = 10 click/giây)
        clickTimer = [NSTimer timerWithTimeInterval:0.1 
                                             target:self 
                                           selector:@selector(performClick) 
                                           userInfo:nil 
                                            repeats:YES];
        // Đưa Timer vào RunLoop Common để không bị khựng khi cuộn màn hình
        [[NSRunLoop mainRunLoop] addTimer:clickTimer forMode:NSRunLoopCommonModes];
        
    } else {
        // Chuyển giao diện sang trạng thái DỪNG
        [toggleBtn setTitle:@"▶ TIẾP TỤC" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemGreenColor];

        [clickTimer invalidate];
        clickTimer = nil;
    }
}

// HÀM MÔ PHỎNG CLICK TỐI ƯU SỰ KIỆN
+ (void)performClick {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;

    UIView *hitView = [window hitTest:targetPoint withEvent:nil];
    if (hitView) {
        CGPoint localPoint = [window convertPoint:targetPoint toView:hitView];
        
        // 1. Tạo sự kiện Chạm xuống (Touch Down)
        UITouch *touch = [[UITouch alloc] init];
        // Nếu target view hỗ trợ kích hoạt trực tiếp UIButton
        if ([hitView isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)hitView;
            [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
        } else {
            // Gửi thông điệp Selector chuẩn UIKit cho View thường
            SEL touchBegan = @selector(touchesBegan:withEvent:);
            SEL touchEnded = @selector(touchesEnded:withEvent:);
            
            if ([hitView respondsToSelector:touchBegan]) {
                [hitView touchesBegan:[NSSet setWithObject:touch] withEvent:nil];
            }
            
            // Hoãn ngắn 0.02s rồi gửi sự kiện Nhấc tay (Touch Up)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if ([hitView respondsToSelector:touchEnded]) {
                    [hitView touchesEnded:[NSSet setWithObject:touch] withEvent:nil];
                }
            });
        }
    }
}

@end

// HOOK VÀO APP KHI MỞ
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
