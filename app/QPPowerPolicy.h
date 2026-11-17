#ifndef QP_POWER_POLICY_H
#define QP_POWER_POLICY_H
#include <stdbool.h>
typedef struct { bool active, sent; } QPPowerAttempt;
/* Deliberately independent of profile, pad, helper version and controller busy. */
static inline bool qp_power_available(bool hostKnown, const QPPowerAttempt *p) {
    return hostKnown && !p->active && !p->sent;
}
static inline bool qp_power_begin(QPPowerAttempt *p, bool confirmed, bool hostKnown) {
    if (!confirmed || !qp_power_available(hostKnown,p)) return false;
    p->active=true; return true;
}
static inline bool qp_power_send_once(QPPowerAttempt *p) {
    if (!p->active || p->sent) return false;
    p->sent=true; return true;
}
static inline void qp_power_finish(QPPowerAttempt *p) { p->active=false; }
#endif
