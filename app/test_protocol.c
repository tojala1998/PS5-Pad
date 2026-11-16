#include "PMCP.h"
#include "QPKodi.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    uint8_t frame[36];
    const uint8_t neutral[]={0x50,0x4d,0x43,0x50,1,2,28,0,1,0,0,0,0,0,0,0,
        128,128,128,128,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    QPState state=qp_neutral(); qp_state_frame(frame,1,state);
    assert(!memcmp(frame,neutral,36));
    state.buttons=QP_CROSS|QP_RIGHT; qp_state_frame(frame,0x01020304,state);
    assert(frame[8]==4 && frame[9]==3 && frame[10]==2 && frame[11]==1);
    assert(frame[12]==0x20 && frame[13]==0x40 && frame[14]==0 && frame[15]==0);
    assert(qp_u32(frame+8)==0x01020304 && qp_valid_header(frame));
    state.buttons=QP_L1; qp_state_frame(frame,2,state); assert(frame[12]==0 && frame[13]==4);
    state.buttons=QP_R1; qp_state_frame(frame,3,state); assert(frame[12]==0 && frame[13]==8);
    qp_state_frame(frame,4,qp_buttons(QP_PS)); assert(frame[12]==0 && frame[13]==0 && frame[14]==1);
    qp_state_frame(frame,5,qp_buttons(QP_L2));
    assert(frame[12]==0 && frame[13]==1 && frame[20]==255 && frame[21]==0);
    qp_state_frame(frame,6,qp_buttons(QP_R2));
    assert(frame[13]==2 && frame[20]==0 && frame[21]==255);
    assert(qp_kodi_action(0)==QP_DOWN && qp_kodi_action(4)==QP_UP);
    assert(qp_kodi_action(1)==QP_LEFT && qp_kodi_action(3)==QP_RIGHT);
    assert(qp_kodi_action(2)==QP_OPTIONS && qp_kodi_action(5)==0);
    uint8_t control[8]; qp_header(control,QP_INITIALIZE,0); assert(qp_valid_header(control) && control[5]==129);
    frame[4]=2; assert(!qp_valid_header(frame)); frame[4]=1;
    frame[6]=1; frame[7]=1; assert(!qp_valid_header(frame));
    puts("PASS: native frame encoder matches PMCP wire fixtures; invalid headers rejected.");
}
