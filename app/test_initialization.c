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
    /* Sleep cancels transient requests but preserves the service-owned pad.
     * Wait for fresh STATUS; a ready existing pad needs neither a prompt nor INIT. */
    qp_initialization_cancel(&s);
    assert(!qp_resume_reuses_controller(false,false,false,false));
    assert(!qp_resume_reuses_controller(true,false,true,true));
    assert(!qp_should_auto_initialize(false,true,false,true,true,true,0));
    assert(qp_resume_reuses_controller(true,true,true,false));
    assert(!qp_should_auto_initialize(false,true,true,true,false,true,0));
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_WAIT);
    /* An explicit Initialize still replaces that controller when requested. */
    assert(qp_initialization_request(&s,true));
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_SEND);
    qp_initialization_cancel(&s);
    /* A fresh status proving absence retains the single automatic attempt. */
    assert(!qp_resume_reuses_controller(true,true,false,false));
    assert(qp_should_auto_initialize(false,true,true,false,false,true,0));
    assert(qp_initialization_request(&s,false));
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_SEND);
    assert(!qp_should_auto_initialize(true,true,true,false,false,true,0));
    assert(qp_initialization_step(&s,true,false,false,true,false)==QP_INIT_WAIT);
    /* Saved-console bring-up has three bounded connects, then at most one
     * qualified load. None of these actions creates or replaces a controller. */
    QPEnsureSession ensure={0}; unsigned delay=99;
    qp_ensure_begin(&ensure);
    assert(qp_ensure_next(&ensure,false,&delay)==QP_ENSURE_CONNECT && delay==0);
    assert(qp_ensure_next(&ensure,true,&delay)==QP_ENSURE_CONNECT && delay==1);
    assert(qp_ensure_next(&ensure,true,&delay)==QP_ENSURE_CONNECT && delay==2);
    assert(qp_ensure_next(&ensure,true,&delay)==QP_ENSURE_LOAD && ensure.loaded);
    assert(qp_ensure_next(&ensure,true,&delay)==QP_ENSURE_STOP && !ensure.active);
    qp_ensure_begin(&ensure);
    for(unsigned i=0;i<3;i++) assert(qp_ensure_next(&ensure,false,&delay)==QP_ENSURE_CONNECT);
    assert(qp_ensure_next(&ensure,false,&delay)==QP_ENSURE_STOP && !ensure.loaded); /* permission/protocol/busy */
    qp_ensure_begin(&ensure); assert(qp_ensure_next(&ensure,false,&delay)==QP_ENSURE_CONNECT);
    qp_ensure_cancel(&ensure); /* HELLO, background, explicit disconnect, host change, or manual takeover */
    assert(qp_ensure_next(&ensure,true,&delay)==QP_ENSURE_STOP && !ensure.loaded);
    qp_ensure_begin(&ensure);
    assert(qp_ensure_next(&ensure,false,&delay)==QP_ENSURE_CONNECT);
    assert(qp_ensure_next(&ensure,false,&delay)==QP_ENSURE_CONNECT && ensure.loadBlocked); /* Other result */
    assert(qp_ensure_next(&ensure,true,&delay)==QP_ENSURE_CONNECT);
    assert(qp_ensure_next(&ensure,true,&delay)==QP_ENSURE_STOP && !ensure.loaded); /* later refusal cannot erase denial/busy/protocol */
    qp_ensure_begin(&ensure); assert(ensure.attempts==0 && !ensure.loaded && ensure.active);
    puts("PASS: initialization queues once, loads at most once, cancels, resumes an existing controller, and bounds automatic session bring-up.");
}
