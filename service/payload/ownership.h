#ifndef QP_OWNERSHIP_H
#define QP_OWNERSHIP_H
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
/* Parse only console login-manager events. User/device ids are never inferred
 * from report success, the foreground user, or a cached assignment. */
enum owner_event_kind { OWNER_NONE, OWNER_ADD, OWNER_REMOVE, OWNER_CHANGE };
struct owner_event { enum owner_event_kind kind; uint32_t device, user; int controller; };
static inline int owner_hex(const char *line, const char *key, uint32_t *value) {
    const char *p=strstr(line,key); char *end;
    if(!p) return 0;
    p+=strlen(key);
    if(strncmp(p,"0x",2)) return 0;
    unsigned long long n=strtoull(p,&end,16);
    if(end==p+2 || *end!=']' || n>UINT32_MAX) return 0;
    *value=(uint32_t)n; return 1;
}
static inline struct owner_event owner_parse(const char *line) {
    struct owner_event e={0};
    const char *p=strstr(line,"#LOGIN MGR# Receive Event : SCE_MBUS_EVENT_DEVICE_");
    if(!p || !owner_hex(p,"[DeviceId:",&e.device)) return e;
    if(strstr(p,"SCE_MBUS_EVENT_DEVICE_ADDED ")) {
        e.kind=OWNER_ADD;
        e.controller=strstr(p,"[type:1]") && strstr(p,"[subType:22]");
    } else if(strstr(p,"SCE_MBUS_EVENT_DEVICE_REMOVED ")) e.kind=OWNER_REMOVE;
    else if(strstr(p,"SCE_MBUS_EVENT_DEVICE_OWNER_CHANGED ") && owner_hex(p,"[UserId:",&e.user)) e.kind=OWNER_CHANGE;
    return e;
}
#endif
