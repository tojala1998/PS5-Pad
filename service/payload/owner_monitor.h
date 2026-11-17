#ifndef QP_OWNER_MONITOR_H
#define QP_OWNER_MONITOR_H
#include "ownership.h"
struct owner_monitor {
    int fd,connecting,synced,enabled;
    uint64_t retry_at,connect_at;
    char line[2048]; size_t length; int overflow;
    uint32_t controllers[64];
};
void owner_monitor_init(struct owner_monitor *m);
/* Calls event only for current-stream events. Initial server backlog is drained
 * before initialization is allowed. No /dev/klog reader is created. */
int owner_monitor_poll(struct owner_monitor *m,uint64_t now,
                       void (*event)(void *,struct owner_event),void *context);
void owner_monitor_close(struct owner_monitor *m);
#endif
