#include "QPHelperUpdate.h"
#include "QPLoaderPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    uint32_t flags=QP_CAP_CONTROL|QP_CAP_DISCONNECT_CONTROLLER;
    assert(qp_helper_needs_replacement(QP_BUNDLED_HELPER_VERSION-1));
    assert(qp_helper_can_update(QP_BUNDLED_HELPER_VERSION-1,flags));
    assert(!qp_helper_can_update(QP_BUNDLED_HELPER_VERSION,flags));
    assert(qp_helper_can_update(QP_BUNDLED_HELPER_VERSION+1,flags));
    assert(!qp_helper_can_update(0x0202,flags));
    assert(!qp_helper_can_update(0x0206,QP_CAP_CONTROL));
    QPHelperUpdate phase=QP_UPDATE_DETACH;
    uint8_t status[32]={0};qp_put32(status+16,UINT32_MAX);
    assert(qp_helper_update_reply(&phase,QP_DISCONNECT_CONTROLLER,status,32));
    assert(phase==QP_UPDATE_STOP);
    uint8_t ack[8]={0};
    assert(qp_helper_update_reply(&phase,QP_ACK,ack,8));
    assert(phase==QP_UPDATE_EOF);
    assert(!qp_helper_replacement_allowed(phase,false,false,true));
    assert(qp_helper_update_eof(&phase,true,false));
    assert(qp_helper_replacement_allowed(phase,false,false,true));
    assert(!qp_helper_replacement_allowed(phase,false,false,false));
    assert(!qp_helper_replacement_allowed(phase,true,false,true));
    assert(!qp_helper_replacement_allowed(phase,false,true,true));
    for(int fault=0;fault<4;fault++) {
        phase=QP_UPDATE_DETACH;uint8_t bad[32];memcpy(bad,status,32);
        if(fault==0)qp_put32(bad,5); /* removal failed */
        if(fault==1)qp_put32(bad+16,123); /* owned handle remains */
        if(fault==2)qp_put32(bad+20,1); /* still ready */
        assert(!qp_helper_update_reply(&phase,QP_DISCONNECT_CONTROLLER,bad,fault==3?31:32));
        assert(phase==QP_UPDATE_FAILED);
    }
    phase=QP_UPDATE_STOP;qp_put32(ack,42);
    assert(!qp_helper_update_reply(&phase,QP_ACK,ack,8)); /* unrelated input ACK */
    phase=QP_UPDATE_STOP;qp_put32(ack,0);qp_put32(ack+4,5);
    assert(!qp_helper_update_reply(&phase,QP_ACK,ack,8));
    phase=QP_UPDATE_DETACH;assert(!qp_helper_update_eof(&phase,true,false));
    phase=QP_UPDATE_EOF;assert(!qp_helper_update_eof(&phase,false,false));
    phase=QP_UPDATE_EOF;assert(!qp_helper_update_eof(&phase,true,true));
    phase=QP_UPDATE_EOF;assert(!qp_helper_update_reply(&phase,QP_ACK,ack,8));
    uint8_t hello[28]={0};qp_header(hello,QP_HELLO,20);hello[8]=1;
    hello[10]=(QP_BUNDLED_HELPER_VERSION-1)&255;hello[11]=(QP_BUNDLED_HELPER_VERSION-1)>>8;
    qp_put32(hello+20,flags);
    assert(qp_loader_hello_valid(hello,28,false));
    assert(!qp_loader_hello_valid(hello,28,true)); /* replaced service still outdated */
    hello[10]=QP_BUNDLED_HELPER_VERSION&255;hello[11]=QP_BUNDLED_HELPER_VERSION>>8;
    assert(qp_loader_hello_valid(hello,28,true));
    hello[10]=(QP_BUNDLED_HELPER_VERSION+1)&255;hello[11]=(QP_BUNDLED_HELPER_VERSION+1)>>8;
    assert(qp_loader_hello_valid(hello,28,false));
    assert(!qp_loader_hello_valid(hello,28,true)); /* newer is also the wrong replacement */
    puts("PASS: old/current/new versions, confirmed detach-stop-EOF-refusal ordering, failures, and post-load version verification.");
}
