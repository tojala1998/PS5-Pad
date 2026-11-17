#ifndef QUIETPAD_PMCP_H
#define QUIETPAD_PMCP_H
#include <stdint.h>
#include <string.h>

enum { QP_HELLO=1, QP_STATE=2, QP_PING=3, QP_ACK=4, QP_ERROR=5,
       QP_STATUS=128, QP_INITIALIZE=129, QP_VLC=130, QP_KODI=131, QP_DISCONNECT_CONTROLLER=132, QP_TYPE_TEXT=133, QP_LIVE_KEYBOARD=134, QP_KEYBOARD_LEASE=135, QP_APP_STATE=136, QP_POWER_OFF=137 };
enum { QP_CAP_CONTROL=0x10000, QP_CAP_DISCONNECT_CONTROLLER=0x20000, QP_CAP_OWNERSHIP=0x40000,
       QP_PROFILE_ASSIGNED=0x80000, QP_PROFILE_PENDING=0x100000, QP_YIELDED=0x200000, QP_MONITOR_READY=0x400000, QP_CAP_TEXT_INPUT=0x800000, QP_CAP_LIVE_KEYBOARD=0x1000000, QP_CAP_APP_STATE=0x2000000, QP_CAP_POWER_OFF=0x4000000 };
enum { QP_L3=2, QP_R3=4, QP_OPTIONS=8, QP_UP=0x10, QP_RIGHT=0x20,
       QP_DOWN=0x40, QP_LEFT=0x80, QP_L2=0x100, QP_R2=0x200,
       QP_L1=0x400, QP_R1=0x800, QP_TRIANGLE=0x1000, QP_CIRCLE=0x2000,
       QP_CROSS=0x4000, QP_SQUARE=0x8000, QP_PS=0x10000, QP_TOUCH=0x100000 };
typedef struct { uint32_t buttons; uint8_t lx,ly,rx,ry,l2,r2; } QPState;
static inline uint16_t qp_u16(const uint8_t *p) { return p[0] | ((uint16_t)p[1]<<8); }
static inline uint32_t qp_u32(const uint8_t *p) { return qp_u16(p) | ((uint32_t)qp_u16(p+2)<<16); }
static inline int qp_supports_disconnect(uint16_t payloadVersion,uint32_t flags) {
    return payloadVersion>=0x0203 && (flags&QP_CAP_CONTROL) && (flags&QP_CAP_DISCONNECT_CONTROLLER);
}
static inline int qp_disconnect_response_valid(const uint8_t *status) {
    return qp_u32(status)==0 && !(qp_u32(status+20)&1) && (int32_t)qp_u32(status+16)<0;
}
static inline void qp_put32(uint8_t *p,uint32_t n) { for(int i=0;i<4;i++) p[i]=(uint8_t)(n>>(i*8)); }
static inline QPState qp_neutral(void) { return (QPState){0,128,128,128,128,0,0}; }
static inline QPState qp_buttons(uint32_t buttons) {
    QPState state=qp_neutral(); state.buttons=buttons;
    state.l2=(buttons&QP_L2)?255:0; state.r2=(buttons&QP_R2)?255:0;
    return state;
}
static inline void qp_header(uint8_t *p,uint8_t kind,uint16_t length) {
    memcpy(p,"PMCP",4); p[4]=1; p[5]=kind; p[6]=length&255; p[7]=length>>8;
}
static inline int qp_valid_header(const uint8_t *p) {
    return !memcmp(p,"PMCP",4) && p[4]==1 && qp_u16(p+6)<=256;
}
static inline void qp_state_frame(uint8_t *p,uint32_t seq,QPState s) {
    memset(p,0,36); qp_header(p,QP_STATE,28); qp_put32(p+8,seq); qp_put32(p+12,s.buttons);
    p[16]=s.lx; p[17]=s.ly; p[18]=s.rx; p[19]=s.ry; p[20]=s.l2; p[21]=s.r2;
}
#endif
