#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include "text_input.h"
static int opened;
static void trace(const char *action,unsigned mod,unsigned key) {
    const char *path=getenv("PADD_TEST_KEYBOARD_TRACE"); if(!path) return;
    FILE *f=fopen(path,"a"); if(!f) return;
    fprintf(f,"{\"action\":\"%s\",\"mod\":%u,\"key\":%u}\n",action,mod,key); fclose(f);
}
int text_backend_open(int32_t user) { (void)user;if(opened) return EBUSY;opened=1;trace("open",0,0);return 0; }
int text_backend_report(uint8_t mod,uint8_t key) { if(!opened) return ENODEV;trace("report",mod,key);return 0; }
int text_backend_close(void) {if(opened) {trace("report",0,0);trace("close",0,0);}opened=0;return 0;}
