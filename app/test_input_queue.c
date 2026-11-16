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
    puts("PASS: short taps survive delayed ACKs; repeat gaps, chords, stale input and overflow checked.");
}
