#ifndef QP_LOADER_POLICY_H
#define QP_LOADER_POLICY_H
#include <stdbool.h>
#include <string.h>
#include "PMCP.h"
#include "QPHelperVersion.h"
static inline bool qp_loader_image_valid(const void *data,size_t size) {
    const unsigned char *p=data;
    return p&&size>=64&&size<=64u*1024u*1024u&&!memcmp(p,"\177ELF",4)&&p[4]==2&&p[5]==1&&qp_u16(p+18)==62;
}
static inline bool qp_loader_fallback_allowed(bool connected,bool sendStarted) {return !connected&&!sendStarted;}
/* NWConnection may report ECONNREFUSED as waiting, never failed. A healthy
 * path's bounded connect timeout can also mean absent. An accepted socket,
 * permission denial or other blocked path must never authorize a new helper. */
static inline bool qp_loader_service_absent(bool connected,bool blocked,bool pathReady,bool refused,bool deadline) {
    return !connected&&!blocked&&(refused||(deadline&&pathReady));
}
/* Accept only the dedicated, newly allocated Payload Manager directory. */
static inline bool qp_loader_owned_path(const char *path,const char *stem,const char *filename) {
    if(!path||!stem||!filename||strncmp(stem,"uhnmeyker-ps5pad-",16))return false;
    const char *prefix="/data/pldmgr/payloads/";
    if(strncmp(path,prefix,strlen(prefix)))return false;
    const char *p=path+strlen(prefix);if(!strncmp(p,"local/",6))p+=6;
    size_t n=strlen(stem);
    return !strncmp(p,stem,n)&&p[n]=='/'&&!strcmp(p+n+1,filename)&&!strstr(path,"..");
}
static inline bool qp_loader_hello_valid(const unsigned char *p,size_t n,bool launched) {
    return n==28&&!memcmp(p,"PMCP",4)&&p[4]==1&&p[5]==QP_HELLO&&qp_u16(p+6)==20&&qp_u16(p+8)==1&&
        (qp_u32(p+20)&QP_CAP_CONTROL)&&(!launched||qp_u16(p+10)>=QP_BUNDLED_HELPER_VERSION);
}
#endif
