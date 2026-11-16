#include "QPInputQueue.h"
#include <assert.h>
#include <stdio.h>

static QPState pressed(uint32_t buttons) { QPState s=qp_neutral(); s.buttons=buttons; return s; }
int main(void) {
    QPInputQueue q; QPState out; qp_input_reset(&q);
    /* Both events arrive before the outstanding neutral report is acknowledged. */
    assert(qp_input_push(&q,pressed(QP_CROSS),10.0));
    assert(qp_input_push(&q,qp_neutral(),10.01));
    assert(qp_input_next(&q,10.03,&out)==1 && out.buttons==QP_CROSS);
    assert(qp_input_next(&q,10.04,&out)==0);
    assert(qp_input_next(&q,10.121,&out)==1 && out.buttons==0);
    /* A second quick tap keeps its release gap and both of its own edges. */
    assert(qp_input_push(&q,pressed(QP_CROSS),10.13));
    assert(qp_input_push(&q,qp_neutral(),10.14));
    assert(qp_input_next(&q,10.15,&out)==0);
    assert(qp_input_next(&q,10.157,&out)==1 && out.buttons==QP_CROSS);
    assert(qp_input_next(&q,10.248,&out)==1 && out.buttons==0);
    assert(q.count==0);
    /* Coalesce redundant samples, preserve chord transitions. */
    qp_input_reset(&q);
    assert(qp_input_push(&q,pressed(QP_L1),20));
    assert(qp_input_push(&q,pressed(QP_L1),20.01) && q.count==1);
    assert(qp_input_push(&q,pressed(QP_L1|QP_R1),20.02));
    assert(qp_input_next(&q,20.03,&out)==1 && out.buttons==QP_L1);
    assert(qp_input_next(&q,20.121,&out)==1 && out.buttons==(QP_L1|QP_R1));
    /* Never replay stale taps or silently discard a release on overflow. */
    qp_input_reset(&q); qp_input_push(&q,pressed(QP_CIRCLE),30);
    assert(qp_input_next(&q,30.751,&out)==-1);
    qp_input_reset(&q);
    for(unsigned i=0;i<QP_INPUT_CAPACITY;i++) assert(qp_input_push(&q,pressed(i%2?0:QP_SQUARE),40));
    assert(!qp_input_push(&q,pressed(QP_CROSS),40));
    qp_input_reset(&q); assert(q.count==0 && q.target.buttons==0 && q.sent.buttons==0);
    /* Old press is still in flight when cancelled; repress arrives before its
     * ACK. Cancellation's neutral must be dequeued first, then dwell 35 ms. */
    qp_input_reset(&q); assert(qp_input_push(&q,pressed(QP_CROSS),50));
    assert(qp_input_next(&q,50,&out)==1 && out.buttons==QP_CROSS);
    qp_input_release(&q,50.01);
    assert(qp_input_push(&q,pressed(QP_CROSS),50.02));
    assert(qp_input_push(&q,qp_neutral(),50.025));
    assert(qp_input_next(&q,50.03,&out)==1 && out.buttons==0); /* old ACK arrives */
    assert(q.sent.buttons==0 && q.sentAt==50.03);
    assert(qp_input_next(&q,50.064,&out)==0);
    assert(qp_input_next(&q,50.066,&out)==1 && out.buttons==QP_CROSS);
    assert(qp_input_next(&q,50.155,&out)==0);
    assert(qp_input_next(&q,50.157,&out)==1 && out.buttons==0 && q.count==0);
    /* A cancelled hold with no new touch still sends exactly one neutral. */
    qp_input_release(&q,51);
    assert(qp_input_next(&q,51,&out)==1 && out.buttons==0);
    assert(q.count==0 && q.target.buttons==0 && q.sent.buttons==0);
    /* Cancellation also discards a full stale queue without losing its release. */
    qp_input_reset(&q);
    for(unsigned i=0;i<QP_INPUT_CAPACITY;i++) assert(qp_input_push(&q,pressed(i%2?0:QP_SQUARE),52));
    qp_input_release(&q,52.01);
    assert(q.count==1 && q.target.buttons==0);
    assert(qp_input_next(&q,52.02,&out)==1 && out.buttons==0 && q.count==0);
    /* New events cannot overwrite the mandatory release on overflow. */
    qp_input_release(&q,53);
    for(unsigned i=0;i<QP_INPUT_CAPACITY-1;i++) assert(qp_input_push(&q,pressed(i%2?0:QP_CIRCLE),53));
    assert(!qp_input_push(&q,pressed(QP_CROSS),53));
    assert(qp_input_next(&q,53.01,&out)==1 && out.buttons==0);
    qp_input_release(&q,54); assert(qp_input_next(&q,54.751,&out)==-1);
    puts("PASS: short taps survive delayed ACKs; repeat gaps, mandatory cancellation release, chords, stale input and overflow checked.");
}
