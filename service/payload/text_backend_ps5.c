/* GPL-3.0-compatible keyboard implementation retained under experiments/. */
#include "text_input.h"
#include "../../experiments/keyboard-probe/third_party/kbm.h"
static ps_keyboard *keyboard;
int text_backend_open(int32_t user) { return ps_keyboard_open((uint32_t)user,&keyboard); }
int text_backend_report(uint8_t mod,uint8_t key) { return ps_keyboard_send(keyboard,mod,key?&key:0,key?1:0); }
int text_backend_close(void) { return ps_keyboard_try_close(&keyboard); }
