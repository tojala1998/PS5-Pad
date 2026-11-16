#ifndef QP_INPUT_FEEDBACK_H
#define QP_INPUT_FEEDBACK_H
#include <stdint.h>

/* A local touch is desired input. Only a successful, current report ACK may
 * advance registered feedback. Clearing controls invalidates in-flight feedback
 * without discarding the transport ACK that permits the neutral report to send. */
typedef struct { uint64_t epoch; } QPInputFeedbackGate;
static inline void qp_feedback_gate_reset(QPInputFeedbackGate *gate) { gate->epoch++; }
static inline int qp_feedback_ack_is_current(const QPInputFeedbackGate *gate,
                                             uint64_t sentEpoch, uint32_t expected,
                                             uint32_t received, int32_t status) {
    return expected && expected==received && status==0 && sentEpoch==gate->epoch;
}

#define QP_FEEDBACK_FLASH_SECONDS 0.120
typedef struct {
    int acknowledgedDown;
    double flashUntil;
    uint64_t generation;
} QPButtonFeedback;

/* Returns 1 exactly once for each acknowledged rising edge, including a repeat
 * arriving before the preceding confirmation flash has finished. */
static inline int qp_feedback_acknowledge(QPButtonFeedback *feedback, int down, double now) {
    down=!!down;
    int rising=down && !feedback->acknowledgedDown;
    feedback->acknowledgedDown=down;
    if(rising) {
        feedback->flashUntil=now+QP_FEEDBACK_FLASH_SECONDS;
        feedback->generation++;
    }
    return rising;
}
static inline int qp_feedback_visible(const QPButtonFeedback *feedback, double now) {
    return feedback->acknowledgedDown || now<feedback->flashUntil;
}
static inline int qp_feedback_timer_is_current(const QPButtonFeedback *feedback, uint64_t generation) {
    return feedback->generation==generation;
}
static inline void qp_feedback_reset(QPButtonFeedback *feedback) {
    feedback->acknowledgedDown=0;
    feedback->flashUntil=0;
    feedback->generation++;
}
#endif
