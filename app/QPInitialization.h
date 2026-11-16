#ifndef QP_INITIALIZATION_H
#define QP_INITIALIZATION_H
#include <stdbool.h>
typedef enum { QP_INIT_IDLE, QP_INIT_WAITING, QP_INIT_SENT, QP_INIT_DONE, QP_INIT_FAILED } QPInitPhase;
typedef enum { QP_INIT_WAIT, QP_INIT_CONNECT, QP_INIT_LOAD, QP_INIT_SEND, QP_INIT_FAIL } QPInitAction;
typedef struct { QPInitPhase phase; bool attempted, loaded, allowLoad; } QPInitialization;
static inline bool qp_initialization_pending(const QPInitialization *s) { return s->phase==QP_INIT_WAITING || s->phase==QP_INIT_SENT; }
static inline bool qp_initialization_request(QPInitialization *s,bool allowLoad) {
    if(qp_initialization_pending(s)) return false;
    *s=(QPInitialization){.phase=QP_INIT_WAITING,.allowLoad=allowLoad}; return true;
}
static inline void qp_initialization_cancel(QPInitialization *s) { *s=(QPInitialization){0}; }
static inline void qp_initialization_complete(QPInitialization *s,bool success) { s->phase=success?QP_INIT_DONE:QP_INIT_FAILED; }
/* Observe after synchronous connection mutations have finished. A temporary
 * disconnect publish inside connect/load is not an observation of failure. */
static inline QPInitAction qp_initialization_step(QPInitialization *s,bool ready,bool connecting,bool controlBusy,bool supportsControl,bool unavailable) {
    if(s->phase==QP_INIT_SENT && !ready) { s->phase=QP_INIT_FAILED; return QP_INIT_FAIL; }
    if(s->phase!=QP_INIT_WAITING) return QP_INIT_WAIT;
    if(ready) {
        s->attempted=true;
        if(!supportsControl) { s->phase=QP_INIT_FAILED; return QP_INIT_FAIL; }
        if(controlBusy) return QP_INIT_WAIT;
        s->phase=QP_INIT_SENT; return QP_INIT_SEND;
    }
    if(connecting) { s->attempted=true; return QP_INIT_WAIT; }
    if(!s->attempted) { s->attempted=true; return QP_INIT_CONNECT; }
    if(unavailable && s->allowLoad && !s->loaded) { s->loaded=true; return QP_INIT_LOAD; }
    s->phase=QP_INIT_FAILED; return QP_INIT_FAIL;
}
static inline bool qp_should_auto_initialize(bool attempted,bool ready,bool checked,bool padReady,bool busy,bool supportsControl,int userStatus) {
    return !attempted && ready && checked && !padReady && !busy && supportsControl && userStatus==0;
}
#endif
