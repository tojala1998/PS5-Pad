#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <arpa/inet.h>
#import "QPConnection.h"
#import "QPKodi.h"
#import "QPDiscovery.h"

static UIColor *Color(unsigned rgb) {
    return [UIColor colorWithRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
}
static UIColor *Accent(void) { return Color(0x6CA6FF); }
static UILabel *Label(NSString *text,CGFloat size,UIFontWeight weight,UIColor *color) {
    UILabel *label=[UILabel new]; label.text=text; label.font=[UIFont systemFontOfSize:size weight:weight];
    label.textColor=color; return label;
}
static void Round(UIView *view,CGFloat radius) {
    view.layer.cornerRadius=radius; view.layer.cornerCurve=kCACornerCurveContinuous;
    view.layer.borderWidth=1; view.layer.borderColor=Color(0x293039).CGColor;
}

@interface QPButton : UIControl
@property(nonatomic) uint32_t mask;
@property(nonatomic) NSInteger edge;
@property(nonatomic) BOOL down;
@property(nonatomic,copy) NSString *glyph;
@property(nonatomic,strong) UIColor *ink;
@property(nonatomic,copy) void (^changed)(void);
- (void)clear;
@end
@implementation QPButton
- (instancetype)init {
    if((self=[super init])) {
        self.backgroundColor=UIColor.clearColor; self.opaque=NO; self.clipsToBounds=YES;
        _ink=Color(0xD8DEE7); Round(self,14); self.layer.borderWidth=0;
        self.isAccessibilityElement=YES; self.accessibilityTraits=UIAccessibilityTraitButton;
    } return self;
}
- (void)setDown:(BOOL)down {
    if(_down==down) return; _down=down;
    self.backgroundColor=[_glyph isEqual:@"PS"]?(down?Color(0xA4C5FA):UIColor.whiteColor):(down?Color(0x292D35):UIColor.clearColor);
    self.layer.borderColor=(down?Accent():Color(0x293039)).CGColor;
    self.transform=down?CGAffineTransformMakeScale(.95,.95):CGAffineTransformIdentity;
    if(down) { UIImpactFeedbackGenerator *h=[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft]; [h impactOccurred]; }
    self.accessibilityValue=down?@"Pressed":@"Released";
    [self setNeedsDisplay]; if(_changed) _changed();
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)touch; (void)event; if(!self.enabled) return NO; self.down=YES; return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event; self.down=CGRectContainsPoint(CGRectInset(self.bounds,-18,-18),[touch locationInView:self]); return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { (void)touch; (void)event; self.down=NO; }
- (void)cancelTrackingWithEvent:(UIEvent *)event { (void)event; self.down=NO; }
- (void)clear { self.down=NO; }
- (BOOL)accessibilityActivate {
    if(!self.enabled) return NO; self.down=YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_MSEC),dispatch_get_main_queue(),^{self.down=NO;}); return YES;
}
- (void)drawRect:(CGRect)rect {
    (void)rect; CGFloat x=CGRectGetMidX(self.bounds),y=CGRectGetMidY(self.bounds),r=11;
    CGContextRef ctx=UIGraphicsGetCurrentContext(); CGContextSetStrokeColorWithColor(ctx,_ink.CGColor);
    CGContextSetLineWidth(ctx,2.2); CGContextSetLineCap(ctx,kCGLineCapRound); CGContextSetLineJoin(ctx,kCGLineJoinRound);
    if([_glyph isEqual:@"cross"]) { CGContextMoveToPoint(ctx,x-r,y-r); CGContextAddLineToPoint(ctx,x+r,y+r); CGContextMoveToPoint(ctx,x+r,y-r); CGContextAddLineToPoint(ctx,x-r,y+r); }
    else if([_glyph isEqual:@"circle"]) CGContextAddEllipseInRect(ctx,CGRectMake(x-r,y-r,r*2,r*2));
    else if([_glyph isEqual:@"square"]) CGContextAddRect(ctx,CGRectMake(x-r,y-r,r*2,r*2));
    else if([_glyph isEqual:@"triangle"]) { CGContextMoveToPoint(ctx,x,y-r-2); CGContextAddLineToPoint(ctx,x+r+2,y+r); CGContextAddLineToPoint(ctx,x-r-2,y+r); CGContextClosePath(ctx); }
    else if([_glyph isEqual:@"back"]) { CGContextMoveToPoint(ctx,x+5,y-10); CGContextAddLineToPoint(ctx,x-5,y); CGContextAddLineToPoint(ctx,x+5,y+10); }
    else if([_glyph isEqual:@"options"]) { for(int i=-1;i<=1;i++) { CGContextMoveToPoint(ctx,x-10,y+i*7); CGContextAddLineToPoint(ctx,x+10,y+i*7); } }
    CGContextStrokePath(ctx);
    if(_edge) { CGContextSetFillColorWithColor(ctx,_ink.CGColor); CGContextFillRect(ctx,CGRectMake(_edge<0?0:self.bounds.size.width-3,0,3,self.bounds.size.height)); }
    if([_glyph isEqual:@"touchpad"]) {
        CGContextStrokeRect(ctx,CGRectMake(x-13,y-9,22,16));
        CGContextStrokeRect(ctx,CGRectMake(x-6,y-3,22,16));
    }
    if([_glyph isEqual:@"L1"] || [_glyph isEqual:@"R1"] || [_glyph isEqual:@"PS"]) {
        NSDictionary *a=@{NSFontAttributeName:[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:_ink};
        CGSize sz=[_glyph sizeWithAttributes:a]; [_glyph drawAtPoint:CGPointMake(x-sz.width/2,y-sz.height/2) withAttributes:a];
    }
}
@end


@interface QPSwipePad : UIView
@property(nonatomic,copy) void (^pulse)(uint32_t);
@property(nonatomic) BOOL active;
@property(nonatomic,strong) UILabel *hint,*sub,*cross;
@property(nonatomic,strong) UIView *cursor;
@property(nonatomic) CFTimeInterval lastStep;
- (void)reset;
@end
@implementation QPSwipePad
- (instancetype)init {
    if((self=[super init])) {
        self.backgroundColor=UIColor.clearColor;
        _cross=Label(@"×",35,UIFontWeightMedium,Color(0x9DBFF3));
        _hint=Label(@"Swipe to navigate.",13,UIFontWeightSemibold,Color(0xB3B3B3));
        _sub=Label(@"Tap to select.",13,UIFontWeightSemibold,Color(0xB3B3B3));
        for(UILabel *label in @[_cross,_hint,_sub]) { label.textAlignment=NSTextAlignmentCenter; [self addSubview:label]; }
        _cursor=[[UIView alloc] initWithFrame:CGRectMake(0,0,44,44)];
        _cursor.backgroundColor=[Color(0xFFFFFF) colorWithAlphaComponent:.07];
        _cursor.layer.cornerRadius=22; _cursor.alpha=0; _cursor.userInteractionEnabled=NO; [self addSubview:_cursor];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        pan.maximumNumberOfTouches=1; [self addGestureRecognizer:pan];
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
        [tap requireGestureRecognizerToFail:pan]; [self addGestureRecognizer:tap];
        self.isAccessibilityElement=YES; self.accessibilityLabel=@"Swipe pad, Cross to select";
        self.accessibilityTraits=UIAccessibilityTraitButton;
        self.accessibilityCustomActions=@[
            [[UIAccessibilityCustomAction alloc] initWithName:@"Up" target:self selector:@selector(accessUp)],
            [[UIAccessibilityCustomAction alloc] initWithName:@"Down" target:self selector:@selector(accessDown)],
            [[UIAccessibilityCustomAction alloc] initWithName:@"Left" target:self selector:@selector(accessLeft)],
            [[UIAccessibilityCustomAction alloc] initWithName:@"Right" target:self selector:@selector(accessRight)]];
    } return self;
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat w=self.bounds.size.width,y=self.bounds.size.height/2;
    _cross.frame=CGRectMake(0,y-47,w,40); _hint.frame=CGRectMake(0,y-2,w,20); _sub.frame=CGRectMake(0,y+15,w,20);
}
- (void)setActive:(BOOL)active { _active=active; self.alpha=active?1:.45; if(!active) [self reset]; }
- (void)emit:(uint32_t)mask { if(!_active||!_pulse) return; _pulse(mask); [[UISelectionFeedbackGenerator new] selectionChanged]; }
- (void)tap:(UITapGestureRecognizer *)gesture { if(gesture.state==UIGestureRecognizerStateRecognized) [self emit:QP_CROSS]; }
- (void)pan:(UIPanGestureRecognizer *)gesture {
    if(!_active) return;
    if(gesture.state==UIGestureRecognizerStateBegan) { _lastStep=0; _cursor.alpha=1; }
    if(gesture.state==UIGestureRecognizerStateBegan||gesture.state==UIGestureRecognizerStateChanged) {
        _cursor.center=[gesture locationInView:self]; CGPoint d=[gesture translationInView:self];
        if(fmax(fabs(d.x),fabs(d.y))>=30 && CACurrentMediaTime()-_lastStep>=.16) {
            [self emit:fabs(d.x)>fabs(d.y)?(d.x>0?QP_RIGHT:QP_LEFT):(d.y>0?QP_DOWN:QP_UP)];
            _lastStep=CACurrentMediaTime(); [gesture setTranslation:CGPointZero inView:self];
        }
    } else [self reset];
}
- (void)reset { _cursor.alpha=0; }
- (BOOL)accessibilityActivate { [self emit:QP_CROSS]; return _active; }
- (BOOL)accessUp { [self emit:QP_UP]; return _active; }
- (BOOL)accessDown { [self emit:QP_DOWN]; return _active; }
- (BOOL)accessLeft { [self emit:QP_LEFT]; return _active; }
- (BOOL)accessRight { [self emit:QP_RIGHT]; return _active; }
@end

@interface QPViewController : UIViewController
@property(nonatomic,strong) QPConnection *link;
@property(nonatomic,strong) UIView *canvas;
@property(nonatomic,strong) UILabel *titleLabel,*statusLabel,*result;
@property(nonatomic,strong) UIButton *consoleButton,*appsButton,*moreButton;
@property(nonatomic,strong) QPSwipePad *swipe;
@property(nonatomic,strong) NSMutableArray<QPButton *> *buttons;
@property(nonatomic,strong) NSMutableArray<UIButton *> *mediaButtons;
@property(nonatomic,copy) NSString *host;
@property(nonatomic) uint32_t pulseMask;
@property(nonatomic) NSUInteger pulseGeneration;
@property(nonatomic) BOOL wantsConnection;
@property(nonatomic) BOOL didOfferSetup;
- (void)resume;
- (void)suspend;
@end

@implementation QPViewController
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (UIButton *)symbol:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular]] forState:UIControlStateNormal];
    button.tintColor=UIColor.whiteColor; button.accessibilityLabel=label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; [_canvas addSubview:button]; return button;
}
- (QPButton *)padButton:(NSString *)glyph label:(NSString *)label mask:(uint32_t)mask color:(unsigned)color edge:(NSInteger)edge {
    QPButton *button=[QPButton new]; button.glyph=glyph; button.mask=mask; button.ink=Color(color);
    button.edge=edge; button.accessibilityLabel=label;
    __weak QPViewController *weakSelf=self; button.changed=^{[weakSelf updateState];};
    [_buttons addObject:button]; [_canvas addSubview:button]; return button;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.view.backgroundColor=Color(0x171717); _canvas=[UIView new]; [self.view addSubview:_canvas];
    _buttons=[NSMutableArray array]; _mediaButtons=[NSMutableArray array]; _link=[QPConnection new];
    _host=[NSUserDefaults.standardUserDefaults stringForKey:@"consoleHost"];
    _wantsConnection=![NSProcessInfo.processInfo.arguments containsObject:@"--offline"];
    __weak QPViewController *weakSelf=self;
    _link.changed=^{[weakSelf refresh];};
    _link.completed=^(NSString *action,int32_t status) {
        QPViewController *self=weakSelf; if(!self) return;
        if(status) self.result.text=[NSString stringWithFormat:@"%@ failed (0x%08X)",action,(unsigned)status];
        else if([action isEqual:@"initialize"]) self.result.text=@"Controller on. Choose your profile on the TV if asked.";
        else self.result.text=[NSString stringWithFormat:@"%@ launch requested",action];
    };
    _appsButton=[self symbol:@"square.grid.2x2" label:@"Open Kodi" action:@selector(showApps)];
    UIImage *logo=[UIImage imageNamed:@"KodiLogo.png"];
    UIImage *buttonLogo=[UIImage imageWithCGImage:logo.CGImage scale:logo.size.width/24.0 orientation:UIImageOrientationUp];
    [_appsButton setImage:[buttonLogo imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    _appsButton.imageView.contentMode=UIViewContentModeScaleAspectFit;
    _moreButton=[self symbol:@"ellipsis" label:@"Console connection" action:@selector(showConnection)];
    for(UIButton *button in @[_appsButton,_moreButton]) { button.backgroundColor=Color(0x25282A); Round(button,11); button.layer.borderWidth=0; }
    _titleLabel=Label(@"PS5 Pad",14,UIFontWeightSemibold,UIColor.whiteColor);
    _statusLabel=Label(@"Connecting…",12,UIFontWeightRegular,Color(0xA5A5A5));
    for(UILabel *label in @[_titleLabel,_statusLabel]) { label.textAlignment=NSTextAlignmentCenter; [_canvas addSubview:label]; }
    _consoleButton=[UIButton buttonWithType:UIButtonTypeCustom]; _consoleButton.accessibilityLabel=@"Initialize PS5 controller";
    [_consoleButton addTarget:self action:@selector(initialize) forControlEvents:UIControlEventTouchUpInside]; [_canvas addSubview:_consoleButton];
    [self padButton:@"L1" label:@"L1" mask:QP_L1 color:0xBBBBBB edge:0];
    [self padButton:@"touchpad" label:@"Touchpad click" mask:QP_TOUCH color:0xEEEEEE edge:0];
    QPButton *ps=[self padButton:@"PS" label:@"PS button; hold for home" mask:QP_PS color:0x171717 edge:0];
    ps.backgroundColor=UIColor.whiteColor; ps.layer.cornerRadius=30;
    [self padButton:@"options" label:@"Options" mask:QP_OPTIONS color:0xEEEEEE edge:0];
    [self padButton:@"R1" label:@"R1" mask:QP_R1 color:0xBBBBBB edge:0];
    _swipe=[QPSwipePad new]; _swipe.pulse=^(uint32_t mask){[weakSelf pulse:mask];}; [_canvas addSubview:_swipe];
    [self padButton:@"triangle" label:@"Triangle" mask:QP_TRIANGLE color:0x56BDA3 edge:-1];
    [self padButton:@"square" label:@"Square" mask:QP_SQUARE color:0xCB8BC4 edge:-1];
    [self padButton:@"circle" label:@"Circle / Back" mask:QP_CIRCLE color:0xD86B77 edge:1];
    NSArray *symbols=@[@"backward.end",@"backward",@"playpause",@"forward",@"forward.end"];
    NSArray *labels=@[@"Previous chapter",@"Seek backward",@"Play / Pause",@"Seek forward",@"Next chapter"];
    for(NSUInteger i=0;i<5;i++) {
        UIButton *button=[self symbol:symbols[i] label:labels[i] action:@selector(mediaAction:)]; button.tag=i;
        [_mediaButtons addObject:button];
    }
    _result=Label(@"",10,UIFontWeightRegular,Color(0xAAAAAA)); _result.textAlignment=NSTextAlignmentCenter;
    _result.numberOfLines=2; [_canvas addSubview:_result]; [self refresh];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; UIEdgeInsets safe=self.view.safeAreaInsets;
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height-safe.top-safe.bottom;
    _canvas.frame=CGRectMake(0,safe.top,w,h);
    _appsButton.frame=CGRectMake(16,12,44,40); _moreButton.frame=CGRectMake(w-60,12,44,40);
    _titleLabel.frame=CGRectMake(66,12,w-132,22); _statusLabel.frame=CGRectMake(66,34,w-132,20);
    _consoleButton.frame=CGRectMake(66,8,w-132,52);
    _buttons[0].frame=CGRectMake(7,82,48,48); _buttons[1].frame=CGRectMake(w*.29-24,82,48,48);
    _buttons[2].frame=CGRectMake(w/2-30,76,60,60);
    _buttons[3].frame=CGRectMake(w*.71-24,82,48,48); _buttons[4].frame=CGRectMake(w-55,82,48,48);
    CGFloat top=155,area=fmax(150,h-top-125);
    _swipe.frame=CGRectMake(57,top,w-114,area);
    _buttons[5].frame=CGRectMake(1,top,55,area/2-4);
    _buttons[6].frame=CGRectMake(1,top+area/2+4,55,area/2-4);
    _buttons[7].frame=CGRectMake(w-56,top,55,area);
    CGFloat unit=(w-28)/5;
    for(NSUInteger i=0;i<_mediaButtons.count;i++) _mediaButtons[i].frame=CGRectMake(14+i*unit,h-75,unit,52);
    _result.frame=CGRectMake(20,h-24,w-40,24);
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(!_host.length && !_didOfferSetup && !self.presentedViewController) { _didOfferSetup=YES; [self findConsole]; }
    else [self resume];
}
- (void)refresh {
    _statusLabel.text=_link.ready?(_link.padReady?@"Controller connected":@"Console online · tap to initialize"):
        (_link.connecting?@"Connecting…":(_host.length?@"Offline · tap to connect":@"Add your PS5"));
    _consoleButton.accessibilityValue=_statusLabel.text;
    BOOL active=_link.ready&&_link.padReady&&!_link.controlBusy; _swipe.active=active;
    for(QPButton *button in _buttons) { button.enabled=active; button.alpha=active?1:.35; if(!active) [button clear]; }
    if(!active) { _pulseMask=0; _pulseGeneration++; }
    for(UIButton *button in _mediaButtons) { button.enabled=active; button.alpha=active?1:.3; }
    UIApplication.sharedApplication.idleTimerDisabled=_link.ready;
}
- (void)updateState {
    uint32_t buttons=_pulseMask;
    for(QPButton *button in _buttons) if(button.down) buttons|=button.mask;
    [_link setState:qp_buttons(buttons)];
}
- (void)clearControls {
    _pulseGeneration++; _pulseMask=0; for(QPButton *button in _buttons) [button clear];
    [_link releaseControls]; [_swipe reset];
}
- (void)pulse:(uint32_t)mask {
    if(!_link.ready||!_link.padReady||_link.controlBusy) return;
    /* End the preceding pulse first so repeated taps never merge into one hold. */
    if(_pulseMask) { _pulseMask=0; [self updateState]; }
    _pulseMask=mask; NSUInteger generation=++_pulseGeneration; [self updateState];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(generation!=self.pulseGeneration) return; self.pulseMask=0; [self updateState];
    });
}
- (void)mediaAction:(UIButton *)button {
    if(!_link.ready||!_link.padReady||_link.controlBusy) return;
    if(button.tag<0||button.tag>4) return;
    [self pulse:qp_kodi_action((unsigned)button.tag)];
    _result.text=@[@"Previous chapter",@"Seek backward",@"Play / Pause",@"Seek forward",@"Next chapter"][button.tag];
}
- (void)showApps {
    [self clearControls];
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"Kodi" message:@"Open Kodi on your PS5. This may interrupt another app's playback." preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *action=[UIAlertAction actionWithTitle:@"Open Kodi" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a; self.result.text=@"Opening Kodi…"; [self.link launchKodi];
    }];
    action.enabled=_link.ready&&_link.supportsControl&&!_link.controlBusy&&_link.kodiInstalled;
    [sheet addAction:action];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)initialize {
    if(!_host.length) { [self findConsole]; return; }
    if(_link.controlBusy||_link.connecting) return; [self clearControls];
    NSString *other=_link.otherController<0?@"Unknown":(_link.otherController?@"Detected at last initialization":@"None at last initialization");
    NSString *text=_link.ready?[NSString stringWithFormat:@"Console service is running.\nOther controller: %@\n\nTurn On reconnects this remote. Choose your profile on the TV if asked. Another controller may turn off.",other]:@"Connect to your console, or load the controller service if its jailbreak and ELF loader are running.";
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"Connect your controller" message:text preferredStyle:UIAlertControllerStyleAlert];
    if(_link.ready&&_link.supportsControl) [sheet addAction:[UIAlertAction actionWithTitle:@"Turn On Controller" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ (void)a; [self.link initializeController]; }]];
    else if(!_link.ready) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Connect" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ (void)a; self.wantsConnection=YES; [self resume]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Load Controller Service" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ (void)a; self.wantsConnection=YES; [self.link loadServiceAt:self.host]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)showConnection {
    [self clearControls];
    NSString *detail=[NSString stringWithFormat:@"%@\n%@",_host?:@"No console added",_link.message?:@""];
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"PS5 connection" message:detail preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Initialize Controller" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a; dispatch_async(dispatch_get_main_queue(),^{[self initialize];});
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:(_link.ready||_link.connecting)?@"Disconnect":@"Connect" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a; if(self.link.ready||self.link.connecting) { self.wantsConnection=NO; [self.link disconnect:@"Disconnected"]; }
        else { self.wantsConnection=YES; [self resume]; }
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Find / Add PS5" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a; dispatch_async(dispatch_get_main_queue(),^{[self findConsole];});
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)findConsole {
    if(self.presentedViewController) return;
    [self clearControls]; [_link disconnect:@"Choose a console"]; _wantsConnection=NO;
    QPDiscoveryController *finder=[QPDiscoveryController new]; __weak QPViewController *weakSelf=self;
    finder.added=^(NSString *host){
        QPViewController *self=weakSelf; if(!self) return;
        self.host=host; [NSUserDefaults.standardUserDefaults setObject:host forKey:@"consoleHost"];
        self.wantsConnection=YES; self.result.text=@"Console added. Tap its status to turn on the controller."; [self resume];
    };
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:finder];
    navigation.modalPresentationStyle=UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)resume { if(_host.length&&_wantsConnection&&!_link.ready&&!_link.connecting&&self.isViewLoaded&&!self.presentedViewController) [_link connectTo:_host]; }
- (void)suspend { [self clearControls]; [_link disconnect:@"Paused in the background"]; UIApplication.sharedApplication.idleTimerDisabled=NO; }
@end

@interface QPSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) QPViewController *controller;
@end
@implementation QPSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    if(![scene isKindOfClass:UIWindowScene.class]) return;
    _window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    _window.frame=((UIWindowScene *)scene).coordinateSpace.bounds;
    _controller=[QPViewController new]; _window.rootViewController=_controller; [_window makeKeyAndVisible];
}
- (void)sceneWillResignActive:(UIScene *)scene { (void)scene; [_controller suspend]; }
- (void)sceneDidBecomeActive:(UIScene *)scene { (void)scene; [_controller resume]; }
- (void)sceneDidDisconnect:(UIScene *)scene { (void)scene; [_controller suspend]; }
@end

@interface QPAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation QPAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options; return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)application; (void)options;
    UISceneConfiguration *config=[[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
    config.delegateClass=QPSceneDelegate.class; return config;
}
@end

int main(int argc,char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(QPAppDelegate.class)); }
}
