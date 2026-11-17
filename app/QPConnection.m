#import "QPConnection.h"
#import <Network/Network.h>
#import <UIKit/UIKit.h>
#import "QPInputQueue.h"
#import "QPInputFeedback.h"
#include <errno.h>

@interface QPConnection () {
    nw_connection_t _connection;
    nw_connection_t _loader;
    NSMutableData *_received;
    NSTimer *_timer;
    QPState _state;
    QPInputQueue _inputs;
    QPInputFeedbackGate _feedbackGate;
    uint64_t _sentFeedbackEpoch;
    uint32_t _sequence, _inflight, _lastAck, _pingToken, _failures;
    uint32_t _lastInputMask, _lastAckedButtons, _sentButtons;
    NSUInteger _inputEvents;
    NSTimeInterval _sentAt, _lastPing, _lastPong, _started;
    NSUInteger _generation;
    BOOL _dirty, _tcpReady, _connectBlocked;
    NSTimeInterval _connectTimeout;
    uint8_t _controlType;
    NSData *_controlPayload;
    NSString *_keyboardDesired,*_keyboardSent,*_keyboardInFlight;
    BOOL _keyboardExit,_keyboardEnter;
    uint8_t _keyboardOp;
    NSTimeInterval _keyboardLastLease;
    BOOL _controlSent;
    BOOL _initializationFailed, _disconnectRequested;
    NSTimeInterval _controlStarted;
    NSString *_host;
    NSString *_lastAction;
    int32_t _lastActionStatus;
}
@property(nonatomic,readwrite) BOOL supportsLiveKeyboard,keyboardConnected,keyboardActive,keyboardClosing;
@property(nonatomic,readwrite,copy) NSString *keyboardMessage;
@property(nonatomic,readwrite) BOOL ready;
@property(nonatomic,readwrite) QPConnectionFailure failureKind;
@property(nonatomic,readwrite) BOOL controllerChecked;
@property(nonatomic,readwrite) BOOL padReady;
@property(nonatomic,readwrite) BOOL supportsOwnership,profileAssigned,waitingForProfile,monitorReady,supportsTextInput;
@property(nonatomic,readwrite) BOOL connecting;
@property(nonatomic,readwrite,copy) NSString *message;
@property(nonatomic,readwrite) NSInteger latency;
@property(nonatomic,readwrite) int32_t padHandle;
@property(nonatomic,readwrite) BOOL supportsControl;
@property(nonatomic,readwrite) BOOL supportsDisconnectController;
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
        @"pad_ready":@(_padReady), @"profile_assigned":@(_profileAssigned), @"waiting_for_profile":@(_waitingForProfile), @"ownership_monitor_ready":@(_monitorReady), @"connection_failure":@(_failureKind), @"controller_checked":@(_controllerChecked),
        @"pad_handle":@(_padHandle), @"latency_ms":@(_latency), @"last_ack":@(_lastAck),
        @"server_report_failures":@(_failures), @"transport":@"direct TCP",
        @"input_events":@(_inputEvents), @"last_input_mask":@(_lastInputMask),
        @"current_buttons":@(_state.buttons), @"last_acked_buttons":@(_lastAckedButtons),
        @"queued_input_events":@(_inputs.count),
        @"supports_control":@(_supportsControl), @"control_busy":@(_controlBusy),
        @"supports_disconnect_controller":@(_supportsDisconnectController), @"disconnecting_controller":@(self.disconnectingController),
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
- (void)readOwnershipFlags:(uint32_t)flags {
    _supportsTextInput=(flags&QP_CAP_TEXT_INPUT)!=0;
    _supportsLiveKeyboard=(flags&QP_CAP_LIVE_KEYBOARD)!=0;
    _supportsOwnership=(flags&QP_CAP_OWNERSHIP)!=0;
    _profileAssigned=_supportsOwnership&&(flags&QP_PROFILE_ASSIGNED)!=0;
    _waitingForProfile=_supportsOwnership&&(flags&QP_PROFILE_PENDING)!=0;
    _monitorReady=_supportsOwnership&&(flags&QP_MONITOR_READY)!=0;
}
- (NSString *)controllerMessage {
    if(_waitingForProfile) return @"Choose your profile on the TV. Use the swipe pad to select it.";
    if(_profileAssigned&&_padReady) return @"Controller connected to your profile.";
    if(_supportsOwnership&&!_monitorReady) return @"Waiting for the PS5 controller monitor.";
    return _padReady?@"Virtual controller connected; profile assignment unverified.":@"Service connected. Use ••• → Turn On Controller.";
}
- (void)invalidateInputFeedback {
    qp_feedback_gate_reset(&_feedbackGate); _lastAckedButtons=0;
    if(_inputFeedbackReset) _inputFeedbackReset();
}
- (void)disconnect:(NSString *)reason {
    nw_connection_t old=_connection;
    BOOL sendNeutral=_ready&&_padReady;
    _connection=nil; _generation++; [_timer invalidate]; _timer=nil;
    _controlPayload=nil; _supportsTextInput=NO;
    _supportsLiveKeyboard=_keyboardConnected=_keyboardActive=_keyboardClosing=NO;
    _keyboardDesired=_keyboardSent=_keyboardInFlight=nil; _keyboardExit=_keyboardEnter=NO;
    _keyboardMessage=@"Keyboard disconnected";
    _supportsOwnership=_profileAssigned=_waitingForProfile=_monitorReady=NO;
    _ready=NO; _padReady=NO; _connecting=NO; _failureKind=QPConnectionFailureNone; _controllerChecked=NO; _inflight=0; _state=qp_neutral(); _dirty=NO;
    _controlBusy=NO; _controlType=0; _controlSent=NO; _supportsControl=NO; _supportsDisconnectController=NO; _disconnectRequested=NO; _initializationFailed=NO; qp_input_reset(&_inputs);
    if(_loader) { nw_connection_cancel(_loader); _loader=nil; }
    _message=reason; _latency=-1; [self invalidateInputFeedback];
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
- (BOOL)serviceUnavailableForError:(nw_error_t)error deadline:(BOOL)deadline {
    if(_tcpReady || !_connection) return NO;
    nw_path_t path=nw_connection_copy_current_path(_connection);
    if(path) {
        nw_path_unsatisfied_reason_t reason=nw_path_get_unsatisfied_reason(path);
        if(reason==nw_path_unsatisfied_reason_local_network_denied || reason==nw_path_unsatisfied_reason_wifi_denied ||
           reason==nw_path_unsatisfied_reason_cellular_denied) return NO;
    }
    if(error) return nw_error_get_error_domain(error)==nw_error_domain_posix && nw_error_get_error_code(error)==ECONNREFUSED;
    return deadline && !_connectBlocked && path && nw_path_get_status(path)==nw_path_status_satisfied;
}
- (void)failConnection:(NSString *)reason unavailable:(BOOL)unavailable {
    [self disconnect:reason];
    _failureKind=unavailable?QPConnectionFailureUnavailable:QPConnectionFailureOther;
    [self publish];
}
- (void)limitConnectWait:(NSTimeInterval)timeout {
    if(_connecting && !_loader) { _connectTimeout=MIN(_connectTimeout,timeout); _started=[self now]; }
}
- (void)connectTo:(NSString *)host { [self connectTo:host timeout:30]; }
- (void)connectTo:(NSString *)host timeout:(NSTimeInterval)timeout {
    [self disconnect:@"Connecting to your PS5…"];
    _host=[host copy]; _connecting=YES; _tcpReady=NO; _connectBlocked=NO; _connectTimeout=timeout; _received=[NSMutableData data]; _state=qp_neutral();
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
            self->_tcpReady=YES; self.message=@"Checking controller…"; self->_started=[self now]; [self receive:generation];
        } else if(state==nw_connection_state_waiting) {
            self.message=@"Allow Local Network access; check Wi-Fi";
            if(error && !(nw_error_get_error_domain(error)==nw_error_domain_posix &&
                (nw_error_get_error_code(error)==ECONNREFUSED || nw_error_get_error_code(error)==ETIMEDOUT))) self->_connectBlocked=YES;
        } else if(state==nw_connection_state_failed) {
            [self failConnection:[NSString stringWithFormat:@"Couldn’t connect (%d). Check PS5 service.",error?nw_error_get_error_code(error):0] unavailable:[self serviceUnavailableForError:error deadline:NO]];
            return;
        }
        [self publish];
    });
    _timer=[NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer){
        (void)timer; QPConnection *self=weakSelf; if(!self) return;
        NSTimeInterval now=[self now];
        if(self.ready) {
            if(self.controlBusy && now-self->_controlStarted>((self->_controlType==QP_TYPE_TEXT||self->_controlType==QP_LIVE_KEYBOARD)?30:8)) {
                [self failConnection:@"PS5 did not finish the request. Check the TV before retrying." unavailable:NO]; return;
            }
            if (!self.controlBusy && ((self->_inflight && now-self->_sentAt>0.7) || now-self->_lastPong>3.5)) {
                [self failConnection:@"Connection stalled. All controls released." unavailable:NO]; return;
            }
            self->_dirty=YES; [self flush];
            if(now-self->_lastPing>=1) [self ping];
            if(self.keyboardActive && now-self->_keyboardLastLease>=0.5) {
                uint8_t lease[8];qp_header(lease,QP_KEYBOARD_LEASE,0);
                [self sendData:[NSData dataWithBytes:lease length:sizeof lease]];self->_keyboardLastLease=now;
            }
            [self pumpKeyboard];
        } else if(now-self->_started>self->_connectTimeout) {
            BOOL unavailable=[self serviceUnavailableForError:nil deadline:YES];
            [self failConnection:@"Connection timed out. Use ••• to retry." unavailable:unavailable];
        }
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
        if(error && self && generation==self->_generation) [self failConnection:@"Connection lost. All controls released." unavailable:NO];
    });
}
- (void)setState:(QPState)state {
    if(!_ready || !_padReady || _controlBusy) return;
    if(!qp_input_push(&_inputs,state,[self now])) {
        [self failConnection:@"Too many pending inputs. Controls released; reconnect to retry." unavailable:NO]; return;
    }
    if(state.buttons && state.buttons!=_state.buttons) { _lastInputMask=state.buttons; _inputEvents++; }
    _state=state; _dirty=YES; [self flush];
}
- (void)releaseControls {
    [self invalidateInputFeedback];
    _state=qp_neutral(); qp_input_release(&_inputs,[self now]); _dirty=YES; [self flush];
}
- (void)sendState:(QPState)state {
    uint8_t bytes[36]; _inflight=++_sequence; _sentAt=[self now]; _dirty=NO; _sentButtons=state.buttons;
    _sentFeedbackEpoch=_feedbackGate.epoch;
    qp_state_frame(bytes,_sequence,state); [self sendData:[NSData dataWithBytes:bytes length:sizeof bytes]];
}
- (void)sendControlRequest {
    if(_controlSent || !_controlType) return;
    _controlSent=YES;
    uint8_t frame[8]; qp_header(frame,_controlType,(uint16_t)_controlPayload.length);
    NSMutableData *message=[NSMutableData dataWithBytes:frame length:8];
    if(_controlPayload) [message appendData:_controlPayload];
    _controlPayload=nil; [self sendData:message];
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
    if(result<0) { [self failConnection:@"Input delayed too long. Controls released; reconnect to retry." unavailable:NO]; return; }
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
        if(error || complete) { [self failConnection:@"PS5 disconnected. Tap Connect to retry." unavailable:NO]; return; }
        [self receive:generation];
    });
}
- (void)parse {
    while(_received.length>=8) {
        const uint8_t *header=_received.bytes;
        if(!qp_valid_header(header)) { [self failConnection:@"This isn’t the controller service." unavailable:NO]; return; }
        NSUInteger length=qp_u16(header+6); uint8_t kind=header[5];
        if(_received.length<8+length) return;
        NSData *body=[_received subdataWithRange:NSMakeRange(8,length)];
        [_received replaceBytesInRange:NSMakeRange(0,8+length) withBytes:NULL length:0];
        const uint8_t *p=body.bytes;
        if(kind==QP_HELLO && length==20 && !_ready) {
            if(qp_u16(p)!=1 || (!(qp_u32(p+12)&0x10000) && (!(qp_u32(p+12)&1) || (int32_t)qp_u32(p+4)<0 || qp_u32(p+16)))) {
                [self failConnection:@"PS5 service is running, but its controller isn’t ready." unavailable:NO]; return;
            }
            [self readOwnershipFlags:qp_u32(p+12)];
            _padHandle=(int32_t)qp_u32(p+4); _ready=YES; _connecting=NO;
            _supportsControl=(qp_u32(p+12)&QP_CAP_CONTROL)!=0;
            _supportsDisconnectController=qp_supports_disconnect(qp_u16(p+2),qp_u32(p+12));
            _padReady=(qp_u32(p+12)&1)!=0 && _padHandle>=0;
            _message=@"PS5 Pad service connected."; _lastPong=[self now]; _dirty=YES;
            [self flush]; [self ping]; [self checkController]; [self publish];
        } else if(kind==QP_ACK && length==8 && _ready) {
            uint32_t seq=qp_u32(p); int32_t status=(int32_t)qp_u32(p+4);
            BOOL current=qp_feedback_ack_is_current(&_feedbackGate,_sentFeedbackEpoch,_inflight,seq,status);
            if(status || !_inflight || seq!=_inflight) { [self failConnection:@"PS5 rejected a controller report." unavailable:NO]; return; }
            _lastAck=seq; _inflight=0;
            if(current) {
                _lastAckedButtons=_sentButtons;
                if(_inputAcknowledged) _inputAcknowledged(_sentButtons);
            }
            [self flush];
        } else if(kind==QP_PING && length==40 && _ready) {
            if(qp_u32(p)!=_pingToken) continue;
            _lastPong=[self now]; _latency=(NSInteger)((_lastPong-_lastPing)*1000);
            _failures=qp_u32(p+32);
            _padHandle=(int32_t)qp_u32(p+16);
            [self readOwnershipFlags:qp_u32(p+20)];
            BOOL reportedReady=(qp_u32(p+20)&1)!=0 && _padHandle>=0 && !_initializationFailed;
            if(reportedReady!=_padReady) {
                _controllerChecked=NO; /* A changed PING is not a new STATUS snapshot. */
                _message=reportedReady?@"Service connected; virtual controller available.":@"Virtual controller unavailable. Use ••• → Initialize Controller.";
            }
            BOOL lostPad=!reportedReady && _padReady;
            _padReady=reportedReady;
            if(lostPad) [self releaseControls];
            if(!_controlBusy) _message=[self controllerMessage];
            [self publish];
        } else if(kind==QP_LIVE_KEYBOARD && length==8 && _ready) {
            if(!_controlSent || _controlType!=kind) { [self failConnection:@"Unexpected keyboard response." unavailable:NO]; return; }
            int32_t status=(int32_t)qp_u32(p);_keyboardConnected=qp_u32(p+4)!=0;
            _controlBusy=NO;_controlType=0;_controlSent=NO;_lastPong=[self now];_sentAt=_lastPong;
            if(status && _keyboardExit && !_keyboardEnter && !_keyboardConnected) {
                _keyboardActive=_keyboardClosing=NO;_keyboardDesired=_keyboardSent=_keyboardInFlight=nil;
                _keyboardMessage=@"Keyboard disconnected";
            } else if(status) {
                _keyboardDesired=_keyboardSent=_keyboardInFlight=nil;
                _keyboardMessage=[NSString stringWithFormat:@"Keyboard stopped (0x%08X). Close and retry.",(unsigned)status];
                _keyboardActive=NO;_keyboardClosing=NO;
                /* Stop renewing: the service removes any surviving keyboard by lease expiry. */
            } else if(_keyboardOp>=2) {
                _keyboardActive=_keyboardClosing=NO;_keyboardDesired=_keyboardSent=_keyboardInFlight=nil;
                _keyboardMessage=@"Keyboard disconnected";
            } else {
                if(_keyboardOp==1) _keyboardSent=_keyboardInFlight;
                _keyboardInFlight=nil;_keyboardMessage=@"Connected · typing live";
                [self pumpKeyboard];
            }
            [self flush];[self publish];
        } else if(kind==QP_TYPE_TEXT && length==8 && _ready) {
            if(!_controlSent || _controlType!=kind) { [self failConnection:@"Unexpected keyboard response." unavailable:NO]; return; }
            int32_t status=(int32_t)qp_u32(p); uint32_t count=qp_u32(p+4);
            _controlBusy=NO; _controlType=0; _controlSent=NO; _lastPong=[self now]; _sentAt=_lastPong;
            _lastAction=@"keyboard"; _lastActionStatus=status;
            _message=status?[NSString stringWithFormat:@"Typing stopped after %u characters (0x%08X).",count,(unsigned)status]:[NSString stringWithFormat:@"Sent %u characters. Keyboard disconnected.",count];
            if(_completed) _completed(@"keyboard",status);
            [self tryDisconnectController]; [self flush]; [self publish];
        } else if(kind==QP_ERROR && length>=4) {
            NSString *detail=[[NSString alloc] initWithBytes:p+4 length:length-4 encoding:NSUTF8StringEncoding];
            if(qp_u32(p)==8 && _completed) _completed(@"handoff",0);
            [self failConnection:qp_u32(p)==5?@"Controller is busy in another app.":(detail?:@"PS5 returned an error.") unavailable:NO]; return;
        } else if((kind==QP_STATUS || kind==QP_INITIALIZE || kind==QP_DISCONNECT_CONTROLLER) && length==32 && _ready) {
            if(!_controlSent || _controlType!=kind) { [self failConnection:@"Unexpected controller response." unavailable:NO]; return; }
            [self readOwnershipFlags:qp_u32(p+20)];
            _userStatus=(int32_t)qp_u32(p+4); _otherController=(int32_t)qp_u32(p+8);
            _padHandle=(int32_t)qp_u32(p+16); _vlcInstalled=(qp_u32(p+24)&1)!=0; _kodiInstalled=(qp_u32(p+24)&2)!=0;
            BOOL reportedReady=(qp_u32(p+20)&1)!=0 && _padHandle>=0;
            _padReady=reportedReady&&!_initializationFailed;
            _initializationCount=qp_u32(p+28); _controlBusy=NO; _controlType=0; _controlSent=NO;
            _lastPong=[self now]; _sentAt=_lastPong;
            if(kind==QP_DISCONNECT_CONTROLLER) {
                int32_t status=(int32_t)qp_u32(p);
                if(!status && !qp_disconnect_response_valid(p)) status=EPROTO;
                _padReady=NO; _controllerChecked=NO; _state=qp_neutral(); qp_input_reset(&_inputs); _dirty=NO;
                [self invalidateInputFeedback];
                _message=status?[NSString stringWithFormat:@"Controller disconnection failed (0x%08X). Use ••• → Disconnect controller to retry.",(unsigned)status]:@"Controller disconnected.";
                _lastAction=@"disconnect_controller"; _lastActionStatus=status;
                if(_completed) _completed(@"disconnect_controller",status);
                if(!status) { [self disconnect:_message]; return; }
            } else if(kind==QP_INITIALIZE) {
                int32_t status=(int32_t)qp_u32(p);
                BOOL incomplete=!status&&!reportedReady;
                if(incomplete) status=EPROTO;
                _initializationFailed=status!=0; _padReady=reportedReady&&!_initializationFailed;
                _state=qp_neutral(); qp_input_reset(&_inputs); _dirty=_padReady;
                [self invalidateInputFeedback];
                if(incomplete) _message=@"Initialization failed: the service did not report a ready virtual controller.";
                else if(status) _message=[NSString stringWithFormat:@"Initialization failed (0x%08X). Use ••• → Initialize Controller to retry.",(unsigned)status];
                else _message=[self controllerMessage];
                _lastAction=@"initialize"; _lastActionStatus=status;
                if(_completed) _completed(@"initialize",status);
            } else {
                int32_t status=(int32_t)qp_u32(p);
                _controllerChecked=status==0;
                if(status) { _padReady=NO; _message=[NSString stringWithFormat:@"Controller check failed (0x%08X).",(unsigned)status]; }
                else if(_initializationFailed) _message=@"Initialization has not succeeded. Use ••• → Initialize Controller to retry.";
                else _message=[self controllerMessage];
                if(status && _completed) _completed(@"check",status);
            }
            [self tryDisconnectController]; [self flush]; [self publish];
        } else if((kind==QP_VLC || kind==QP_KODI) && length==4 && _ready) {
            if(!_controlSent || _controlType!=kind) { [self failConnection:@"Unexpected media response." unavailable:NO]; return; }
            _controlBusy=NO; _controlType=0; _controlSent=NO; _lastPong=[self now]; _sentAt=_lastPong;
            _lastAction=kind==QP_VLC?@"VLC":@"Kodi"; _lastActionStatus=(int32_t)qp_u32(p);
            _message=_lastActionStatus?[NSString stringWithFormat:@"%@ launch failed (0x%08X)",_lastAction,(unsigned)_lastActionStatus]:[NSString stringWithFormat:@"%@ launch requested",_lastAction];
            if(_completed) _completed(_lastAction,_lastActionStatus);
            [self tryDisconnectController]; [self flush]; [self publish];
        } else { [self failConnection:@"Unexpected reply from the PS5 service." unavailable:NO]; return; }
    }
}
- (void)control:(uint8_t)kind {
    if(!_ready || !_supportsControl || _controlBusy) return;
    [self invalidateInputFeedback];
    _state=qp_neutral(); qp_input_reset(&_inputs); _dirty=YES;
    _controlBusy=YES; _controlType=kind; _controlSent=NO; _controlStarted=[self now];
    _message=kind==QP_LIVE_KEYBOARD?@"Keyboard session active":(kind==QP_TYPE_TEXT?@"Typing…":(kind==QP_DISCONNECT_CONTROLLER?@"Disconnecting controller…":(kind==QP_INITIALIZE?@"Turning on controller…":(kind==QP_STATUS?@"Checking controller…":(kind==QP_KODI?@"Opening Kodi…":@"Opening VLC…")))));
    [self flush]; [self publish];
}
- (BOOL)disconnectingController { return _disconnectRequested || _controlType==QP_DISCONNECT_CONTROLLER; }
- (void)tryDisconnectController {
    if(!_disconnectRequested || !_ready || _controlBusy) return;
    _disconnectRequested=NO; [self control:QP_DISCONNECT_CONTROLLER];
}
- (void)disconnectController {
    if(self.disconnectingController) return;
    if(!_ready || !_supportsDisconnectController) {
        int32_t status=_ready?ENOTSUP:ENOTCONN;
        _message=_ready?@"This PS5 service needs an update before it can disconnect the controller.":@"Connect to the PS5 service before disconnecting its controller.";
        _lastAction=@"disconnect_controller"; _lastActionStatus=status;
        if(_completed) _completed(@"disconnect_controller",status);
        [self publish]; return;
    }
    [self invalidateInputFeedback];
    _disconnectRequested=YES; _state=qp_neutral(); qp_input_reset(&_inputs); _dirty=YES;
    _message=@"Disconnecting controller…"; [self tryDisconnectController]; [self publish];
}
- (void)sendKeyboardOp:(uint8_t)op payload:(NSData *)payload {
    _keyboardOp=op;_controlPayload=payload;[self control:QP_LIVE_KEYBOARD];
}
- (void)openKeyboard {
    if(!_ready||!_supportsLiveKeyboard||!_profileAssigned||_controlBusy||_keyboardActive)return;
    _keyboardActive=YES;_keyboardClosing=_keyboardExit=_keyboardEnter=NO;_keyboardConnected=NO;
    _keyboardDesired=@"";_keyboardSent=@"";_keyboardInFlight=nil;_keyboardLastLease=0;
    _keyboardMessage=@"Connecting keyboard…";uint8_t op=0;
    [self sendKeyboardOp:op payload:[NSData dataWithBytes:&op length:1]];
}
- (void)updateKeyboardText:(NSString *)text {
    if(!_keyboardActive||_keyboardClosing)return;
    NSData *bytes=[text dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];
    if(!bytes||bytes.length>128)return;
    const uint8_t *p=bytes.bytes;for(NSUInteger i=0;i<bytes.length;i++)if(p[i]<32||p[i]>126)return;
    _keyboardDesired=[text copy];[self pumpKeyboard];
}
- (void)closeKeyboardWithEnter:(BOOL)enter {
    if(!_keyboardActive)return;
    _keyboardExit=YES;_keyboardEnter=enter;_keyboardClosing=YES;
    if(!enter) {
        _keyboardDesired=_keyboardSent;
        if(_controlBusy&&_controlType==QP_LIVE_KEYBOARD) {
            uint8_t cancel[9];qp_header(cancel,QP_KEYBOARD_LEASE,1);cancel[8]=1;
            [self sendData:[NSData dataWithBytes:cancel length:sizeof cancel]];
        }
    }
    [self pumpKeyboard];[self publish];
}
- (void)pumpKeyboard {
    if(!_keyboardActive||!_keyboardConnected||_controlBusy||!_ready)return;
    if(_keyboardExit&&!_keyboardEnter) {
        uint8_t op=2;[self sendKeyboardOp:op payload:[NSData dataWithBytes:&op length:1]];return;
    }
    if(![_keyboardDesired isEqualToString:_keyboardSent]) {
        NSUInteger prefix=0,limit=MIN(_keyboardDesired.length,_keyboardSent.length);
        while(prefix<limit&&[_keyboardDesired characterAtIndex:prefix]==[_keyboardSent characterAtIndex:prefix])prefix++;
        NSUInteger backspaces=_keyboardSent.length-prefix;
        uint8_t header[3]={1,(uint8_t)backspaces,(uint8_t)(backspaces>>8)};
        NSMutableData *edit=[NSMutableData dataWithBytes:header length:3];
        [edit appendData:[[_keyboardDesired substringFromIndex:prefix] dataUsingEncoding:NSASCIIStringEncoding]];
        _keyboardInFlight=_keyboardDesired;_keyboardMessage=@"Typing live…";
        [self sendKeyboardOp:1 payload:edit];return;
    }
    if(_keyboardExit) {uint8_t op=3;[self sendKeyboardOp:op payload:[NSData dataWithBytes:&op length:1]];}
}
- (void)typeText:(NSString *)text {
    if(!_ready || !_supportsTextInput || !_profileAssigned || _controlBusy) return;
    NSData *bytes=[text dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];
    const uint8_t *p=bytes.bytes; BOOL valid=bytes.length>0&&bytes.length<=128;
    for(NSUInteger i=0;i<bytes.length;i++) if(p[i]<32||p[i]>126) valid=NO;
    if(!valid) { _message=@"Use 1–128 English letters, numbers, spaces or punctuation."; [self publish]; return; }
    _controlPayload=bytes; [self control:QP_TYPE_TEXT];
}
- (void)checkController { [self control:QP_STATUS]; }
- (void)initializeController { [self control:QP_INITIALIZE]; }
- (void)launchVLC { [self control:QP_VLC]; }
- (void)launchKodi { [self control:QP_KODI]; }
- (void)loadServiceAt:(NSString *)host {
    [self disconnect:@"Loading controller service…"]; _host=[host copy];
    NSData *elf=[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"padd-controller" ofType:@"elf"]];
    if(!elf.length) { [self failConnection:@"The controller service is missing from this build." unavailable:NO]; return; }
    _connecting=YES;
    NSUInteger generation=_generation;
    _loader=nw_connection_create(nw_endpoint_create_host(host.UTF8String,"9021"),
        nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION));
    nw_connection_t loader=_loader; __weak QPConnection *weakSelf=self;
    nw_connection_set_queue(loader,dispatch_get_main_queue());
    nw_connection_set_state_changed_handler(loader,^(nw_connection_state_t state,nw_error_t error){
        (void)error; QPConnection *self=weakSelf; if(!self || self->_generation!=generation) return;
        if(state==nw_connection_state_failed) { [self failConnection:@"ELF loader unavailable. Run the jailbreak on the PS5 first." unavailable:NO]; return; }
        if(state==nw_connection_state_ready) {
            dispatch_data_t data=dispatch_data_create(elf.bytes,elf.length,dispatch_get_main_queue(),DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            nw_connection_send(loader,data,NW_CONNECTION_FINAL_MESSAGE_CONTEXT,true,^(nw_error_t sendError){
                if(self->_generation!=generation) return;
                if(sendError) { [self failConnection:@"Couldn’t send the controller service." unavailable:NO]; return; }
                self.message=@"Service sent. Waiting for PS5…"; [self publish];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                    if(self->_generation==generation) [self connectTo:host timeout:3];
                });
            });
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self->_generation==generation) [self failConnection:@"ELF loader did not respond. Check the PS5 jailbreak." unavailable:NO];
    });
    nw_connection_start(loader); [self publish];
}
@end
