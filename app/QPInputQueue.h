#ifndef QP_INPUT_QUEUE_H
#define QP_INPUT_QUEUE_H
#include "PMCP.h"

/* Preserve both edges of a tap while a preceding report awaits its ACK.
 * A short hold makes each edge visible to applications that poll the pad.
 * An overloaded connection must stop, rather than replay stale actions. */
#define QP_INPUT_CAPACITY 16
typedef struct { QPState state; double queuedAt; } QPInputEvent;
typedef struct {
    QPInputEvent events[QP_INPUT_CAPACITY];
    unsigned head, count;
    QPState target, sent;
    double sentAt;
} QPInputQueue;

static inline int qp_same_state(QPState a, QPState b) {
    return a.buttons==b.buttons && a.lx==b.lx && a.ly==b.ly &&
           a.rx==b.rx && a.ry==b.ry && a.l2==b.l2 && a.r2==b.r2;
}
static inline void qp_input_reset(QPInputQueue *q) {
    memset(q,0,sizeof *q); q->target=q->sent=qp_neutral();
}
static inline int qp_input_push(QPInputQueue *q, QPState state, double now) {
    if(qp_same_state(q->target,state)) return 1;
    if(q->count==QP_INPUT_CAPACITY) return 0;
    q->events[(q->head+q->count)%QP_INPUT_CAPACITY]=(QPInputEvent){state,now};
    q->count++; q->target=state; return 1;
}
/* 1: next report; 0: wait for its minimum dwell; -1: stale input. */
static inline int qp_input_next(QPInputQueue *q, double now, QPState *state) {
    if(!q->count) return 0;
    QPInputEvent *next=&q->events[q->head];
    if(now-next->queuedAt>0.75) return -1;
    double dwell=q->sent.buttons?0.090:0.035;
    if(now-q->sentAt<dwell) return 0;
    *state=next->state; q->head=(q->head+1)%QP_INPUT_CAPACITY; q->count--;
    q->sent=*state; q->sentAt=now; return 1;
}
#endif
