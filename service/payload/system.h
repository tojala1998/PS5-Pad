/* What padd needs from the console. Two implementations:
 *   system_ps5.c  - the real /dev/hid pad and system services (docs/vpad-abi.md)
 *   system_host.c - a recording stub, so the daemon logic can be tested on the Mac
 */
#ifndef PS5MCP_SYSTEM_H
#define PS5MCP_SYSTEM_H

#include <stddef.h>
#include <stdint.h>

#include "protocol.h"

/* Returns 0 and the foreground user id, or an SCE error code. */
int system_foreground_user(int32_t *user_id);
/* Each returns 0 on success, an errno (>0) or an SCE error code (<0). */
int pad_add(int32_t user_id, int32_t *handle);
int pad_report(int32_t handle, const struct pmcp_state *state);
int pad_remove(int32_t handle);
int system_controller_connected(int32_t user_id, int32_t *connected);
int system_vlc_installed(void);
int system_launch_vlc(void);
int system_kodi_installed(void);
int system_launch_kodi(void);

void system_shutdown(void);

#endif
