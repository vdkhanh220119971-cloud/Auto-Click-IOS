#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import "GCDAsyncSocket.h"

// --- KHAI BÁO CẤP THẤP IOHIDEVENT ---
typedef struct __IOHIDEvent * IOHIDEventRef;
typedef struct __IOHIDEventSystemClient * IOHIDEventSystemClientRef;

static IOHIDEventRef (*$IOHIDEventCreateDigitizerFingerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, float, float, float, float, float, Boolean, Boolean, uint32_t) = NULL;
static IOHIDEventSystemClientRef (*$IOHIDEventSystemClientCreate)(CFAllocatorRef) = NULL;
static void (*$IOHIDEventSystemClientDispatchEvent)(IOHIDEventSystemClientRef, IOHIDEventRef) = NULL;
static IOHIDEventSystemClientRef sharedHIDClient = NULL;

// --- KHAI BÁO UI ---
static BOOL isRunning = NO;
static NSTimer *clickTimer = nil;
static CGPoint targetPoint = {150, 300};
static UIView *menuView = nil;
static UIButton *toggleBtn = nil;
static UIView *targetPin = nil;

// --- LỚP SOCKET SERVER (XỬ LÝ TOUCH CHẠY NGẦM) ---
@interface TouchSocketServer : NSObject <GCDAsyncSocketDelegate>
@property (nonatomic, strong) GCDAsyncSocket *serverSocket;
@property (nonatomic, strong) NSMutableArray *connectedClients;
+ (instancetype)sharedServer;
- (void)startListening;
- (void)dispatchHardwareTouchAtX:(float)x y:(float)y;
@end

@implementation TouchSocketServer
+ (instancetype)sharedServer {
    static TouchSocketServer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TouchSocketServer alloc] init];
        instance.connectedClients = [NSMutableArray array];
    });
    return instance;
}

- (void)startListening {
    dispatch_queue_t serverQueue = dispatch_queue_create("com.autoclick.serverQueue", DISPATCH_QUEUE_SERIAL);
    self.serverSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:serverQueue];
    NSError *error = nil;
    if ([self.serverSocket acceptOnPort:8181 error:&error]) {
        NSLog(@"[AutoClick] Socket Server started on port 8181");
    }
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
    [self.connectedClients addObject:newSocket];
    [newSocket readDataWithTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSString *command = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    command = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Parse lệnh "X,Y"
    NSArray *coords = [command componentsSeparatedByString:@","];
    if (coords.count == 2) {
        float x = [coords[0] floatValue];
        float y = [coords[1] floatValue];
        [self dispatchHardwareTouchAtX:x y:y];
    }
    [sock readDataWithTimeout:-1 tag:0];
}

// Bơm Touch IOHIDEvent trực tiếp vào System Event Queue
- (void)dispatchHardwareTouchAtX:(float)x y:(float)y {
    if (!$IOHIDEventCreateDigitizerFingerEvent || !$IOHIDEventSystemClientDispatchEvent) return;
    if (!sharedHIDClient) sharedHIDClient = $IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!sharedHIDClient) return;

    // Lấy tỷ lệ màn hình chuẩn (Normalized)
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    float nx = x / screenSize.width;
    float ny = y / screenSize.height;

    uint64_t now = mach_absolute_time();

    // 1. Gửi Touch Down
    IOHIDEventRef eventDown = $IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, now, 1, 0, 0, nx, ny, 0, 1.0, 0, 1, 1, 0);
    if (eventDown) {
        $IOHIDEventSystemClientDispatchEvent(sharedHIDClient, eventDown);
        CFRelease(eventDown);
    }

    // 2. Delay 30ms (giả lập ngón tay dừng lại trên màn)
    usleep(30000);

    // 3. Gửi Touch Up
    now = mach_absolute_time();
    IOHIDEventRef eventUp = $IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, now, 1, 0, 0, nx, ny, 0, 0.0, 0, 0, 0, 0);
    if (eventUp) {
        $IOHIDEventSystemClientDispatchEvent(sharedHIDClient, eventUp);
        CFRelease(eventUp);
    }
}
@end

// --- LỚP ENGINE VÀ GIAO DIỆN CLIENT ---
@interface AutoClickEngine : NSObject
+ (void)setupOverlay;
+ (void)toggleAction;
+ (void)fireTouchCommand;
@end

@implementation AutoClickEngine
static GCDAsyncSocket *clientSocket;

+ (void)setupOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window || menuView) return;

        // Khởi động Socket Client
        clientSocket = [[GCDAsyncSocket alloc] initWithDelegate:nil delegateQueue:dispatch_get_main_queue()];
        [clientSocket connectToHost:@"127.0.0.1" onPort:8181 error:nil];

        // Tạo Tâm Ghim
        targetPin = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 36, 36)];
        targetPin.center = targetPoint;
        targetPin.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.5];
        targetPin.layer.cornerRadius = 18;
        targetPin.layer.borderWidth = 2;
        targetPin.layer.borderColor = [UIColor whiteColor].CGColor;
        UIPanGestureRecognizer *pinPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPin:)];
        [targetPin addGestureRecognizer:pinPan];
        [window addSubview:targetPin];

        // Tạo Menu
        menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 130, 44)];
        menuView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        menuView.layer.cornerRadius = 22;
        UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragMenu:)];
        [menuView addGestureRecognizer:menuPan];

        toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        toggleBtn.frame = CGRectMake(6, 6, 118, 32);
        toggleBtn.layer.cornerRadius = 16;
        toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [toggleBtn setTitle:@"▶ TIẾP TỤC" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemGreenColor];
        [toggleBtn addTarget:self action:@selector(toggleAction) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:toggleBtn];

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

+ (void)toggleAction {
    isRunning = !isRunning;
    if (isRunning) {
        [toggleBtn setTitle:@"⏸ DỪNG" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemRedColor];
        
        // Timer chạy mỗi 0.2s, chỉ việc gửi chuỗi "X,Y" qua socket
        clickTimer = [NSTimer timerWithTimeInterval:0.2 target:self selector:@selector(fireTouchCommand) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:clickTimer forMode:NSRunLoopCommonModes];
    } else {
        [toggleBtn setTitle:@"▶ TIẾP TỤC" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = [UIColor systemGreenColor];
        [clickTimer invalidate];
        clickTimer = nil;
    }
}

// Bắn lệnh qua Socket để Server gọi IOHIDEvent
+ (void)fireTouchCommand {
    if ([clientSocket isConnected]) {
        NSString *cmd = [NSString stringWithFormat:@"%f,%f\n", targetPoint.x, targetPoint.y];
        NSData *cmdData = [cmd dataUsingEncoding:NSUTF8StringEncoding];
        [clientSocket writeData:cmdData withTimeout:-1 tag:0];
    } else {
        // Reconnect nếu rớt mạng nội bộ
        [clientSocket connectToHost:@"127.0.0.1" onPort:8181 error:nil];
    }
}
@end

// --- HÀM KHỞI TẠO ĐỘNG (Bypass Lỗi Undefined Symbol) ---
__attribute__((constructor)) static void initializeAutoClicker() {
    // Load IOKit API động trong Runtime
    void *ioKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (ioKitHandle) {
        $IOHIDEventCreateDigitizerFingerEvent = dlsym(ioKitHandle, "IOHIDEventCreateDigitizerFingerEvent");
        $IOHIDEventSystemClientCreate = dlsym(ioKitHandle, "IOHIDEventSystemClientCreate");
        $IOHIDEventSystemClientDispatchEvent = dlsym(ioKitHandle, "IOHIDEventSystemClientDispatchEvent");
    }

    // Khởi động Socket Server chạy ngầm
    [[TouchSocketServer sharedServer] startListening];

    // Khởi động UI
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification 
                                                      object:nil 
                                                       queue:[NSOperationQueue mainQueue] 
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [AutoClickEngine setupOverlay];
        });
    }];
}
