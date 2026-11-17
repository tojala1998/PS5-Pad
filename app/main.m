#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <arpa/inet.h>
#import "QPConnection.h"
#import "QPKodi.h"
#import "QPDiscovery.h"
#import "QPInitialization.h"
#import "QPInputFeedback.h"
#import "QPLifecycle.h"

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

@interface QPButton : UIControl {
    QPButtonFeedback _feedback;
    BOOL _trackingPress;
    NSUInteger _desiredGeneration;
}
@property(nonatomic) uint32_t mask;
@property(nonatomic) NSInteger edge;
@property(nonatomic) BOOL down;
@property(nonatomic,copy) NSString *glyph;
@property(nonatomic,strong) UIColor *ink;
@property(nonatomic,copy) void (^changed)(void);
@property(nonatomic,copy) void (^cancelled)(void);
- (void)acknowledgeDown:(BOOL)down;
- (void)clearFeedback;
- (void)clear;
@end
@implementation QPButton
- (instancetype)init {
    if((self=[super init])) {
        self.backgroundColor=UIColor.clearColor; self.opaque=NO; self.clipsToBounds=YES;
        self.contentMode=UIViewContentModeRedraw;
        _ink=Color(0xD8DEE7); Round(self,14); self.layer.borderWidth=0;
        self.isAccessibilityElement=YES; self.accessibilityTraits=UIAccessibilityTraitButton;
    } return self;
}
- (void)setDown:(BOOL)down {
    if(_down==down) return; _down=down;
    /* Desired input never paints or vibrates; the matching service ACK does. */
    if(_changed) _changed();
}
- (void)refreshFeedback {
    BOOL lit=qp_feedback_visible(&_feedback,CACurrentMediaTime());
    self.backgroundColor=[_glyph isEqual:@"PS"]?(lit?Color(0xA4C5FA):UIColor.whiteColor):(lit?Color(0x292D35):UIColor.clearColor);
    self.layer.borderColor=(lit?Accent():Color(0x293039)).CGColor;
    self.accessibilityValue=_feedback.acknowledgedDown?@"Registered":@"Released";
    [self setNeedsDisplay];
}
- (void)acknowledgeDown:(BOOL)down {
    BOOL previous=_feedback.acknowledgedDown;
    BOOL rising=qp_feedback_acknowledge(&_feedback,down,CACurrentMediaTime());
    if(previous==down && !rising) return;
    [self refreshFeedback];
    if(!rising) return;
    /* Animate only the paint, never the UIControl's geometry. Each rising edge
     * restarts this flash even when a fast repeat overlaps the preceding one. */
    CABasicAnimation *flash=[CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    flash.fromValue=(__bridge id)([_glyph isEqual:@"PS"]?Color(0xE4EFFF):Color(0x42618A)).CGColor;
    flash.toValue=(__bridge id)self.backgroundColor.CGColor; flash.duration=QP_FEEDBACK_FLASH_SECONDS;
    [self.layer addAnimation:flash forKey:@"registeredPress"];
    UIImpactFeedbackGenerator *h=[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft]; [h impactOccurred];
    uint64_t generation=_feedback.generation; __weak QPButton *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(QP_FEEDBACK_FLASH_SECONDS*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        QPButton *button=weakSelf;
        if(button && qp_feedback_timer_is_current(&button->_feedback,generation)) [button refreshFeedback];
    });
}
- (void)clearFeedback {
    qp_feedback_reset(&_feedback); [self.layer removeAnimationForKey:@"registeredPress"]; [self refreshFeedback];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if(!self.enabled || ![self pointInside:[touch locationInView:self] withEvent:event]) return NO;
    _trackingPress=YES; _desiredGeneration++; self.down=YES; return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if(!self.enabled || !_trackingPress) return NO;
    self.down=[self pointInside:[touch locationInView:self] withEvent:event]; return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)touch; (void)event; _trackingPress=NO; _desiredGeneration++; self.down=NO;
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {
    (void)event; _trackingPress=NO; _desiredGeneration++; self.down=NO; [self clearFeedback];
    if(_cancelled) _cancelled();
}
- (void)clear {
    /* The owner releases the aggregate report; do not queue intermediate chords
     * while it is clearing several controls or disabling the connection. */
    _down=NO; _trackingPress=NO; _desiredGeneration++; [self clearFeedback];
}
- (BOOL)accessibilityActivate {
    if(!self.enabled) return NO;
    if(_down) self.down=NO;
    NSUInteger generation=++_desiredGeneration; self.down=YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(generation==self->_desiredGeneration) self.down=NO;
    }); return YES;
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


@interface QPSwipePad : UIView {
    QPButtonFeedback _crossFeedback;
    uint32_t _acknowledgedDirections;
}
@property(nonatomic,copy) void (^pulse)(uint32_t);
@property(nonatomic,copy) void (^cancelled)(void);
@property(nonatomic) BOOL active;
@property(nonatomic,strong) UILabel *hint,*sub,*cross;
@property(nonatomic,strong) UIView *cursor;
@property(nonatomic) CFTimeInterval lastStep;
- (void)acknowledgeButtons:(uint32_t)buttons;
- (void)clearFeedback;
- (void)reset;
@end
@implementation QPSwipePad
- (instancetype)init {
    if((self=[super init])) {
        self.backgroundColor=UIColor.clearColor;
        _cross=Label(@"×",35,UIFontWeightMedium,Color(0x9DBFF3));
        _cross.layer.cornerRadius=12; _cross.clipsToBounds=YES;
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
    _cross.frame=CGRectMake(w/2-24,y-47,48,40); _hint.frame=CGRectMake(0,y-2,w,20); _sub.frame=CGRectMake(0,y+15,w,20);
}
- (void)setActive:(BOOL)active {
    _active=active; self.alpha=active?1:.45; if(!active) { [self reset]; [self clearFeedback]; }
}
- (void)refreshCrossFeedback {
    BOOL lit=qp_feedback_visible(&_crossFeedback,CACurrentMediaTime());
    _cross.backgroundColor=lit?Color(0x292D35):UIColor.clearColor;
    _cross.textColor=lit?UIColor.whiteColor:Color(0x9DBFF3);
    self.accessibilityValue=_crossFeedback.acknowledgedDown?@"Cross registered":@"Released";
}
- (void)acknowledgeButtons:(uint32_t)buttons {
    BOOL previous=_crossFeedback.acknowledgedDown;
    BOOL cross=qp_feedback_acknowledge(&_crossFeedback,(buttons&QP_CROSS)!=0,CACurrentMediaTime());
    uint32_t directions=buttons&(QP_UP|QP_DOWN|QP_LEFT|QP_RIGHT);
    uint32_t risingDirections=directions&~_acknowledgedDirections; _acknowledgedDirections=directions;
    if(previous!=_crossFeedback.acknowledgedDown || cross) [self refreshCrossFeedback];
    if(cross || risingDirections) [[UISelectionFeedbackGenerator new] selectionChanged];
    if(!cross) return;
    CABasicAnimation *flash=[CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    flash.fromValue=(__bridge id)Color(0x42618A).CGColor;
    flash.toValue=(__bridge id)_cross.backgroundColor.CGColor; flash.duration=QP_FEEDBACK_FLASH_SECONDS;
    [_cross.layer addAnimation:flash forKey:@"registeredPress"];
    uint64_t generation=_crossFeedback.generation; __weak QPSwipePad *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(QP_FEEDBACK_FLASH_SECONDS*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        QPSwipePad *pad=weakSelf;
        if(pad && qp_feedback_timer_is_current(&pad->_crossFeedback,generation)) [pad refreshCrossFeedback];
    });
}
- (void)clearFeedback {
    qp_feedback_reset(&_crossFeedback); _acknowledgedDirections=0;
    [_cross.layer removeAnimationForKey:@"registeredPress"]; [self refreshCrossFeedback];
}
- (void)emit:(uint32_t)mask { if(!_active||!_pulse) return; _pulse(mask); }
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
    } else {
        [self reset];
        if((gesture.state==UIGestureRecognizerStateCancelled || gesture.state==UIGestureRecognizerStateFailed) && _cancelled) _cancelled();
    }
}
- (void)reset { _cursor.alpha=0; }
- (BOOL)accessibilityActivate { [self emit:QP_CROSS]; return _active; }
- (BOOL)accessUp { [self emit:QP_UP]; return _active; }
- (BOOL)accessDown { [self emit:QP_DOWN]; return _active; }
- (BOOL)accessLeft { [self emit:QP_LEFT]; return _active; }
- (BOOL)accessRight { [self emit:QP_RIGHT]; return _active; }
@end

@interface QPKeyboardController : UIViewController <UITextFieldDelegate>
@property(nonatomic,strong) QPConnection *link;
@property(nonatomic,strong) UITextField *field;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) BOOL ending;
@end
@implementation QPKeyboardController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Keyboard";self.view.backgroundColor=Color(0x151718);
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(closeEditor)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Enter" style:UIBarButtonItemStyleDone target:self action:@selector(submitEditor)];
    UILabel *help=Label(@"Open a text field on the TV. Text below types live into that field. Enter submits it; Close disconnects without Enter.",15,UIFontWeightRegular,Color(0xAAAAAA));help.numberOfLines=0;
    _status=Label(@"Connecting keyboard…",14,UIFontWeightMedium,Color(0x53D889));_status.numberOfLines=0;
    _field=[UITextField new];_field.textColor=UIColor.whiteColor;_field.backgroundColor=Color(0x25282A);
    _field.borderStyle=UITextBorderStyleRoundedRect;_field.placeholder=@"Type here…";_field.font=[UIFont systemFontOfSize:20];
    _field.delegate=self;_field.autocorrectionType=UITextAutocorrectionTypeNo;_field.autocapitalizationType=UITextAutocapitalizationTypeNone;
    _field.smartQuotesType=UITextSmartQuotesTypeNo;_field.smartDashesType=UITextSmartDashesTypeNo;_field.spellCheckingType=UITextSpellCheckingTypeNo;
    _field.keyboardType=UIKeyboardTypeASCIICapable;_field.returnKeyType=UIReturnKeySend;_field.enabled=NO;
    [_field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[help,_field,_status]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=20;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:stack];[NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [_field.heightAnchor constraintEqualToConstant:52]]];
    self.modalInPresentation=YES;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];[_link openKeyboard];
    __weak QPKeyboardController *weakSelf=self;
    _timer=[NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer){
        (void)timer;[weakSelf updateEditor];
    }];[self updateEditor];
}
- (void)updateEditor {
    _status.text=_link.keyboardMessage?:@"Keyboard unavailable";
    BOOL enabled=_link.keyboardActive&&_link.keyboardConnected&&!_link.keyboardClosing&&!_ending;
    if(enabled&&!_field.enabled){_field.enabled=YES;[_field becomeFirstResponder];}else _field.enabled=enabled;
    self.navigationItem.rightBarButtonItem.enabled=enabled;
    if(!_link.ready || (_ending&&!_link.keyboardActive)) [self dismissViewControllerAnimated:YES completion:nil];
}
- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)text {
    NSString *value=[field.text?:@"" stringByReplacingCharactersInRange:range withString:text];
    NSData *bytes=[value dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];
    if(!bytes||bytes.length>128)return NO;
    const uint8_t *p=bytes.bytes;for(NSUInteger i=0;i<bytes.length;i++)if(p[i]<32||p[i]>126)return NO;
    return YES;
}
- (void)textChanged { [_link updateKeyboardText:_field.text?:@""]; }
- (BOOL)textFieldShouldReturn:(UITextField *)field {(void)field;[self submitEditor];return NO;}
- (void)submitEditor {if(_ending)return;[self textChanged];_ending=YES;[_field resignFirstResponder];[_link closeKeyboardWithEnter:YES];[self updateEditor];}
- (void)closeEditor {_ending=YES;_field.text=@"";[_link closeKeyboardWithEnter:NO];[self dismissViewControllerAnimated:YES completion:nil];}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];[_timer invalidate];_timer=nil;_field.text=@"";
    if(!_ending) [_link closeKeyboardWithEnter:NO];
}
@end

@interface QPViewController : UIViewController {
    QPInitialization _initialization;
    QPEnsureSession _ensureSession;
    QPLifecycle _lifecycle;
}
@property(nonatomic,strong) QPConnection *link;
@property(nonatomic,strong) UIView *canvas;
@property(nonatomic,strong) UILabel *titleLabel,*statusLabel,*result;
@property(nonatomic,strong) UIButton *consoleButton,*appsButton,*moreButton;
@property(nonatomic,strong) QPSwipePad *swipe;
@property(nonatomic,strong) NSMutableArray<QPButton *> *buttons;
@property(nonatomic,strong) NSMutableArray<UIButton *> *mediaButtons;
@property(nonatomic,copy) NSString *host;
@property(nonatomic) uint32_t pulseMask;
@property(nonatomic) NSUInteger pulseGeneration,kodiIconGeneration;
@property(nonatomic) BOOL kodiIconStateKnown,kodiIconHidden,mediaWasActive;
@property(nonatomic) BOOL wantsConnection;
@property(nonatomic) BOOL didOfferSetup;
@property(nonatomic) BOOL needsInitializePrompt,initializePromptScheduled;
@property(nonatomic) BOOL showingLinkProgress;
@property(nonatomic) BOOL initializationWorkScheduled,autoInitializeAttempted,ensureSessionScheduled,reusedController;
@property(nonatomic) NSUInteger ensureSessionGeneration;
@property(nonatomic,copy) NSString *sessionIdentifier,*lifecycleBlockedReason;
@property(nonatomic) NSUInteger initializationRequests,initializationSends,initializationLoads;
@property(nonatomic,copy) NSString *initializationFailure;
@property(nonatomic,strong) UIView *connectionBar;
@property(nonatomic) BOOL connectionBarBusy,connectionWasReady;
@property(nonatomic) NSUInteger connectionBarGeneration;
@property(nonatomic,strong) UILabel *initializeHint;
- (void)resume;
- (void)activateScene;
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
    /* UIKit cancellation ends this input session; normal touch-end does not. */
    button.cancelled=^{[weakSelf clearControls];};
    [_buttons addObject:button]; [_canvas addSubview:button]; return button;
}
- (void)viewDidLoad {
    [super viewDidLoad]; _sessionIdentifier=NSUUID.UUID.UUIDString; _lifecycleBlockedReason=@"Waiting for scene activation"; self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.view.backgroundColor=Color(0x171717); _canvas=[UIView new]; [self.view addSubview:_canvas];
    _buttons=[NSMutableArray array]; _mediaButtons=[NSMutableArray array]; _link=[QPConnection new];
    _host=[NSUserDefaults.standardUserDefaults stringForKey:@"consoleHost"];
    _needsInitializePrompt=NO; /* Saved consoles resume their existing controller. */
    _wantsConnection=![NSProcessInfo.processInfo.arguments containsObject:@"--offline"];
    __weak QPViewController *weakSelf=self;
    _link.changed=^{[weakSelf refresh];};
    _link.inputAcknowledged=^(uint32_t buttons) {
        QPViewController *self=weakSelf; if(!self) return;
        for(QPButton *button in self.buttons) [button acknowledgeDown:(buttons&button.mask)!=0];
        [self.swipe acknowledgeButtons:buttons];
    };
    _link.inputFeedbackReset=^{
        QPViewController *self=weakSelf; if(!self) return;
        for(QPButton *button in self.buttons) [button clearFeedback];
        [self.swipe clearFeedback];
    };
    _link.completed=^(NSString *action,int32_t status) {
        QPViewController *self=weakSelf; if(!self) return;
        if([action isEqual:@"initialize"]) {
            if(self.link.disconnectingController) return;
            qp_initialization_complete(&self->_initialization,status==0);
            self.initializationFailure=status?self.link.message:nil;
            self.result.text=self.link.message;
        } else if([action isEqual:@"handoff"]) {
            [self cancelEnsureSession]; qp_initialization_cancel(&self->_initialization);
            self.wantsConnection=NO; self.autoInitializeAttempted=YES; self.needsInitializePrompt=NO;
            self.showingLinkProgress=YES;
        } else if([action isEqual:@"disconnect_controller"]) {
            qp_initialization_cancel(&self->_initialization); self.showingLinkProgress=YES;
            self.result.text=self.link.message;
        } else if([action isEqual:@"check"]) {
            self.autoInitializeAttempted=YES;
            if(qp_initialization_pending(&self->_initialization)) {
                qp_initialization_complete(&self->_initialization,NO); self.initializationFailure=self.link.message;
            }
            self.result.text=self.link.message;
        }
        else if([action isEqual:@"power_off"]) self.result.text=self.link.message;
        else if([action isEqual:@"keyboard"]) self.result.text=self.link.message;
        else if(status) self.result.text=[NSString stringWithFormat:@"%@ failed (0x%08X)",action,(unsigned)status];
        else self.result.text=[NSString stringWithFormat:@"%@ launch requested",action];
    };
    _appsButton=[self symbol:@"square.grid.2x2" label:@"Open Kodi" action:@selector(showApps)];
    UIImage *logo=[UIImage imageNamed:@"KodiLogo.png"];
    UIImage *buttonLogo=[UIImage imageWithCGImage:logo.CGImage scale:logo.size.width/24.0 orientation:UIImageOrientationUp];
    [_appsButton setImage:[buttonLogo imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    _appsButton.imageView.contentMode=UIViewContentModeScaleAspectFit;
    _appsButton.alpha=0;_appsButton.enabled=NO;_appsButton.accessibilityElementsHidden=YES;
    _moreButton=[self symbol:@"ellipsis" label:@"Console connection" action:@selector(showConnection)];
    for(UIButton *button in @[_appsButton,_moreButton]) { button.backgroundColor=Color(0x25282A); Round(button,11); button.layer.borderWidth=0; }
    _titleLabel=Label(@"PS5 Pad",14,UIFontWeightSemibold,UIColor.whiteColor);
    _statusLabel=Label(@"Connecting…",12,UIFontWeightRegular,Color(0xA5A5A5));
    for(UILabel *label in @[_titleLabel,_statusLabel]) { label.textAlignment=NSTextAlignmentCenter; [_canvas addSubview:label]; }
    _consoleButton=[UIButton buttonWithType:UIButtonTypeCustom]; _consoleButton.accessibilityLabel=@"Initialize PS5 controller";
    [_consoleButton addTarget:self action:@selector(requestInitialization) forControlEvents:UIControlEventTouchUpInside]; [_canvas addSubview:_consoleButton];
    [self padButton:@"L1" label:@"L1" mask:QP_L1 color:0xBBBBBB edge:0];
    [self padButton:@"touchpad" label:@"Touchpad click" mask:QP_TOUCH color:0xEEEEEE edge:0];
    QPButton *ps=[self padButton:@"PS" label:@"PS button; hold for home" mask:QP_PS color:0x171717 edge:0];
    ps.backgroundColor=UIColor.whiteColor; ps.layer.cornerRadius=30;
    [self padButton:@"options" label:@"Options" mask:QP_OPTIONS color:0xEEEEEE edge:0];
    [self padButton:@"R1" label:@"R1" mask:QP_R1 color:0xBBBBBB edge:0];
    _swipe=[QPSwipePad new]; _swipe.pulse=^(uint32_t mask){[weakSelf pulse:mask];};
    _swipe.cancelled=^{[weakSelf clearControls];}; [_canvas addSubview:_swipe];
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
    _initializeHint=Label(@"If another controller takes over, use ••• → Initialize Controller.",11,UIFontWeightRegular,Color(0x999999));
    _connectionBar=[UIView new]; _connectionBar.backgroundColor=Color(0x53D889);
    _connectionBar.layer.cornerRadius=1.5; _connectionBar.hidden=YES; [_canvas addSubview:_connectionBar];
    _initializeHint.numberOfLines=2; _initializeHint.textAlignment=NSTextAlignmentCenter; [_canvas addSubview:_initializeHint];
    qp_lifecycle_view_ready(&_lifecycle); [self scheduleActivation];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; UIEdgeInsets safe=self.view.safeAreaInsets;
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height-safe.top-safe.bottom;
    _canvas.frame=CGRectMake(0,safe.top,w,h);
    _appsButton.bounds=CGRectMake(0,0,44,40);_appsButton.center=CGPointMake(38,32); _moreButton.frame=CGRectMake(w-60,12,44,40);
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
    _initializeHint.frame=CGRectMake(35,h-118,w-70,38);
    _connectionBar.frame=CGRectMake(w/2-40,57,80,3);
    CGFloat unit=(w-28)/5;
    for(NSUInteger i=0;i<_mediaButtons.count;i++) _mediaButtons[i].frame=CGRectMake(14+i*unit,h-75,unit,52);
    _result.frame=CGRectMake(20,h-24,w-40,24);
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self scheduleActivation]; [self resume];
}
- (void)updateConnectionIndicator {
    BOOL ready=_link.ready&&_link.padReady&&_link.profileAssigned;
    BOOL busy=_ensureSession.active||_link.connecting||qp_initialization_pending(&_initialization);
    if(busy && !_connectionBarBusy) {
        _connectionBarGeneration++; [_connectionBar.layer removeAllAnimations];
        _connectionBar.hidden=NO; _connectionBar.alpha=1;
        CABasicAnimation *pulse=[CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue=@0.25; pulse.toValue=@1; pulse.duration=.6;
        pulse.autoreverses=YES; pulse.repeatCount=HUGE_VALF;
        [_connectionBar.layer addAnimation:pulse forKey:@"connecting"];
    } else if(!busy && ready && !_connectionWasReady) {
        NSUInteger generation=++_connectionBarGeneration;
        [_connectionBar.layer removeAllAnimations]; _connectionBar.hidden=NO; _connectionBar.alpha=1;
        [UIView animateWithDuration:.55 delay:.2 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.connectionBar.alpha=0;
        } completion:^(BOOL finished){
            (void)finished; if(generation==self.connectionBarGeneration) self.connectionBar.hidden=YES;
        }];
    } else if(!busy && (!ready || _connectionBarBusy)) {
        _connectionBarGeneration++; [_connectionBar.layer removeAllAnimations]; _connectionBar.hidden=YES;
    }
    _connectionBarBusy=busy; _connectionWasReady=ready;
}
- (void)updateKodiShortcut {
    BOOL fresh=_link.appStateFresh&&_link.kodiRunningKnown;
    _appsButton.enabled=fresh&&!_link.kodiRunning&&_link.kodiInstalled&&_link.profileAssigned&&!_link.controlBusy;
    if(!fresh) { _appsButton.accessibilityElementsHidden=YES;return; }
    BOOL hide=_link.kodiRunning;
    if(_kodiIconStateKnown&&hide==_kodiIconHidden) { _appsButton.accessibilityElementsHidden=hide;return; }
    _kodiIconStateKnown=YES;_kodiIconHidden=hide;NSUInteger generation=++_kodiIconGeneration;
    _appsButton.accessibilityElementsHidden=hide;_appsButton.hidden=NO;
    if(!hide&&_appsButton.alpha<0.01)_appsButton.transform=CGAffineTransformMakeScale(.65,.65);
    [UIView animateWithDuration:hide?.22:.32 delay:0 usingSpringWithDamping:hide?1:.72 initialSpringVelocity:0
        options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{
            self.appsButton.alpha=hide?0:1;
            self.appsButton.transform=hide?CGAffineTransformMakeScale(.65,.65):CGAffineTransformIdentity;
        } completion:^(BOOL finished){(void)finished;if(generation==self.kodiIconGeneration)self.appsButton.hidden=hide;}];
}
- (void)refresh {
    if(_ensureSession.active && _link.ready) [self cancelEnsureSession];
    if(_initialization.phase==QP_INIT_DONE && (!_link.ready || !_link.padReady)) { qp_initialization_cancel(&_initialization); _showingLinkProgress=YES; }
    BOOL pending=qp_initialization_pending(&_initialization);
    NSString *progress=nil;
    if(_initialization.phase==QP_INIT_WAITING) progress=_link.ready?@"Checking controller…":(_initialization.loaded?_link.message:@"Connecting to service…");
    else if(_initialization.phase==QP_INIT_SENT) progress=@"Initializing controller…";
    else if(_initialization.phase==QP_INIT_DONE) progress=_link.waitingForProfile?@"Choose your profile on the TV…":_link.message;
    else if(_initialization.phase==QP_INIT_FAILED) progress=_initializationFailure?:_link.message;
    _statusLabel.text=_ensureSession.active?(_ensureSession.loaded?_link.message:@"Reconnecting…"):(_link.disconnectingController?@"Disconnecting controller…":(pending?progress:(_link.controlBusy?_link.message:(_link.ready?(_link.waitingForProfile?@"Choose your profile on TV":(_link.profileAssigned?@"Controller ready":(_link.padReady?@"Controller connected":@"Service connected · use •••"))):
        (_link.connecting?@"Connecting…":(_host.length?(_link.failureKind!=QPConnectionFailureNone?@"Connection failed · use •••":@"Offline · use •••"):@"Add your PS5"))))));
    if(_ensureSession.active) _result.text=_ensureSession.loaded?_link.message:@"Reconnecting to your existing controller…";
    else if(progress) _result.text=progress;
    else if(!_link.ready || _link.controlBusy) { _showingLinkProgress=YES; _result.text=_link.message; }
    else if(_showingLinkProgress) { _showingLinkProgress=NO; _result.text=_link.message; }
    _initializeHint.hidden=_link.profileAssigned;
    [self updateConnectionIndicator];
    _consoleButton.accessibilityValue=_statusLabel.text; _consoleButton.enabled=!_link.disconnectingController&&!_ensureSession.active;
    BOOL active=_wantsConnection&&_link.ready&&_link.padReady&&!_link.controlBusy&&!_link.disconnectingController&&!pending; _swipe.active=active;
    for(QPButton *button in _buttons) { BOOL allowed=active&&(!_link.waitingForProfile || !(button.mask&~0x60F0u)); button.enabled=allowed; button.alpha=allowed?1:.35; if(!allowed) [button clear]; }
    if(!active) { _pulseMask=0; _pulseGeneration++; }
    BOOL mediaActive=active&&_link.profileAssigned&&_link.appStateFresh&&_link.kodiFocused;
    BOOL lostMedia=_mediaWasActive&&!mediaActive;_mediaWasActive=mediaActive;
    if(lostMedia) [self clearControls];
    for(UIButton *button in _mediaButtons) {button.enabled=mediaActive;button.alpha=mediaActive?1:.3;}
    [self updateKodiShortcut];
    UIApplication.sharedApplication.idleTimerDisabled=NO;
    [self offerInitializationIfReady];
    NSDictionary *record=@{@"session_id":_sessionIdentifier?:@"",@"process_id":@(NSProcessInfo.processInfo.processIdentifier),
        @"host":_host?:@"",@"wants_connection":@(_wantsConnection),@"scene_active":@(_lifecycle.active),@"view_ready":@(_lifecycle.viewReady),
        @"activation_queued":@(_lifecycle.queued),@"activation_started":@(_lifecycle.started),@"activation_generation":@(_lifecycle.generation),
        @"activation_count":@(_lifecycle.activations),@"suspend_count":@(_lifecycle.suspends),@"activation_start_count":@(_lifecycle.starts),
        @"blocked_reason":_lifecycleBlockedReason?:@"",@"phase":@(_initialization.phase),@"requests":@(_initializationRequests),@"init_sent":@(_initializationSends),
        @"service_loads":@(_initializationLoads),@"loaded_this_request":@(_initialization.loaded),@"allows_load":@(_initialization.allowLoad),
        @"auto_attempted":@(_autoInitializeAttempted),@"automatic_session_active":@(_ensureSession.active),
        @"automatic_connect_attempts":@(_ensureSession.attempts),@"automatic_service_loaded":@(_ensureSession.loaded),@"automatic_load_blocked":@(_ensureSession.loadBlocked),@"reused_controller":@(_reusedController),@"failure":_initializationFailure?:@"",@"updated_unix":@(NSDate.date.timeIntervalSince1970)};
    NSString *file=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"PS5Pad-initialization.json"];
    [[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:nil] writeToFile:file atomically:YES];
    [self scheduleInitialization];
    [self scheduleEnsureSession];
}
- (void)cancelEnsureSession {
    qp_ensure_cancel(&_ensureSession); _ensureSessionGeneration++; _ensureSessionScheduled=NO;
}
- (void)startEnsureSession {
    if(!_lifecycle.active || !_lifecycle.viewReady) { _lifecycleBlockedReason=@"Waiting for active scene and loaded view"; return; }
    if(!_host.length || !_wantsConnection || qp_initialization_pending(&_initialization) || _link.disconnectingController) {
        _lifecycleBlockedReason=!_host.length?@"No console selected":(!_wantsConnection?@"Connection disabled by user":@"Explicit controller action in progress");
        [self refresh]; return;
    }
    [self cancelEnsureSession]; _lifecycleBlockedReason=@"";
    _reusedController=NO; _autoInitializeAttempted=NO;
    if(_link.ready) { [self offerInitializationIfReady]; return; }
    qp_ensure_begin(&_ensureSession); [self refresh];
}
- (void)scheduleEnsureSession {
    if(!_ensureSession.active || _ensureSessionScheduled) return;
    _ensureSessionScheduled=YES; NSUInteger generation=_ensureSessionGeneration;
    dispatch_async(dispatch_get_main_queue(),^{
        if(generation!=self.ensureSessionGeneration) return;
        self.ensureSessionScheduled=NO;
        if(!self.wantsConnection || !self.host.length || qp_initialization_pending(&self->_initialization) || self.link.disconnectingController ||
           !self->_lifecycle.active) { [self cancelEnsureSession]; return; }
        if(self.link.ready) { [self cancelEnsureSession]; [self refresh]; return; }
        if(self.link.connecting) {
            /* Adopt a connection already started during initial scene setup. */
            if(!self->_ensureSession.attempts) { self->_ensureSession.attempts=1; [self.link limitConnectWait:3]; }
            return;
        }
        unsigned delay=0;
        QPEnsureAction action=qp_ensure_next(&self->_ensureSession,self.link.failureKind==QPConnectionFailureUnavailable,&delay);
        if(action==QP_ENSURE_STOP) { [self cancelEnsureSession]; [self refresh]; return; }
        if(action==QP_ENSURE_LOAD) { [self.link loadServiceAt:self.host]; return; }
        if(!delay) { [self.link connectTo:self.host timeout:3]; return; }
        self.ensureSessionScheduled=YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)delay*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if(generation!=self.ensureSessionGeneration) return;
            self.ensureSessionScheduled=NO;
            if(!self->_ensureSession.active || !self.wantsConnection || qp_initialization_pending(&self->_initialization) || self.link.disconnectingController ||
               !self->_lifecycle.active) { [self cancelEnsureSession]; return; }
            if(self.link.ready) { [self cancelEnsureSession]; [self refresh]; return; }
            if(self.link.connecting) { [self scheduleEnsureSession]; return; }
            [self.link connectTo:self.host timeout:3];
        });
    });
}
- (void)scheduleInitialization {
    if(!qp_initialization_pending(&_initialization) || _initializationWorkScheduled) return;
    _initializationWorkScheduled=YES;
    dispatch_async(dispatch_get_main_queue(),^{
        self.initializationWorkScheduled=NO;
        if(!self->_lifecycle.active) { qp_initialization_cancel(&self->_initialization); return; }
        /* connectTo/loadServiceAt synchronously publish a temporary disconnect.
         * Reading on the next turn observes their completed state mutation. */
        QPInitAction action=qp_initialization_step(&self->_initialization,self.link.ready,self.link.connecting,
            self.link.controlBusy,self.link.supportsControl,self.link.failureKind==QPConnectionFailureUnavailable);
        if(action==QP_INIT_CONNECT) [self.link connectTo:self.host timeout:3];
        else if(action==QP_INIT_LOAD) { self.initializationLoads++; [self.link loadServiceAt:self.host]; }
        else if(action==QP_INIT_SEND) { self.initializationSends++; [self.link initializeController]; }
        else if(action==QP_INIT_FAIL) {
            self.initializationFailure=self.link.ready&&!self.link.supportsControl?@"This service does not support initialization.":self.link.message;
            [self refresh];
        }
    });
}
- (void)beginInitializationAllowLoad:(BOOL)allowLoad {
    if(_link.disconnectingController) return;
    if(!_lifecycle.active) return;
    if(!_host.length) {
        if(self.presentedViewController) [self dismissViewControllerAnimated:YES completion:^{ [self findConsole]; }];
        else [self findConsole];
        return;
    }
    if(!qp_initialization_request(&_initialization,allowLoad)) return;
    BOOL cancelLoader=_ensureSession.active&&_ensureSession.loaded&&!_link.ready;
    [self cancelEnsureSession];
    if(cancelLoader) [_link disconnect:@"Preparing controller…"];
    _reusedController=NO;
    _initializationRequests++; [_link limitConnectWait:3];
    _autoInitializeAttempted=YES; _needsInitializePrompt=NO; _initializationFailure=nil; _wantsConnection=YES;
    [self clearControls]; [self refresh];
}
- (void)requestInitialization { [self beginInitializationAllowLoad:YES]; }
- (void)offerInitializationIfReady {
    if(!_wantsConnection || _link.disconnectingController || !self.view.window || self.presentedViewController || !_lifecycle.active ||
       qp_initialization_pending(&_initialization)) return;
    if(qp_resume_reuses_controller(_link.ready,_link.controllerChecked,_link.padReady&&(!_link.supportsOwnership||_link.profileAssigned),_link.controlBusy)) {
        _needsInitializePrompt=NO;
        if(_initialization.phase==QP_INIT_IDLE && !_autoInitializeAttempted) _reusedController=YES;
        return;
    }
    if(_link.waitingForProfile) { _needsInitializePrompt=NO; return; }
    if(_link.supportsOwnership&&!_link.monitorReady) return;
    if(qp_should_auto_initialize(_autoInitializeAttempted,_link.ready,_link.controllerChecked,_link.padReady,_link.controlBusy,_link.supportsControl,(int)_link.userStatus)) {
        [self beginInitializationAllowLoad:NO]; return;
    }
    if(!_needsInitializePrompt || _initializePromptScheduled || !_link.ready || !_link.supportsControl || _link.controlBusy) return;
    _initializePromptScheduled=YES;
    dispatch_async(dispatch_get_main_queue(),^{
        self.initializePromptScheduled=NO;
        if(!self.needsInitializePrompt || !self.link.ready || !self.link.supportsControl || self.link.controlBusy ||
           qp_initialization_pending(&self->_initialization) || !self.view.window || self.presentedViewController ||
           !self->_lifecycle.active) return;
        [self offerInitialization];
    });
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
    if(!button.enabled||!_link.ready||!_link.padReady||!_link.profileAssigned||_link.controlBusy||!_link.appStateFresh||!_link.kodiFocused) return;
    if(button.tag<0||button.tag>4) return;
    [self pulse:qp_kodi_action((unsigned)button.tag)];
    _result.text=@[@"Previous chapter",@"Seek backward",@"Play / Pause",@"Seek forward",@"Next chapter"][button.tag];
}
- (void)showApps {
    if(!_link.appStateFresh||!_link.kodiRunningKnown||_link.kodiRunning)return;
    [self clearControls];
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"Kodi" message:@"Open Kodi on your PS5. This may interrupt another app's playback." preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *action=[UIAlertAction actionWithTitle:@"Open Kodi" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a; if(!self.link.appStateFresh||!self.link.kodiRunningKnown||self.link.kodiRunning)return;
        self.result.text=@"Opening Kodi…"; [self.link launchKodi];
    }];
    action.enabled=_link.ready&&_link.supportsControl&&!_link.controlBusy&&_link.kodiInstalled&&(!_link.supportsOwnership||_link.profileAssigned);
    [sheet addAction:action];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)offerInitialization {
    _needsInitializePrompt=NO;
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"Initialize Controller"
        message:@"Select your profile on the TV if asked. If another controller takes over, use ••• → Initialize Controller again. Selecting your profile switches off the other controller."
        preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Initialize Controller" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a; [self requestInitialization];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Not now" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)disconnectController {
    [self cancelEnsureSession];
    qp_initialization_cancel(&_initialization); _needsInitializePrompt=NO; _autoInitializeAttempted=YES; _wantsConnection=NO;
    [self clearControls]; [_link disconnectController];
}
- (void)showKeyboard {
    [self clearControls];
    QPKeyboardController *keyboard=[QPKeyboardController new];keyboard.link=_link;
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:keyboard];
    navigation.modalPresentationStyle=UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)confirmPowerOff {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Power Off PS5?" message:@"This closes running apps and fully shuts down the console. You will need to turn it on and run the jailbreak again before reconnecting." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Power Off" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        (void)a;if(!self.link.ready||!self.link.supportsPowerOff||self.link.controlBusy||self.link.keyboardActive)return;
        [self cancelEnsureSession];qp_initialization_cancel(&self->_initialization);
        self.wantsConnection=NO;self.needsInitializePrompt=NO;self.autoInitializeAttempted=YES;
        [self clearControls];self.result.text=@"Requesting power off…";[self.link powerOff];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showConnection {
    [self clearControls];
    NSString *detail=[NSString stringWithFormat:@"%@\n%@\n\nInitialize connects to the service, starts it if needed, and turns on the controller. Selecting your profile switches off the other controller.",_host?:@"No console added",_link.ready?[NSString stringWithFormat:@"Helper %@ connected. %@",_link.serviceVersion?:@"",_link.message?:@""]:_link.message?:@""];
    if(_link.ready&&!_link.supportsPowerOff)
        detail=[detail stringByAppendingString:@"\n\nFull Power Off requires helper 2.8 or newer. Controller functions remain available. The running helper is never replaced automatically."];
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:_link.ready?@"PS5 connection":@"Connect to PS5" message:detail preferredStyle:UIAlertControllerStyleAlert];
    BOOL controllerConnected=_link.ready&&_link.padReady;
    if(controllerConnected) {
        UIAlertAction *disconnect=[UIAlertAction actionWithTitle:@"Disconnect Controller" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            (void)a; [self disconnectController];
        }];
        disconnect.enabled=_link.supportsDisconnectController&&!_link.disconnectingController;
        [sheet addAction:disconnect];
    } else {
        UIAlertAction *initialize=[UIAlertAction actionWithTitle:@"Initialize Controller" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            (void)a; [self requestInitialization];
        }];
        initialize.enabled=!qp_initialization_pending(&_initialization)&&!_link.disconnectingController&&!_link.controlBusy&&!_ensureSession.active&&!_link.connecting;
        [sheet addAction:initialize];
    }
    UIAlertAction *keyboard=[UIAlertAction actionWithTitle:@"Keyboard…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a; [self dismissViewControllerAnimated:YES completion:^{ [self showKeyboard]; }];
    }];
    keyboard.enabled=_link.ready&&_link.supportsLiveKeyboard&&_link.profileAssigned&&!_link.controlBusy;
    [sheet addAction:keyboard];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Find / Add PS5" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a; [self dismissViewControllerAnimated:YES completion:^{ [self findConsole]; }];
    }]];
    UIAlertAction *power=[UIAlertAction actionWithTitle:@"Power Off PS5" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        (void)a;[self dismissViewControllerAnimated:YES completion:^{[self confirmPowerOff];}];
    }];
    power.enabled=_link.ready&&_link.supportsPowerOff&&!_link.controlBusy&&!_link.keyboardActive&&!_link.disconnectingController;
    [sheet addAction:power];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)findConsole {
    if(self.presentedViewController) return;
    [self cancelEnsureSession]; qp_initialization_cancel(&_initialization); _autoInitializeAttempted=NO;
    [self clearControls]; [_link disconnect:@"Choose a console"]; _wantsConnection=NO;
    QPDiscoveryController *finder=[QPDiscoveryController new]; __weak QPViewController *weakSelf=self;
    finder.added=^(NSString *host){
        QPViewController *self=weakSelf; if(!self) return;
        self.host=host; [NSUserDefaults.standardUserDefaults setObject:host forKey:@"consoleHost"];
        self.needsInitializePrompt=YES; self.wantsConnection=YES; self.result.text=@"Console added. Connecting…"; [self startEnsureSession];
    };
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:finder];
    navigation.modalPresentationStyle=UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)scheduleActivation {
    uint64_t generation=qp_lifecycle_queue_start(&_lifecycle);
    if(!generation) return;
    dispatch_async(dispatch_get_main_queue(),^{
        if(!qp_lifecycle_take_start(&self->_lifecycle,generation)) return;
        self.lifecycleBlockedReason=@"";
        [self resumeAfterInterruption];
        [self refresh];
    });
}
- (void)activateScene {
    qp_lifecycle_activate(&_lifecycle);
    [self scheduleActivation];
    if(_lifecycle.viewReady) [self refresh];
}
- (void)resume {
    if(!_lifecycle.active || !_lifecycle.viewReady) return;
    [self scheduleActivation];
    if(!_host.length && !_didOfferSetup && !self.presentedViewController) { _didOfferSetup=YES; [self findConsole]; return; }
    if(_host.length&&_wantsConnection&&!self.presentedViewController&&!qp_initialization_pending(&_initialization) && _ensureSession.active)
        [self scheduleEnsureSession];
    [self offerInitializationIfReady];
}
- (void)resumeAfterInterruption {
    if(!_lifecycle.active || !_lifecycle.viewReady) return;
    if(!_host.length) { [self resume]; return; }
    /* Dismiss stale connection alerts, then reconnect to the existing pad.
     * Keep the discovery navigation controller and its editable address intact. */
    if([self.presentedViewController isKindOfClass:UIAlertController.class]) {
        uint64_t generation=_lifecycle.generation;
        [self dismissViewControllerAnimated:NO completion:^{
            if(qp_lifecycle_is_current(&self->_lifecycle,generation)) [self startEnsureSession];
        }];
    } else [self startEnsureSession];
}
- (void)suspend {
    qp_lifecycle_suspend(&_lifecycle); _lifecycleBlockedReason=@"Scene inactive";
    [self cancelEnsureSession]; qp_initialization_cancel(&_initialization); [self clearControls];
    [_link disconnect:@"Paused in the background"]; UIApplication.sharedApplication.idleTimerDisabled=NO;
}

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
- (void)sceneDidBecomeActive:(UIScene *)scene { (void)scene; [_controller activateScene]; }
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
