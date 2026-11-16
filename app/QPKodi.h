#ifndef QP_KODI_H
#define QP_KODI_H
#include "PMCP.h"
/* PS5MC's PS5PadInput.cpp + fullscreen keyboard.xml mappings.
 * These commands are for Kodi video playback, not global Sony media events. */
static inline uint32_t qp_kodi_action(unsigned action) {
    const uint32_t masks[]={QP_DOWN,QP_LEFT,QP_OPTIONS,QP_RIGHT,QP_UP};
    return action<5?masks[action]:0;
}
#endif
