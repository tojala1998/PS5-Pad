#include <errno.h>
#include <string.h>
#include "live_keyboard.h"
#include "text_input.h"
#include "../../experiments/keyboard-probe/ascii.h"
void live_cancel(struct live_keyboard *k,int status) {
    if(!k->opened && !k->cleanup) return;
    k->cleanup=1; if(!k->status) k->status=status; k->due=0;
    memset(k->keys,0,sizeof k->keys); memset(k->mods,0,sizeof k->mods);
}
int live_request(struct live_keyboard *k,int32_t user,const uint8_t *p,size_t n,uint64_t now) {
    if(!n || p[0]>3) return EINVAL;
    if(k->busy || k->cleanup) return EBUSY;
    unsigned op=p[0],deletes=0,len=0;
    if(op==1) {
        if(n<3 || n>131) return EINVAL;
        deletes=p[1]|((unsigned)p[2]<<8);len=(unsigned)n-3;
        if(deletes>128 || (!deletes&&!len)) return EINVAL;
        for(unsigned i=0;i<len;i++) {uint8_t m,v;if(!ascii_key(p[3+i],&m,&v)) return EINVAL;}
    } else if(n!=1) return EINVAL;
    if(op==0) {
        if(k->opened) return EALREADY;
        int rc=text_backend_open(user);if(rc)return rc;
        memset(k,0,sizeof *k); k->opened=1;k->lease=now+1800;k->due=now+1000;
    } else {
        if(!k->opened) return ENODEV;
        k->due=now;k->status=0;k->length=0;k->index=0;k->held=0;
    }
    k->busy=1;k->op=(int)op;
    if(op==1) {
        for(unsigned i=0;i<deletes;i++) {k->keys[i]=42;k->mods[i]=0;}
        for(unsigned i=0;i<len;i++) ascii_key(p[3+i],&k->mods[deletes+i],&k->keys[deletes+i]);
        k->length=deletes+len;
    } else if(op==2) live_cancel(k,0);
    else if(op==3) {k->keys[0]=40;k->mods[0]=0;k->length=1;}
    return 0;
}
int live_tick(struct live_keyboard *k,uint64_t now) {
    if(k->opened && !k->cleanup && now>=k->lease) live_cancel(k,ETIMEDOUT);
    if(k->cleanup) {
        if(now<k->due)return 0;
        int rc=text_backend_close();if(rc){if(!k->status)k->status=rc;k->due=now+100;return 0;}
        int reply=k->busy;k->opened=0;k->busy=0;k->cleanup=0;k->held=0;return reply;
    }
    if(!k->busy || now<k->due)return 0;
    if(k->op==0) {k->busy=0;return 1;}
    if(k->index==k->length) {
        if(k->op==3){live_cancel(k,0);return live_tick(k,now);}
        k->busy=0;memset(k->keys,0,sizeof k->keys);memset(k->mods,0,sizeof k->mods);return 1;
    }
    int rc=text_backend_report(k->held?0:k->mods[k->index],k->held?0:k->keys[k->index]);
    if(rc){live_cancel(k,rc);return live_tick(k,now);}
    if(k->held){k->held=0;k->index++;}else k->held=1;
    k->due=now+40;return 0;
}
