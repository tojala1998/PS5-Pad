#import "QPLocalNetworkAccess.h"
#import <Network/Network.h>
#import <UIKit/UIKit.h>

@interface QPLocalNetworkAccess () {
    nw_listener_t _listener;
    nw_browser_t _browser;
    NSUInteger _generation;
    NSTimer *_timer;
    NSUInteger _activeTicks;
}
@end
@implementation QPLocalNetworkAccess
- (void)cancel {
    _generation++; [_timer invalidate]; _timer=nil;
    if(_browser) { nw_browser_cancel(_browser); _browser=nil; }
    if(_listener) { nw_listener_cancel(_listener); _listener=nil; }
}
- (void)dealloc { [self cancel]; }
- (void)request {
    [self cancel]; NSUInteger generation=_generation; _activeTicks=0;
    if(_changed) _changed(QPLocalAccessChecking);
    /* iOS exposes no permission-query API. Successful Bonjour discovery of our
     * unique temporary service demonstrates access. Merely reaching .ready,
     * a timeout, or a TCP error does not. No console is contacted here. */
    NSString *token=NSUUID.UUID.UUIDString;
    const char *type="_ps5pad-access._tcp";
    nw_parameters_t parameters=nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION);
    _listener=nw_listener_create(parameters);
    _browser=nw_browser_create(nw_browse_descriptor_create_bonjour_service(type,NULL),parameters);
    if(!_listener || !_browser) { [self cancel]; if(_changed) _changed(QPLocalAccessFailed); return; }
    nw_listener_set_queue(_listener,dispatch_get_main_queue());
    nw_browser_set_queue(_browser,dispatch_get_main_queue());
    nw_listener_set_advertise_descriptor(_listener,nw_advertise_descriptor_create_bonjour_service(token.UTF8String,type,NULL));
    nw_listener_set_new_connection_handler(_listener,^(nw_connection_t connection){ nw_connection_cancel(connection); });
    __weak QPLocalNetworkAccess *weakSelf=self;
    nw_listener_set_state_changed_handler(_listener,^(nw_listener_state_t state,nw_error_t error){
        (void)error; QPLocalNetworkAccess *self=weakSelf; if(!self || generation!=self->_generation) return;
        if(state==nw_listener_state_failed) { [self cancel]; if(self.changed) self.changed(QPLocalAccessFailed); }
    });
    nw_browser_set_state_changed_handler(_browser,^(nw_browser_state_t state,nw_error_t error){
        QPLocalNetworkAccess *self=weakSelf; if(!self || generation!=self->_generation) return;
        if(state==nw_browser_state_waiting) {
            /* PolicyDenied can precede the person's answer. Keep browsing so
             * Allow resumes the check without a second tap. */
            if(self.changed) self.changed(QPLocalAccessWaiting);
        } else if(state==nw_browser_state_failed) {
            BOOL policy=error && nw_error_get_error_domain(error)==nw_error_domain_dns && nw_error_get_error_code(error)==-65570;
            [self cancel]; if(self.changed) self.changed(policy?QPLocalAccessWaiting:QPLocalAccessFailed);
        }
    });
    nw_browser_set_browse_results_changed_handler(_browser,^(nw_browse_result_t oldResult,nw_browse_result_t newResult,bool complete){
        (void)oldResult; (void)complete; QPLocalNetworkAccess *self=weakSelf;
        if(!self || generation!=self->_generation || !newResult) return;
        nw_endpoint_t endpoint=nw_browse_result_copy_endpoint(newResult);
        const char *name=nw_endpoint_get_bonjour_service_name(endpoint);
        if(name && [token isEqualToString:[NSString stringWithUTF8String:name]]) {
            [self cancel]; if(self.changed) self.changed(QPLocalAccessAllowed);
        }
    });
    _timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){
        (void)timer; QPLocalNetworkAccess *self=weakSelf;
        if(!self || generation!=self->_generation) return;
        /* Do not run down a timeout while iOS is asking for permission. */
        if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
        if(++self->_activeTicks==20 && self.changed) self.changed(QPLocalAccessWaiting);
    }];
    nw_listener_start(_listener); nw_browser_start(_browser);
}
@end
