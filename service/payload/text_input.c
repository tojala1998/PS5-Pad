#include <errno.h>
#include <string.h>
#include "text_input.h"
#include "../../experiments/keyboard-probe/ascii.h"
int text_begin(struct text_job *j,int32_t user,const uint8_t *text,size_t length,uint64_t now) {
    if(j->active || j->cleanup) return EBUSY;
    if(!length || length>sizeof j->text) return EINVAL;
    for(size_t i=0;i<length;i++) {uint8_t mod,key; if(!ascii_key(text[i],&mod,&key)) return EINVAL;}
    int rc=text_backend_open(user); if(rc) return rc;
    memset(j,0,sizeof *j); memcpy(j->text,text,length); j->length=(unsigned)length;
    j->active=1; j->started=now; j->due=now+150; return 0;
}
void text_cancel(struct text_job *j,int status) {
    if(!j->active && !j->cleanup) return;
    j->active=0; j->cleanup=1; if(!j->status) j->status=status;
    memset(j->text,0,sizeof j->text); j->due=0;
}
int text_tick(struct text_job *j,uint64_t now) {
    if(j->cleanup) {
        if(now<j->due) return 0;
        int rc=text_backend_close();
        if(rc) {if(!j->status) j->status=rc;j->due=now+100;return 0;}
        j->cleanup=0; j->held=0; return 1;
    }
    if(!j->active || now<j->due) return 0;
    if(now-j->started>15000) {text_cancel(j,ETIMEDOUT);return text_tick(j,now);}
    uint8_t mod=0,key=0;
    if(!j->held) ascii_key(j->text[j->index],&mod,&key);
    int rc=text_backend_report(mod,key);
    if(rc) {text_cancel(j,rc);return text_tick(j,now);}
    if(j->held) {j->index++; j->held=0;} else j->held=1;
    if(j->index==j->length) {text_cancel(j,0);return text_tick(j,now);}
    j->due=now+40; return 0;
}
