#ifndef QP_LIFECYCLE_H
#define QP_LIFECYCLE_H
#include <stdbool.h>
#include <stdint.h>
/* UISceneDelegate owns activity. UIApplication's aggregate state can lag the
 * scene callback, so it is deliberately not an input to this component. */
typedef struct {
    bool active,viewReady,queued,started;
    uint64_t generation;
    unsigned activations,suspends,starts;
} QPLifecycle;
static inline bool qp_lifecycle_activate(QPLifecycle *s) {
    if(s->active) return false;
    s->active=true; s->queued=false; s->started=false; s->generation++; s->activations++; return true;
}
static inline void qp_lifecycle_view_ready(QPLifecycle *s) { s->viewReady=true; }
static inline void qp_lifecycle_suspend(QPLifecycle *s) {
    s->active=false; s->queued=false; s->started=false; s->generation++; s->suspends++;
}
static inline uint64_t qp_lifecycle_queue_start(QPLifecycle *s) {
    if(!s->active || !s->viewReady || s->queued || s->started) return 0;
    s->queued=true; return s->generation;
}
static inline bool qp_lifecycle_is_current(const QPLifecycle *s,uint64_t generation) {
    return s->active && s->viewReady && generation==s->generation;
}
static inline bool qp_lifecycle_take_start(QPLifecycle *s,uint64_t generation) {
    if(!qp_lifecycle_is_current(s,generation) || !s->queued || s->started) return false;
    s->queued=false; s->started=true; s->starts++; return true;
}
#endif
