#ifndef QP_HELPER_UPDATE_H
#define QP_HELPER_UPDATE_H
#include <stdbool.h>
#include "PMCP.h"
#include "QPHelperVersion.h"
typedef enum { QP_UPDATE_NONE, QP_UPDATE_DETACH, QP_UPDATE_STOP,
    QP_UPDATE_EOF, QP_UPDATE_ABSENCE, QP_UPDATE_FAILED } QPHelperUpdate;
/* Each app uses its tested, bundled helper. A different version is a
 * replacement candidate in either direction, not an assumed-compatible peer. */
static inline bool qp_helper_needs_replacement(uint16_t version) {
    return version != QP_BUNDLED_HELPER_VERSION;
}
static inline bool qp_helper_can_update(uint16_t version,uint32_t flags) {
    /* Public 2.x helpers and future releases retain PMCP v1 management/STOP.
     * Do not require unrelated controller commands to replace a helper. */
    return qp_helper_needs_replacement(version) && version>=0x0200 && (flags&QP_CAP_CONTROL);
}
static inline QPHelperUpdate qp_helper_update_begin(uint16_t version,uint32_t flags) {
    if(!qp_helper_can_update(version,flags))return QP_UPDATE_FAILED;
    return qp_supports_disconnect(version,flags)?QP_UPDATE_DETACH:QP_UPDATE_STOP;
}
static inline bool qp_helper_update_reply(QPHelperUpdate *phase,uint8_t kind,const uint8_t *body,size_t length) {
    if(*phase==QP_UPDATE_DETACH && kind==QP_DISCONNECT_CONTROLLER && length==32 && qp_disconnect_response_valid(body)) {
        *phase=QP_UPDATE_STOP; return true;
    }
    if(*phase==QP_UPDATE_STOP && kind==QP_ACK && length==8 && !qp_u32(body) && !qp_u32(body+4)) {
        *phase=QP_UPDATE_EOF; return true;
    }
    *phase=QP_UPDATE_FAILED; return false;
}
static inline bool qp_helper_update_eof(QPHelperUpdate *phase,bool clean,bool buffered) {
    if(*phase==QP_UPDATE_EOF && clean && !buffered) { *phase=QP_UPDATE_ABSENCE; return true; }
    *phase=QP_UPDATE_FAILED; return false;
}
static inline bool qp_helper_replacement_allowed(QPHelperUpdate phase,bool connected,bool blocked,bool refused) {
    return phase==QP_UPDATE_ABSENCE && !connected && !blocked && refused;
}
#endif
