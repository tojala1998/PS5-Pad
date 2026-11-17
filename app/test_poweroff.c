#include "QPPowerPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    QPPowerAttempt p={0};
    assert(!qp_power_begin(&p,false,true));
    assert(!qp_power_begin(&p,true,false));
    assert(!qp_power_send_once(&p));
    /* No profile/helper/pad argument exists: pending ownership cannot block power. */
    assert(qp_power_available(true,&p));
    assert(qp_power_begin(&p,true,true));
    assert(!qp_power_begin(&p,true,true));
    qp_power_finish(&p); /* failure before a transfer permits a fresh confirmation */
    assert(!qp_power_begin(&p,false,true));
    assert(qp_power_begin(&p,true,true));
    assert(qp_power_send_once(&p));
    assert(!qp_power_send_once(&p));
    qp_power_finish(&p); /* success, cancellation, error and timeout never auto-retry */
    assert(!qp_power_available(true,&p));
    assert(!qp_power_begin(&p,true,true));
    assert(!qp_power_send_once(&p));
    puts("PASS: power needs explicit confirmation, not profile assignment; single send and no uncertain retry.");
}
