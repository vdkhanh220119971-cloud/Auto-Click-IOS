#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import "GCDAsyncSocket.h"

// --- DEFINITIONS CHO PRIVATE IOHIDEVENT ---
typedef struct __IOHIDEvent * IOHIDEventRef;
typedef struct __IOHIDEventSystemClient * IOHIDEventSystemClientRef;

#define kIOHIDDigitizerEventRange 0x00000001
#define kIOHIDDigitizerEventTouch 0x00000002

static IOHIDEventRef (*$IOHIDEventCreateDigitizerFingerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, float, float, float, float, float, Boolean, Boolean, uint32_t) = NULL;
static IOHIDEventSystemClientRef (*$IOHIDEventSystemClientCreate)(CFAllocatorRef) = NULL;
static void (*$IOHIDEventSystemClientDispatchEvent)(IOHIDEventSystemClientRef, IOHIDEventRef) = NULL;

static IOHIDEventSystemClientRef sharedHIDClient = NULL;

// --- TRẠNG THÁI TOÀN CỤC ---
static BOOL isRunning = NO;
static NSTimer *clickTimer = nil;
static CGPoint targetPoint = {150, 300};

static UIView *menuView = nil;
static UIButton *toggleBtn = nil;
static UIButton *targetBtn = nil;
static UIView *targetPin = nil;

static GCDAsyncSocket *clientSocket = nil;

// --- SERVER BƠM LỆNH PHẦN CỨNG BẰNG GCDASYNCSOCKET ---
@interface TouchServer : NSObject <GCDAsyncSocketDelegate>
@property (nonatomic, strong) GCDAsyncSocket *serverSocket;
@property (nonatomic, strong) dispatch_queue_t socketQueue;
+ (instancetype)sharedInstance;
- (void)startServer;
- (void)injectTouchAtX:(float)x y:(float)y;
@end

@implementation TouchServer

+ (instancetype)sharedInstance {
    static TouchServer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TouchServer alloc] init];
    });
    return instance;
}

- (void)startServer {
    self.socketQueue = dispatch_queue_create("com.autoclick.socketQueue", DISPATCH_QUEUE_SERIAL);
    self.serverSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.socketQueue];
    
    NSError *err = nil;
    if ([self.serverSocket acceptOnPort:8181 error:&err]) {
        NSLog(@"[AutoTouch] GCDAsyncSocket Listening on Port 8181");
    }
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
    [newSocket readDataWithTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    msg = [msg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSArray *parts = [msg componentsSeparatedByString:@","];
    if (parts.count == 2) {
        float x = [parts[0] floatValue];
        float y = [parts[1] floatValue];
        [self injectTouchAtX:x y:y];
    }
    
    [sock readDataWithTimeout:-1 tag:0];
}

// Bơm Touch ở cấp hệ thống thông qua IOHIDEvent
- (void)injectTouchAtX:(float)x y:(float)y {
    if (!$IOHIDEventCreateDigitizerFingerEvent || !$IOHIDEventSystemClientDispatchEvent) return;
    if (!sharedHIDClient && $IOHIDEventSystemClientCreate) {
        sharedHIDClient = $IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    }
    if (!sharedHIDClient) return;

    CGSize screen = [UIScreen mainScreen].bounds.size;
    float normX = x / screen.width;
    float normY = y / screen.height;

    uint64_t timestamp = mach_absolute_time();

    // 1. Touch Down
    IOHIDEventRef eventDown = $IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, 
        timestamp, 
        1, 
        0, 
        kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch, 
        normX, normY, 0, 
        1.0, 
        0, 
        1, 
        1, 
        0
    );

    if (eventDown) {
        $IOHIDEventSystemClientDispatchEvent(sharedHIDClient, eventDown);
        CFRelease(eventDown);
    }

    // Giữ phím 20ms giả lập thao tác tay thật
    usleep(20000);

    // 2. Touch Up
    timestamp = mach_absolute_time();
    IOHIDEventRef eventUp = $IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, 
        timestamp, 
        1, 
        0, 
        kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch, 
        normX, normY, 0, 
        0.0, 
        0, 
        0, 
        0, 
        0
    );

    if (eventUp) {
        $IOHIDEventSystemClientDispatchEvent(sharedHIDClient, eventUp);
        CFRelease(eventUp);
    }
}

@end

// --- UI OVERLAY & ĐIỀU KHIỂN ---
@interface AutoClickEngine : NSObject <GCDAsyncSocketDelegate>
+ (void)setupOverlay;
+ (void)toggleAction;
+ (void)sendTouchCommand;
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

        // Khởi tạo Socket Client kết nối đến Local Server
        dispatch_queue_t clientQueue = dispatch_queue_create("com.autoclick.clientQueue", DISPATCH_QUEUE_SERIAL);
        clientSocket = [[GCDAsyncSocket alloc] initWithDelegate:nil delegateQueue:clientQueue];
        [clientSocket connectToHost:@"127.0.0.1" onPort:8181 error:nil];

        // 1. Tâm Ghim
        targetPin = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 36, 36)];
        targetPin.center = targetPoint;
        targetPin.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.5];
        targetPin.layer.cornerRadius = 18;
        targetPin.layer.borderWidth = 2;
        targetPin.layer.borderColor = [UIColor whiteColor].CGColor;
        
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

        clickTimer = [NSTimer timerWithTimeInterval:0.15 
                                             target:self 
                                           selector:@selector(sendTouchCommand) 
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

+ (void)sendTouchCommand {
    if (![clientSocket isConnected]) {
        [clientSocket connectToHost:@"127.0.0.1" onPort:8181 error:nil];
    }
    
    NSString *payload = [NSString stringWithFormat:@"%.2f,%.2f\n", targetPoint.x, targetPoint.y];
    NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
    [clientSocket writeData:data withTimeout:-1 tag:0];
}

@end

// --- INIT DYNAMIC BINDINGS ---
__attribute__((constructor)) static void initializeEngine() {
    void *ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (ioKit) {
        $IOHIDEventCreateDigitizerFingerEvent = dlsym(ioKit, "IOHIDEventCreateDigitizerFingerEvent");
        $IOHIDEventSystemClientCreate = dlsym(ioKit, "IOHIDEventSystemClientCreate");
        $IOHIDEventSystemClientDispatchEvent = dlsym(ioKit, "IOHIDEventSystemClientDispatchEvent");
    }

    [[TouchServer sharedInstance] startServer];

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification 
                                                      object:nil 
                                                       queue:[NSOperationQueue mainQueue] 
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [AutoClickEngine setupOverlay];
        });
    }];
}
