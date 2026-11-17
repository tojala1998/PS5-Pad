#import "QPPowerOff.h"
#import "QPPowerPolicy.h"
#import "QPLoaderPolicy.h"
#import <Network/Network.h>
#include <errno.h>

@interface QPPowerOff () {
    nw_connection_t _socket;
    NSData *_image;
    QPPowerAttempt _attempt;
    NSUInteger _generation;
}
@end
@implementation QPPowerOff
- (BOOL)available { return qp_power_available(true,&_attempt); }
- (void)finish:(NSString *)message {
    if(!_attempt.active)return;
    qp_power_finish(&_attempt);
    nw_connection_t socket=_socket; _socket=nil;
    if(socket)nw_connection_cancel(socket);
    _image=nil;
    if(_completed)_completed(message);
}
- (void)cancel {
    if(!_attempt.active)return;
    [self finish:_attempt.sent?@"Shutdown result unknown. Check the PS5; the command was not retried.":@"Power off cancelled before sending a shutdown command."];
}
- (void)requestAt:(NSString *)host confirmed:(BOOL)confirmed {
    if(!qp_power_begin(&_attempt,confirmed,host.length>0))return;
    _image=[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"ps5pad-poweroff" ofType:@"elf"]];
    if(!qp_loader_image_valid(_image.bytes,_image.length)) {
        [self finish:@"The dedicated power-off payload is missing or invalid. No shutdown command was sent."];return;
    }
    NSUInteger generation=++_generation;
    nw_connection_t socket=nw_connection_create(nw_endpoint_create_host(host.UTF8String,"9021"),nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION));
    _socket=socket;
    nw_connection_set_queue(socket,dispatch_get_main_queue());
    nw_connection_set_state_changed_handler(socket,^(nw_connection_state_t state,nw_error_t error){
        if(generation!=self->_generation||!self->_attempt.active||self->_socket!=socket)return;
        if(state==nw_connection_state_ready) {
            if(!qp_power_send_once(&self->_attempt))return;
            dispatch_data_t data=dispatch_data_create(self->_image.bytes,self->_image.length,dispatch_get_main_queue(),DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            /* One complete ELF, then TCP write half-close, as used by .13's loader.
             * Never send PMCP 137 to an old controller helper, replace that helper,
             * initialize a controller, or retry an ambiguous transfer. */
            nw_connection_send(socket,data,NW_CONNECTION_FINAL_MESSAGE_CONTEXT,true,^(nw_error_t sendError){
                if(generation!=self->_generation||!self->_attempt.active||self->_socket!=socket)return;
                [self finish:sendError?@"Shutdown result unknown. Check the PS5; the command was not retried.":@"Full-power-off request sent. Check that the PS5 turns fully off, not into Rest Mode. It was not retried."];
            });
        } else if(state==nw_connection_state_failed || (state==nw_connection_state_waiting&&error)) {
            [self finish:self->_attempt.sent?@"Shutdown result unknown. Check the PS5; the command was not retried.":@"Cannot reach the PS5 ELF loader on port 9021. No shutdown command was sent. Start the ELF loader and try again."];
        }
    });
    nw_connection_start(socket);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(generation!=self->_generation||!self->_attempt.active||self->_socket!=socket)return;
        [self finish:self->_attempt.sent?@"Shutdown result unknown. Check the PS5; the command was not retried.":@"The PS5 ELF loader did not connect. No shutdown command was sent."];
    });
}
@end
