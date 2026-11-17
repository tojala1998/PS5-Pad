#ifndef QP_LIVE_KEYBOARD_H
#define QP_LIVE_KEYBOARD_H
#include <stdint.h>
#include <stddef.h>
/* One client-owned keyboard. Commands are serialized; no replay after reconnect. */
struct live_keyboard { int opened,busy,cleanup,held,status,op; unsigned length,index; uint8_t keys[256],mods[256]; uint64_t due,lease; };
int live_request(struct live_keyboard *k,int32_t user,const uint8_t *p,size_t n,uint64_t now);
void live_cancel(struct live_keyboard *k,int status);
int live_tick(struct live_keyboard *k,uint64_t now);
#endif
