#import "QPConnection.h"
#import <Network/Network.h>
#import <UIKit/UIKit.h>
#import "QPInputQueue.h"
#include <errno.h>

@interface QPConnection () {
    nw_connection_t _connection;
    nw_connection_t _loader;
    NSMutableData *_received;
    NSTimer *_timer;
    QPState _state;
    QPInputQueue _inputs;
    uint32_t _sequence, _inflight, _lastAck, _pingToken, _failures;
    uint32_t _lastInputMask, _lastAckedButtons, _sentButtons;
    NSUInteger _inputEvents;
    NSTimeInterval _sentAt, _lastPing, _lastPong, _started;
    NSUInteger _generation;
    BOOL _dirty;
    uint8_t _controlType;
    BOOL _controlSent;
    BOOL _initializationFailed;
    NSTimeInterval _controlStarted;
    NSString *_host;
    NSString *_lastAction;
    int32_t _lastActionStatus;
}
@property(nonatomic,readwrite) BOOL ready;
@property(nonatomic,readwrite) BOOL padReady;
@property(nonatomic,readwrite) BOOL connecting;
@property(nonatomic,readwrite,copy) NSString *message;
@property(nonatomic,readwrite) NSInteger latency;
@property(nonatomic,readwrite) int32_t padHandle;
@property(nonatomic,readwrite) BOOL supportsControl;
@property(nonatomic,readwrite) BOOL controlBusy;
@property(nonatomic,readwrite) BOOL vlcInstalled;
@property(nonatomic,readwrite) BOOL kodiInstalled;
@property(nonatomic,readwrite) NSInteger otherController;
@property(nonatomic,readwrite) NSInteger userStatus;
@property(nonatomic,readwrite) NSUInteger initializationCount;
@end

@implementation QPConnection
- (instancetype)init {
    if ((self=[super init])) { _state=qp_neutral(); qp_input_reset(&_inputs); _message=@"Ready when you are"; _latency=-1; _padHandle=-1; _otherController=-1; _userStatus=-1; }
    return self;
}
- (NSTimeInterval)now { return NSProcessInfo.processInfo.systemUptime; }
- (void)publish {
    NSDictionary *record=@{@"app":@"PS5 Pad", @"version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"0.1.2", @"host":_host?:@"",
        @"port":@9305, @"ready":@(_ready), @"connecting":@(_connecting), @"message":_message?:@"",
        @"pad_ready":@(_padReady),
        @"pad_handle":@(_padHandle), @"latency_ms":@(_latency), @"last_ack":@(_lastAck),
        @"server_report_failures":@(_failures), @"transport":@"direct TCP",
        @"input_events":@(_inputEvents), @"last_input_mask":@(_lastInputMask),
        @"current_buttons":@(_state.buttons), @"last_acked_buttons":@(_lastAckedButtons),
        @"queued_input_events":@(_inputs.count),
        @"supports_control":@(_supportsControl), @"control_busy":@(_controlBusy),
        @"other_controller_snapshot":@(_otherController), @"user_status":@(_userStatus),
        @"initialization_count":@(_initializationCount), @"vlc_installed":@(_vlcInstalled),
        @"kodi_installed":@(_kodiInstalled), @"last_action":_lastAction?:@"", @"last_action_status":@(_lastActionStatus),
        @"updated_unix":@(NSDate.date.timeIntervalSince1970)};
    NSString *file=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject
                    stringByAppendingPathComponent:@"PS5Pad-status.json"];
    [[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:nil]
        writeToFile:file atomically:YES];
    if (_changed) _changed();
}
- (void)disconnect:(NSString *)reason {
    nw_connection_t old=_connection;
    BOOL sendNeutral=_ready&&_padReady;
    _connection=nil; _generation++; [_timer invalidate]; _timer=nil;
    _ready=NO; _padReady=NO; _connecting=NO; _inflight=0; _state=qp_neutral(); _dirty=NO;
    _controlBusy=NO; _controlType=0; _controlSent=NO; _supportsControl=NO; _initializationFailed=NO; qp_input_reset(&_inputs);
    if(_loader) { nw_connection_cancel(_loader); _loader=nil; }
    _message=reason; _latency=-1;
    if (old) {
        if (sendNeutral) {
            uint8_t frame[36]; qp_state_frame(frame,++_sequence,qp_neutral());
            dispatch_data_t data=dispatch_data_create(frame,sizeof frame,dispatch_get_main_queue(),DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            nw_connection_send(old,data,NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,true,^(nw_error_t error){
                (void)error; nw_connection_cancel(old);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{nw_connection_cancel(old);});
        } else nw_connection_cancel(old);
    }
    [self publish];
}
- (void)connectTo:(NSString *)host {
    [self disconnect:@"Connecting to your PS5…"];
    _host=[host copy]; _connecting=YES; _received=[NSMutableData data]; _state=qp_neutral();
    _lastAction=nil; _lastActionStatus=0;
    _sequence=0; _lastAck=0; _failures=0; _padHandle=-1; _started=[self now]; _lastPong=_started;
    nw_endpoint_t endpoint=nw_endpoint_create_host(host.UTF8String,"9305");
    nw_parameters_t params=nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
        ^(nw_protocol_options_t options){ nw_tcp_options_set_no_delay(options,true); });
    _connection=nw_connection_create(endpoint,params);
    NSUInteger generation=_generation;
    __weak QPConnection *weakSelf=self;
    nw_connection_set_queue(_connection,dispatch_get_main_queue());
    nw_connection_set_state_changed_handler(_connection,^(nw_connection_state_t state,nw_error_t error){
        QPConnection *self=weakSelf; if(!self || generation!=self->_generation) return;
        if(state==nw_connection_state_ready) {
            self.message=@"Checking controller…"; self->_started=[self now]; [self receive:generation];
        } else if(state==nw_connection_state_waiting) {
            self.message=@"Allow Local Network access; check Wi-Fi";
        } else if(state==nw_connection_state_failed) {
            [self disconnect:[NSString stringWithFormat:@"Couldn’t connect (%d). Check PS5 service.",error?nw_error_get_error_code(error):0]];
            return;
        }
        [self publish];
    });
    _timer=[NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer){
        (void)timer; QPConnection *self=weakSelf; if(!self) return;
        NSTimeInterval now=[self now];
        if(self.ready) {
            if(self.controlBusy && now-self->_controlStarted>8) {
                [self disconnect:@"PS5 did not finish the request. Check the TV before retrying."]; return;
            }
            if (!self.controlBusy && ((self->_inflight && now-self->_sentAt>0.7) || now-self->_lastPong>3.5)) {
                [self disconnect:@"Connection stalled. All controls released."]; return;
            }
            self->_dirty=YES; [self flush];
            if(now-self->_lastPing>=1) [self ping];
        } else if(now-self->_started>30) [self disconnect:@"Connection timed out. Tap Connect to retry."];
    }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    nw_connection_start(_connection); [self publish];
}
- (void)sendData:(NSData *)bytes {
    if(!_connection) return;
    NSUInteger generation=_generation;
    dispatch_data_t data=dispatch_data_create(bytes.bytes,bytes.length,dispatch_get_main_queue(),DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    __weak QPConnection *weakSelf=self;
    nw_connection_send(_connection,data,NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,true,^(nw_error_t error){
        QPConnection *self=weakSelf;
        if(error && self && generation==self->_generation) [self disconnect:@"Connection lost. All controls released."];
    });
}
- (void)setState:(QPState)state {
    if(!_ready || !_padReady || _controlBusy) return;
    if(!qp_input_push(&_inputs,state,[self now])) {
        [self disconnect:@"Too many pending inputs. Controls released; reconnect to retry."]; return;
    }
    if(state.buttons && state.buttons!=_state.buttons) { _lastInputMask=state.buttons; _inputEvents++; }
    _state=state; _dirty=YES; [self flush];
}
- (void)releaseControls {
    _state=qp_neutral(); qp_input_reset(&_inputs); _dirty=YES; [self flush];
}
- (void)sendState:(QPState)state {
    uint8_t bytes[36]; _inflight=++_sequence; _sentAt=[self now]; _dirty=NO; _sentButtons=state.buttons;
    qp_state_frame(bytes,_sequence,state); [self sendData:[NSData dataWithBytes:bytes length:sizeof bytes]];
}
- (void)sendControlRequest {
    if(_controlSent || !_controlType) return;
    _controlSent=YES;
    uint8_t frame[8]; qp_header(frame,_controlType,0);
    [self sendData:[NSData dataWithBytes:frame length:8]];
}
- (void)flush {
    if(!_ready || _inflight) return;
    if(_controlBusy) {
        if(!_controlSent) {
            if(_padReady && _sentButtons) [self sendState:qp_neutral()];
            else [self sendControlRequest];
        }
        return;
    }
    if(!_padReady || (!_dirty && !_inputs.count)) return;
    QPState next;
    int result=qp_input_next(&_inputs,[self now],&next);
    if(result<0) { [self disconnect:@"Input delayed too long. Controls released; reconnect to retry."]; return; }
    if(result>0) [self sendState:next];
    else if(_inputs.count==0) [self sendState:_inputs.sent];
}
- (void)ping {
    _lastPing=[self now]; _pingToken++;
    uint8_t frame[12]; qp_header(frame,QP_PING,4); qp_put32(frame+8,_pingToken);
    [self sendData:[NSData dataWithBytes:frame length:12]];
}
- (void)receive:(NSUInteger)generation {
    if(!_connection || generation!=_generation) return;
    __weak QPConnection *weakSelf=self;
    nw_connection_receive(_connection,1,4096,^(dispatch_data_t content,nw_content_context_t context,bool complete,nw_error_t error){
        (void)context; QPConnection *self=weakSelf;
        if(!self || generation!=self->_generation) return;
        if(content) dispatch_data_apply(content,^bool(dispatch_data_t region,size_t offset,const void *buffer,size_t size){
            (void)region; (void)offset; [self->_received appendBytes:buffer length:size]; return true;
        });
        [self parse];
        if(generation!=self->_generation) return;
        if(error || complete) { [self disconnect:@"PS5 disconnected. Tap Connect to retry."]; return; }
        [self receive:generation];
    });
}
- (void)parse {
    while(_received.length>=8) {
        const uint8_t *header=_received.bytes;
        if(!qp_valid_header(header)) { [self disconnect:@"This isn’t the controller service."]; return; }
        NSUInteger length=qp_u16(header+6); uint8_t kind=header[5];
        if(_received.length<8+length) return;
        NSData *body=[_received subdataWithRange:NSMakeRange(8,length)];
        [_received replaceBytesInRange:NSMakeRange(0,8+length) withBytes:NULL length:0];
        const uint8_t *p=body.bytes;
        if(kind==QP_HELLO && length==20 && !_ready) {
            if(qp_u16(p)!=1 || (!(qp_u32(p+12)&0x10000) && (!(qp_u32(p+12)&1) || (int32_t)qp_u32(p+4)<0 || qp_u32(p+16)))) {
                [self disconnect:@"PS5 service is running, but its controller isn’t ready."]; return;
            }
            _padHandle=(int32_t)qp_u32(p+4); _ready=YES; _connecting=NO;
            _supportsControl=(qp_u32(p+12)&0x10000)!=0;
            _padReady=(qp_u32(p+12)&1)!=0 && _padHandle>=0;
            _message=@"PS5 Pad service connected."; _lastPong=[self now]; _dirty=YES;
            [self flush]; [self ping]; [self checkController]; [self publish];
        } else if(kind==QP_ACK && length==8 && _ready) {
            uint32_t seq=qp_u32(p); int32_t status=(int32_t)qp_u32(p+4);
            if(status || !_inflight || seq!=_inflight) { [self disconnect:@"PS5 rejected a controller report."]; return; }
            _lastAck=seq; _lastAckedButtons=_sentButtons; _inflight=0; [self flush];
        } else if(kind==QP_PING && length==40 && _ready) {
            if(qp_u32(p)!=_pingToken) continue;
            _lastPong=[self now]; _latency=(NSInteger)((_lastPong-_lastPing)*1000);
            _failures=qp_u32(p+32);
            _padHandle=(int32_t)qp_u32(p+16);
            _padReady=(qp_u32(p+20)&1)!=0 && _padHandle>=0 && !_initializationFailed;
            [self publish];
        } else if(kind==QP_ERROR && length>=4) {
            NSString *detail=[[NSString alloc] initWithBytes:p+4 length:length-4 encoding:NSUTF8StringEncoding];
            [self disconnect:qp_u32(p)==5?@"Controller is busy in another app.":(detail?:@"PS5 returned an error.")]; return;
        } else if((kind==QP_STATUS || kind==QP_INITIALIZE) && length==32 && _ready) {
            if(!_controlSent || _controlType!=kind) { [self disconnect:@"Unexpected controller response."]; return; }
            _userStatus=(int32_t)qp_u32(p+4); _otherController=(int32_t)qp_u32(p+8);
            _padHandle=(int32_t)qp_u32(p+16); _vlcInstalled=(qp_u32(p+24)&1)!=0; _kodiInstalled=(qp_u32(p+24)&2)!=0;
            BOOL reportedReady=(qp_u32(p+20)&1)!=0 && _padHandle>=0;
            _padReady=reportedReady&&!_initializationFailed;
            _initializationCount=qp_u32(p+28); _controlBusy=NO; _controlType=0; _controlSent=NO;
            _lastPong=[self now]; _sentAt=_lastPong;
            if(kind==QP_INITIALIZE) {
                int32_t status=(int32_t)qp_u32(p);
                BOOL incomplete=!status&&!reportedReady;
                if(incomplete) status=EPROTO;
                _initializationFailed=status!=0; _padReady=reportedReady&&!_initializationFailed;
                _state=qp_neutral(); qp_input_reset(&_inputs); _dirty=_padReady;
                if(incomplete) _message=@"Initialization failed: the service did not report a ready virtual controller.";
                else if(status) _message=[NSString stringWithFormat:@"Initialization failed (0x%08X). Use ••• → Initialize Controller to retry.",(unsigned)status];
                else _message=@"Virtual controller ready. Select your profile on the TV if asked.";
                _lastAction=@"initialize"; _lastActionStatus=status;
                if(_completed) _completed(@"initialize",status);
            } else {
                int32_t status=(int32_t)qp_u32(p);
                if(status) { _padReady=NO; _message=[NSString stringWithFormat:@"Controller check failed (0x%08X).",(unsigned)status]; }
                else if(_initializationFailed) _message=@"Initialization has not succeeded. Use ••• → Initialize Controller to retry.";
                else _message=_padReady?@"Service connected; virtual controller available. Profile control is not verified.":@"Service connected. Use ••• → Initialize Controller.";
            }
            [self flush]; [self publish];
        } else if((kind==QP_VLC || kind==QP_KODI) && length==4 && _ready) {
            if(!_controlSent || _controlType!=kind) { [self disconnect:@"Unexpected media response."]; return; }
            _controlBusy=NO; _controlType=0; _controlSent=NO; _lastPong=[self now]; _sentAt=_lastPong;
            _lastAction=kind==QP_VLC?@"VLC":@"Kodi"; _lastActionStatus=(int32_t)qp_u32(p);
            _message=_lastActionStatus?[NSString stringWithFormat:@"%@ launch failed (0x%08X)",_lastAction,(unsigned)_lastActionStatus]:[NSString stringWithFormat:@"%@ launch requested",_lastAction];
            if(_completed) _completed(_lastAction,_lastActionStatus);
            [self flush]; [self publish];
        } else { [self disconnect:@"Unexpected reply from the PS5 service."]; return; }
    }
}
- (void)control:(uint8_t)kind {
    if(!_ready || !_supportsControl || _controlBusy) return;
    _state=qp_neutral(); qp_input_reset(&_inputs); _dirty=YES;
    _controlBusy=YES; _controlType=kind; _controlSent=NO; _controlStarted=[self now];
    _message=kind==QP_INITIALIZE?@"Initializing…":(kind==QP_STATUS?@"Checking controller…":(kind==QP_KODI?@"Opening Kodi…":@"Opening VLC…"));
    [self flush]; [self publish];
}
- (void)checkController { [self control:QP_STATUS]; }
- (void)initializeController { [self control:QP_INITIALIZE]; }
- (void)launchVLC { [self control:QP_VLC]; }
- (void)launchKodi { [self control:QP_KODI]; }
- (void)loadServiceAt:(NSString *)host {
    [self disconnect:@"Loading controller service…"]; _host=[host copy];
    NSData *elf=[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"padd-controller" ofType:@"elf"]];
    if(!elf.length) { [self disconnect:@"The controller service is missing from this build."]; return; }
    _connecting=YES;
    NSUInteger generation=_generation;
    _loader=nw_connection_create(nw_endpoint_create_host(host.UTF8String,"9021"),
        nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION));
    nw_connection_t loader=_loader; __weak QPConnection *weakSelf=self;
    nw_connection_set_queue(loader,dispatch_get_main_queue());
    nw_connection_set_state_changed_handler(loader,^(nw_connection_state_t state,nw_error_t error){
        (void)error; QPConnection *self=weakSelf; if(!self || self->_generation!=generation) return;
        if(state==nw_connection_state_failed) { [self disconnect:@"ELF loader unavailable. Run the jailbreak on the PS5 first."]; return; }
        if(state==nw_connection_state_ready) {
            dispatch_data_t data=dispatch_data_create(elf.bytes,elf.length,dispatch_get_main_queue(),DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            nw_connection_send(loader,data,NW_CONNECTION_FINAL_MESSAGE_CONTEXT,true,^(nw_error_t sendError){
                if(self->_generation!=generation) return;
                if(sendError) { [self disconnect:@"Couldn’t send the controller service."]; return; }
                self.message=@"Service sent. Waiting for PS5…"; [self publish];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                    if(self->_generation==generation) [self connectTo:host];
                });
            });
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self->_generation==generation) [self disconnect:@"ELF loader did not respond. Check the PS5 jailbreak."];
    });
    nw_connection_start(loader); [self publish];
}
@end
