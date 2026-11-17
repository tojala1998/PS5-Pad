#import "QPHelperLoader.h"
#import "QPLoaderPolicy.h"
#import "QPHelperUpdate.h"
#import <Network/Network.h>
#include <errno.h>

@interface QPHelperLoader () <NSURLSessionTaskDelegate> {
    nw_connection_t _socket;
    NSURLSession *_session;
    NSString *_host,*_stem,*_filename;
    NSData *_image;
    NSMutableData *_hello;
    BOOL _active,_launched,_loaderConnected,_sendStarted,_usedManager;
    BOOL _probeConnected,_probeBlocked;
    NSMutableArray *_trace;
    unsigned _probes;
    QPHelperUpdate _update;
    NSUInteger _runGeneration;
    unsigned _exitProbes;
}
@end
@implementation QPHelperLoader
- (void)cancel {
    _runGeneration++;
    _active=NO;if(_socket){nw_connection_cancel(_socket);_socket=nil;}
    [_session invalidateAndCancel];_session=nil;_image=nil;
}
- (void)finish:(NSString *)error {
    if(!_active)return;void(^done)(NSString *)=_completed;
    [self record:error?:@"verified" state:0 code:0];
    [self cancel];if(done)done(error);
}
- (void)record:(NSString *)event state:(int)state code:(int)code {
    if(!_trace)_trace=[NSMutableArray new];
    [_trace addObject:@{@"event":event,@"state":@(state),@"code":@(code),@"time":@(NSDate.date.timeIntervalSince1970)}];
    if(_trace.count>48)[_trace removeObjectAtIndex:0];
    NSString *file=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"PS5Pad-startup.json"];
    NSDictionary *record=@{@"version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"",@"events":_trace};
    [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil] writeToFile:file atomically:YES];
}
- (void)say:(NSString *)message {[self record:message state:0 code:0];if(_active&&_progress)_progress(message);}
- (nw_connection_t)socketOnPort:(const char *)port {
    nw_connection_t c=nw_connection_create(nw_endpoint_create_host(_host.UTF8String,port),nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION));
    nw_connection_set_queue(c,dispatch_get_main_queue());_socket=c;return c;
}
- (void)start:(NSString *)host image:(NSData *)image {
    [self cancel];_active=YES;_host=[host copy];_image=image;
    _launched=_loaderConnected=_sendStarted=_usedManager=NO;_probes=0;_trace=[NSMutableArray new];
    _update=QP_UPDATE_NONE;_exitProbes=0;NSUInteger run=_runGeneration;
    if(!qp_loader_image_valid(image.bytes,image.length)){[self finish:@"The bundled helper is not a valid PS5 ELF."];return;}
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest=6;config.timeoutIntervalForResource=10;config.HTTPShouldSetCookies=NO;
    config.URLCache=nil;config.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    _session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    [self say:@"Checking controller service…"];[self probe];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,70*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self->_active&&self->_runGeneration==run)[self finish:@"Service startup timed out. Check the PS5 before retrying."];
    });
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    (void)session;(void)task;(void)response;(void)request;completionHandler(nil);
}
- (void)http:(NSString *)method path:(NSString *)path body:(NSData *)body done:(void (^)(NSData *,NSString *))done {
    NSUInteger run=_runGeneration;
    NSURLComponents *parts=[NSURLComponents new];parts.scheme=@"http";parts.host=_host;parts.port=@8084;
    NSURL *url=[NSURL URLWithString:path relativeToURL:parts.URL];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];request.HTTPMethod=method;request.HTTPBody=body;
    [request setValue:@"1" forHTTPHeaderField:@"X-PLDMGR-Request"];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(!self->_active||self->_runGeneration!=run)return;
            NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
            [self record:[NSString stringWithFormat:@"Payload Manager %@",method] state:(int)status code:(int)error.code];
            NSString *failure=error?@"Payload Manager did not respond.":(status!=200?[NSString stringWithFormat:@"Payload Manager returned HTTP %ld.",(long)status]:(data.length>1024*1024?@"Payload Manager response was too large.":nil));
            done(data,failure);
        });
    }] resume];
}
- (void)probeFailed:(nw_connection_t)c absent:(BOOL)absent {
    if(!_active||_socket!=c)return;nw_connection_cancel(c);_socket=nil;
    [self record:absent?@"helper_absent":@"probe_did_not_confirm_absence" state:0 code:0];
    if(_update==QP_UPDATE_ABSENCE&&!absent) {
        [self finish:@"Could not confirm the old helper stopped. No replacement was sent."];return;
    }
    /* The old service has now fully released its port. End the shutdown
     * deadline before starting a potentially slower ELF/manager transfer. */
    if(_update==QP_UPDATE_ABSENCE&&absent)_update=QP_UPDATE_NONE;
    if(!_launched){if(absent)[self sendDirect];else [self finish:@"Controller service did not answer safely; no duplicate helper was sent."];return;}
    if(++_probes>=8){[self finish:@"Helper was sent but did not become ready. Check the PS5 before retrying."];return;}
    NSUInteger run=_runGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(self->_active&&self->_runGeneration==run)[self probe];});
}
- (void)waitForOldListener:(nw_connection_t)c {
    nw_connection_cancel(c);_socket=nil;
    if(++_exitProbes>=20){[self finish:@"The old helper is still running. No replacement was sent."];return;}
    NSUInteger run=_runGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(self->_active&&self->_runGeneration==run)[self probe];
    });
}
- (void)sendUpdateCommand:(uint8_t)kind socket:(nw_connection_t)c {
    uint8_t frame[8];qp_header(frame,kind,0);
    dispatch_data_t data=dispatch_data_create(frame,sizeof frame,dispatch_get_main_queue(),DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    nw_connection_send(c,data,NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,true,^(nw_error_t error){
        if(error&&self->_active&&self->_socket==c)[self finish:@"Helper update interrupted. No replacement was sent."];
    });
}
- (void)readUpdate:(nw_connection_t)c {
    nw_connection_receive(c,1,4096,^(dispatch_data_t content,nw_content_context_t context,bool complete,nw_error_t error){
        (void)context;if(!self->_active||self->_socket!=c)return;
        if(content)dispatch_data_apply(content,^bool(dispatch_data_t region,size_t offset,const void *buffer,size_t size){
            (void)region;(void)offset;[self->_hello appendBytes:buffer length:size];return true;
        });
        while(self->_hello.length>=8) {
            const uint8_t *p=self->_hello.bytes;
            if(!qp_valid_header(p)){[self finish:@"Invalid helper update response. No replacement was sent."];return;}
            size_t size=qp_u16(p+6);if(self->_hello.length<8+size)break;
            if(!qp_helper_update_reply(&self->_update,p[5],p+8,size)) {
                [self finish:@"The helper could not release its controller or confirm stopping. No replacement was sent."];return;
            }
            [self->_hello replaceBytesInRange:NSMakeRange(0,8+size) withBytes:NULL length:0];
            if(self->_update==QP_UPDATE_STOP) {
                [self say:@"Stopping mismatched helper…"];[self sendUpdateCommand:6 socket:c];
            }
        }
        if(error||complete) {
            if(!qp_helper_update_eof(&self->_update,complete&&!error,self->_hello.length!=0)) {
                [self finish:@"Clean helper shutdown was not confirmed. No replacement was sent."];return;
            }
            [self say:@"Verifying old helper stopped…"];[self waitForOldListener:c];return;
        }
        [self readUpdate:c];
    });
}
- (void)beginUpdate:(nw_connection_t)c {
    _update=QP_UPDATE_DETACH;_hello=[NSMutableData new];
    [self say:@"Updating helper · releasing controller…"];
    [self sendUpdateCommand:QP_DISCONNECT_CONTROLLER socket:c];[self readUpdate:c];
    NSUInteger run=_runGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self->_active&&self->_runGeneration==run&&self->_update!=QP_UPDATE_NONE&& !self->_launched)
            [self finish:@"Helper shutdown timed out. No replacement was sent."];
    });
}
- (void)readHello:(nw_connection_t)c {
    nw_connection_receive(c,1,28,^(dispatch_data_t content,nw_content_context_t context,bool complete,nw_error_t error){
        (void)context;if(!self->_active||self->_socket!=c)return;
        if(content)dispatch_data_apply(content,^bool(dispatch_data_t region,size_t offset,const void *buffer,size_t size){(void)region;(void)offset;[self->_hello appendBytes:buffer length:size];return true;});
        if(self->_hello.length>=28){
            if(!qp_loader_hello_valid(self->_hello.bytes,self->_hello.length,self->_launched)){[self finish:@"Unexpected or mismatched helper response; startup was not confirmed."];return;}
            const uint8_t *p=self->_hello.bytes;uint16_t version=qp_u16(p+10);uint32_t flags=qp_u32(p+20);
            if(qp_helper_needs_replacement(version)) {
                if(self->_update==QP_UPDATE_ABSENCE){[self waitForOldListener:c];return;}
                if(!qp_helper_can_update(version,flags)){[self finish:@"This helper cannot be safely updated automatically. No replacement was sent."];return;}
                [self record:@"mismatched_helper" state:version code:QP_BUNDLED_HELPER_VERSION];
                [self beginUpdate:c];return;
            }
            self->_update=QP_UPDATE_NONE;
            nw_connection_cancel(c);self->_socket=nil;
            [self say:@"Controller service verified."];
            if(self->_usedManager){
                [self http:@"POST" path:[@"/manage:delete?filename=" stringByAppendingString:self->_filename] body:nil done:^(NSData *data,NSString *failure){(void)data;(void)failure;[self finish:nil];}];
            }else [self finish:nil];
        }else if(error||complete){[self probeFailed:c absent:NO];}
        else [self readHello:c];
    });
}
- (BOOL)probeAbsent:(nw_connection_t)c error:(nw_error_t)error deadline:(BOOL)deadline {
    nw_path_t path=nw_connection_copy_current_path(c);
    if(path){nw_path_unsatisfied_reason_t why=nw_path_get_unsatisfied_reason(path);
        if(why==nw_path_unsatisfied_reason_local_network_denied||why==nw_path_unsatisfied_reason_wifi_denied||why==nw_path_unsatisfied_reason_cellular_denied)_probeBlocked=YES;}
    BOOL refused=error&&nw_error_get_error_domain(error)==nw_error_domain_posix&&nw_error_get_error_code(error)==ECONNREFUSED;
    if(_update==QP_UPDATE_ABSENCE)return qp_helper_replacement_allowed(_update,_probeConnected,_probeBlocked,refused);
    return qp_loader_service_absent(_probeConnected,_probeBlocked,path&&nw_path_get_status(path)==nw_path_status_satisfied,refused,deadline);
}
- (void)probe {
    if(!_active)return;_hello=[NSMutableData new];_probeConnected=_probeBlocked=NO;nw_connection_t c=[self socketOnPort:"9305"];
    nw_connection_set_state_changed_handler(c,^(nw_connection_state_t state,nw_error_t error){
        if(!self->_active||self->_socket!=c)return;
        int code=error?nw_error_get_error_code(error):0;[self record:@"helper_probe" state:state code:code];
        if(state==nw_connection_state_ready){self->_probeConnected=YES;[self readHello:c];}
        else if(state==nw_connection_state_waiting){
            if(error&&!(nw_error_get_error_domain(error)==nw_error_domain_posix&&(code==ECONNREFUSED||code==ETIMEDOUT)))self->_probeBlocked=YES;
            if([self probeAbsent:c error:error deadline:NO])[self probeFailed:c absent:YES];
        }else if(state==nw_connection_state_failed)[self probeFailed:c absent:[self probeAbsent:c error:error deadline:NO]];
    });
    nw_connection_start(c);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self->_active&&self->_socket==c&&self->_update!=QP_UPDATE_DETACH&&self->_update!=QP_UPDATE_STOP&&self->_update!=QP_UPDATE_EOF)
            [self probeFailed:c absent:[self probeAbsent:c error:nil deadline:YES]];
    });
}
- (void)directFailed:(nw_connection_t)c {
    if(!_active||_socket!=c)return;nw_connection_cancel(c);_socket=nil;
    if(qp_loader_fallback_allowed(_loaderConnected,_sendStarted))[self startManager];
    else [self finish:@"The helper transfer was interrupted. Check the PS5 before retrying; no second copy was sent."];
}
- (void)sendDirect {
    [self say:@"Starting controller service…"];nw_connection_t c=[self socketOnPort:"9021"];
    nw_connection_set_state_changed_handler(c,^(nw_connection_state_t state,nw_error_t error){
        if(!self->_active||self->_socket!=c)return;
        int code=error?nw_error_get_error_code(error):0;[self record:@"ELF loader" state:state code:code];
        if(state==nw_connection_state_waiting&&error&&nw_error_get_error_domain(error)==nw_error_domain_posix&&code==ECONNREFUSED){[self directFailed:c];return;}
        if(state==nw_connection_state_failed){[self directFailed:c];return;}
        if(state==nw_connection_state_ready&&!self->_sendStarted){
            self->_loaderConnected=self->_sendStarted=YES;
            dispatch_data_t data=dispatch_data_create(self->_image.bytes,self->_image.length,dispatch_get_main_queue(),DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            nw_connection_send(c,data,NW_CONNECTION_FINAL_MESSAGE_CONTEXT,true,^(nw_error_t sendError){
                if(!self->_active||self->_socket!=c)return;
                if(sendError){[self directFailed:c];return;}
                self->_launched=YES;[self say:@"Waiting for controller service…"];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                    if(!self->_active||self->_socket!=c)return;nw_connection_cancel(c);self->_socket=nil;[self probe];
                });
            });
        }
    });
    nw_connection_start(c);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self->_active&&self->_socket==c)[self directFailed:c];});
}
- (void)startManager {
    [self say:@"Starting service through Payload Manager…"];
    /* Alphabetic nonce avoids Payload Manager's version-suffix normalization.
     * Refuse collisions; upload never overwrites an existing folder or file. */
    NSString *uuid=[[NSUUID.UUID.UUIDString lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSMutableString *suffix=[NSMutableString new];
    for(NSUInteger i=0;i<16;i++){unichar ch=[uuid characterAtIndex:i];unsigned v=ch<='9'?ch-'0':ch-'a'+10;[suffix appendFormat:@"%c",'a'+v];}
    _stem=[@"uhnmeyker-ps5pad-" stringByAppendingString:suffix];_filename=[_stem stringByAppendingString:@".elf"];
    [self http:@"GET" path:@"/version" body:nil done:^(NSData *data,NSString *error){
        (void)data;if(error){[self finish:@"No ELF loader or Payload Manager is available. Start either on the jailbroken PS5."];return;}
        [self http:@"GET" path:[@"/manage:check?filename=" stringByAppendingString:self->_filename] body:nil done:^(NSData *checkData,NSString *checkError){
            id check=checkData?[NSJSONSerialization JSONObjectWithData:checkData options:0 error:nil]:nil;
            if(checkError||![check isKindOfClass:NSDictionary.class]||![check[@"folder_name"] isEqual:self->_stem]||![check[@"folder_exists"] isEqual:@NO]||![check[@"file_exists"] isEqual:@NO]){[self finish:@"Payload Manager could not provide an empty PS5 Pad folder. Existing payloads were preserved."];return;}
            [self uploadManager];
        }];
    }];
}
- (void)uploadManager {
    [self http:@"POST" path:[@"/manage:upload?filename=" stringByAppendingString:_filename] body:_image done:^(NSData *data,NSString *error){
        (void)data;if(error){[self finish:error];return;}
        [self http:@"GET" path:@"/list_payloads" body:nil done:^(NSData *listData,NSString *listError){
            id list=listData?[NSJSONSerialization JSONObjectWithData:listData options:0 error:nil]:nil;
            NSArray *paths=[list isKindOfClass:NSDictionary.class]?list[@"payloads"]:nil;NSString *stored=nil;
            if([paths isKindOfClass:NSArray.class])for(id p in paths)if([p isKindOfClass:NSString.class]&&qp_loader_owned_path([p UTF8String],self->_stem.UTF8String,self->_filename.UTF8String)){stored=p;break;}
            if(listError||!stored){[self finish:@"The uploaded helper was not listed in its own folder; launch was cancelled."];return;}
            self->_usedManager=YES;self->_launched=YES;
            [self http:@"POST" path:[@"/loadpayload:" stringByAppendingString:stored] body:nil done:^(NSData *launchData,NSString *launchError){
                (void)launchData;(void)launchError;/* Even a lost response may have launched it. Only probe, never relaunch. */
                [self say:@"Waiting for controller service…"];[self probe];
            }];
        }];
    }];
}
@end
