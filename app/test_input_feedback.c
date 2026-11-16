#include "QPInputFeedback.h"
#include "PMCP.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    QPInputFeedbackGate gate={0};
    uint64_t sent=gate.epoch;
    assert(qp_feedback_ack_is_current(&gate,sent,41,41,0));
    assert(!qp_feedback_ack_is_current(&gate,sent,41,40,0));
    assert(!qp_feedback_ack_is_current(&gate,sent,41,41,5));
    assert(!qp_feedback_ack_is_current(&gate,sent,0,0,0));
    qp_feedback_gate_reset(&gate); /* cancelled while the press was in flight */
    assert(!qp_feedback_ack_is_current(&gate,sent,41,41,0));
    assert(qp_feedback_ack_is_current(&gate,gate.epoch,42,42,0));

    QPButtonFeedback cross={0}, circle={0};
    assert(!qp_feedback_visible(&cross,10)); /* queued input alone has no feedback */
    assert(qp_feedback_acknowledge(&cross,1,10));
    uint64_t firstFlash=cross.generation;
    assert(cross.acknowledgedDown && qp_feedback_visible(&cross,10.001));
    /* A late press ACK followed immediately by release still has a visible flash. */
    assert(!qp_feedback_acknowledge(&cross,0,10.001));
    assert(!cross.acknowledgedDown && qp_feedback_visible(&cross,10.119));
    assert(!qp_feedback_visible(&cross,10.121));
    assert(!qp_feedback_visible(&circle,10.1));

    assert(qp_feedback_acknowledge(&cross,1,11));
    double until=cross.flashUntil;
    uint64_t heldGeneration=cross.generation;
    assert(!qp_feedback_acknowledge(&cross,1,11.05)); /* heartbeat ACK, no second haptic */
    assert(cross.flashUntil==until && cross.generation==heldGeneration);
    assert(qp_feedback_visible(&cross,12)); /* actual held state survives flash expiry */
    assert(!qp_feedback_acknowledge(&cross,0,12));
    assert(!qp_feedback_visible(&cross,12));

    /* Chords apply each bit independently; the already-held button never retriggers. */
    uint32_t mask=QP_CROSS;
    assert(qp_feedback_acknowledge(&cross,mask&QP_CROSS,13));
    assert(!qp_feedback_acknowledge(&circle,mask&QP_CIRCLE,13));
    mask|=QP_CIRCLE;
    assert(!qp_feedback_acknowledge(&cross,mask&QP_CROSS,13.01));
    assert(qp_feedback_acknowledge(&circle,mask&QP_CIRCLE,13.01));
    assert(!qp_feedback_acknowledge(&cross,0,13.02));
    uint64_t oldFlash=cross.generation;
    assert(qp_feedback_acknowledge(&cross,1,13.03)); /* fast repeat gets its own flash */
    assert(cross.generation!=oldFlash && cross.flashUntil>13.14);
    assert(!qp_feedback_timer_is_current(&cross,oldFlash));
    assert(!qp_feedback_timer_is_current(&cross,firstFlash));
    assert(qp_feedback_timer_is_current(&cross,cross.generation));

    uint64_t cancelledFlash=cross.generation;
    qp_feedback_reset(&cross);
    assert(!cross.acknowledgedDown && !qp_feedback_visible(&cross,13.04));
    assert(!qp_feedback_timer_is_current(&cross,cancelledFlash));
    assert(circle.acknowledgedDown); /* clearing one visual does not alter another */
    assert(qp_feedback_acknowledge(&cross,1,14));
    puts("PASS: ACK validity/epochs, delayed releases, per-button chords, repeat/heartbeat feedback and timer cancellation.");
}
