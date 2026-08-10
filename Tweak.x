#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

// Định nghĩa các hàm Private CAPI của Apple để tạo IOHIDEvent cấp thấp
typedef struct __IOHIDEvent * IOHIDEventRef;
typedef uint32_t IOHIDDigitizerTransducerType;

FOUNDATION_EXTERN IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(
    CFAllocatorRef allocator,
    uint64_t timeStamp,
    uint32_t index,
    uint32_t identity,
    uint32_t eventOptions,
    float x,
    float y,
    float z,
    float tipPressure,
    float twist,
    Boolean range,
    Boolean touch,
    uint32_t options
);

FOUNDATION_EXTERN void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child, uint32_t options);

// Khởi tạo client kết nối đến hệ thống cảm ứng
typedef struct __IOHIDEventSystemClient * IOHIDEventSystemClientRef;
FOUNDATION_EXTERN IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
FOUNDATION_EXTERN void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);

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
+ (void)sendLowLevelTouchAtPoint:(CGPoint)point;
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

        // 1. Tạo Tâm Ghim
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

        // 2. Tạo Menu Điều Khiển
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

        // Tốc độ nhấp: 0.15 giây / lần
        clickTimer = [NSTimer timerWithTimeInterval:0.15 
                                             target:self 
                                           selector:@selector(triggerClick) 
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

+ (void)triggerClick {
    [self sendLowLevelTouchAtPoint:targetPoint];
}

// LÕI XỬ LÝ: MÔ PHỎNG SỰ KIỆN CẢM ỨNG CẤP THẤP TỐI ƯU NHẤT
+ (void)sendLowLevelTouchAtPoint:(CGPoint)point {
    UIScreen *mainScreen = [UIScreen mainScreen];
    CGRect bounds = mainScreen.bounds;
    
    // Chuẩn hóa tọa độ theo tỉ lệ màn hình thực tế (Normalized Coordinates 0.0 -> 1.0)
    float normalizedX = point.x / bounds.size.width;
    float normalizedY = point.y / bounds.size.height;

    uint64_t now = mach_absolute_time();

    // 1. Tạo sự kiện Chạm ngón tay xuống (Touch Down)
    IOHIDEventRef eventDown = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, now, 1, 0, 0,
        normalizedX, normalizedY, 0, 1.0, 0,
        1, 1, 0
    );

    // 2. Tạo sự kiện Nhấc ngón tay lên (Touch Up)
    IOHIDEventRef eventUp = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, now + 10000000, 1, 0, 0,
        normalizedX, normalizedY, 0, 0.0, 0,
        0, 0, 0
    );

    // Phát lệnh gửi Touch Down qua ứng dụng
    UIWindow *keyWin = menuView.window;
    if (keyWin) {
        // Gửi sự kiện trực tiếp vào cổng tiếp nhận Responder của App
        UIView *hitView = [keyWin hitTest:point withEvent:nil];
        if (hitView && hitView != menuView && hitView != targetPin) {
            UITouch *touch = [[UITouch alloc] init];
            [touch setValue:@(UITouchPhaseBegan) forKey:@"phase"];
            [touch setValue:keyWin forKey:@"window"];
            [touch setValue:hitView forKey:@"view"];
            [touch setValue:[NSValue valueWithCGPoint:point] forKey:@"locationInWindow"];

            UIEvent *event = [[UIApplication sharedApplication] performSelector:@selector(_touchesEvent)];
            if (event) {
                [hitView touchesBegan:[NSSet setWithObject:touch] withEvent:event];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [touch setValue:@(UITouchPhaseEnded) forKey:@"phase"];
                    [hitView touchesEnded:[NSSet setWithObject:touch] withEvent:event];
                });
            }
        }
    }

    if (eventDown) CFRelease(eventDown);
    if (eventUp) CFRelease(eventUp);
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
