#include "QPInitialization.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    QPInitialization s={0};
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_WAIT);
    assert(qp_initialization_request(&s,true));
    assert(qp_initialization_step(&s,false,false,false,false,false)==QP_INIT_CONNECT);
    /* connectTo publishes a temporary disconnect, then connecting before the
     * queued observer runs. Only that final state is delivered to this reducer. */
    assert(qp_initialization_step(&s,false,true,false,false,false)==QP_INIT_WAIT);
    assert(qp_initialization_step(&s,true,false,true,true,false)==QP_INIT_WAIT);
    assert(!qp_initialization_request(&s,true));
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_SEND);
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_WAIT);
    assert(qp_initialization_step(&s,false,false,false,false,false)==QP_INIT_FAIL); /* lost INIT reply */
    qp_initialization_complete(&s,true); assert(s.phase==QP_INIT_DONE);
    assert(qp_initialization_request(&s,true));
    assert(qp_initialization_step(&s,false,false,false,false,false)==QP_INIT_CONNECT);
    assert(qp_initialization_step(&s,false,false,false,false,true)==QP_INIT_LOAD);
    assert(qp_initialization_step(&s,false,true,false,false,false)==QP_INIT_WAIT);
    assert(qp_initialization_step(&s,true,false,true,true,false)==QP_INIT_WAIT);
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_SEND);
    qp_initialization_complete(&s,false);
    assert(qp_initialization_request(&s,true));
    assert(qp_initialization_step(&s,false,true,false,false,false)==QP_INIT_WAIT);
    assert(qp_initialization_step(&s,false,false,false,false,true)==QP_INIT_LOAD);
    assert(qp_initialization_step(&s,false,false,false,false,true)==QP_INIT_FAIL); /* never load twice */
    assert(qp_initialization_request(&s,true));
    assert(qp_initialization_step(&s,false,true,false,false,false)==QP_INIT_WAIT);
    assert(qp_initialization_step(&s,false,false,false,false,false)==QP_INIT_FAIL); /* denial/busy/protocol */
    assert(qp_initialization_request(&s,true)); qp_initialization_cancel(&s);
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_WAIT);
    assert(qp_initialization_request(&s,true));
    assert(qp_initialization_step(&s,true,false,false,false,false)==QP_INIT_FAIL);
    assert(qp_initialization_request(&s,false));
    assert(qp_initialization_step(&s,false,true,false,false,false)==QP_INIT_WAIT);
    assert(qp_initialization_step(&s,false,false,false,false,true)==QP_INIT_FAIL); /* automatic never loads */
    assert(qp_initialization_request(&s,true));
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_SEND);
    qp_initialization_cancel(&s); /* background/disconnect while sending */
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_WAIT);
    assert(qp_initialization_request(&s,true));
    assert(qp_initialization_step(&s,false,true,false,false,false)==QP_INIT_WAIT);
    assert(qp_initialization_step(&s,false,false,false,false,true)==QP_INIT_LOAD);
    qp_initialization_cancel(&s); /* console change/background during ELF load */
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_WAIT);
    assert(qp_should_auto_initialize(false,true,true,false,false,true,0));
    assert(!qp_should_auto_initialize(true,true,true,false,false,true,0));
    assert(!qp_should_auto_initialize(false,true,false,false,false,true,0));
    assert(!qp_should_auto_initialize(false,true,true,true,false,true,0));
    assert(!qp_should_auto_initialize(false,true,true,false,true,true,0));
    assert(!qp_should_auto_initialize(false,true,true,false,false,true,-1));
    puts("PASS: initialization queues once, loads at most once, cancels, and gates automatic initialization.");
}
