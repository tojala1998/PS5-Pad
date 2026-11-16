/* Host stub for padd tests: records pad activity instead of touching hardware.
 *
 * PADD_TRACE=<file> receives one JSON line per state *change* and per call, so
 * tests can assert what the console would have seen.
 * PADD_FAIL_ADD=<errno> makes pad_add fail; PADD_FAIL_ADD_USER=<user id> limits that to one user.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "system.h"

static FILE *trace;
/* The last state traced per pad (padd feeds up to two), so a repeat is skipped but each pad's first report shows. */
static struct {
    int32_t handle;
    struct pmcp_state state;
} last[16];
static int lasts;
static int32_t next_handle = 1000;

static void emit(const char *line) {
    if (!trace) {
        const char *path = getenv("PADD_TRACE");
        if (!path || !(trace = fopen(path, "a"))) return;
        setvbuf(trace, NULL, _IOLBF, 0);
    }
    fputs(line, trace);
}

#define FOREGROUND_USER 0x11ecf8b9

int system_foreground_user(int32_t *user_id) {
    *user_id = FOREGROUND_USER;
    return 0;
}

int pad_add(int32_t user_id, int32_t *handle) {
    const char *fail = getenv("PADD_FAIL_ADD");
    const char *only = getenv("PADD_FAIL_ADD_USER");
    char line[128];
    snprintf(line, sizeof line, "{\"call\":\"pad_add\",\"user_id\":%d}\n", user_id);
    emit(line);
    if (fail && (!only || strtol(only, NULL, 0) == user_id)) return atoi(fail);
    *handle = next_handle++;
    return 0;
}

int pad_report(int32_t handle, const struct pmcp_state *state) {
    struct pmcp_state copy = *state;
    copy.seq = 0;
    int i = 0;
    while (i < lasts && last[i].handle != handle) i++;
    if (i < lasts && memcmp(&copy, &last[i].state, sizeof copy) == 0) return 0;
    if (i == lasts) {
        if (lasts == 16) i = lasts - 1;  /* many old handles: reuse the newest slot */
        else lasts++;
    }
    last[i].handle = handle;
    last[i].state = copy;
    char line[256];
    snprintf(line, sizeof line,
             "{\"call\":\"pad_report\",\"handle\":%d,\"buttons\":%u,\"lx\":%u,\"ly\":%u,\"rx\":%u,\"ry\":%u,"
             "\"l2\":%u,\"r2\":%u}\n", handle, state->buttons, state->lx, state->ly, state->rx, state->ry,
             state->l2, state->r2);
    emit(line);
    return 0;
}

int pad_remove(int32_t handle) {
    char line[64];
    snprintf(line, sizeof line, "{\"call\":\"pad_remove\",\"handle\":%d}\n", handle);
    emit(line);
    return 0;
}

void system_shutdown(void) {
    emit("{\"call\":\"shutdown\"}\n");
    if (trace) fclose(trace);
    trace = NULL;
}

int system_controller_connected(int32_t user_id, int32_t *connected) {
    (void)user_id; *connected = 1; return 0;
}
int system_vlc_installed(void) { return 1; }
int system_launch_vlc(void) { emit("{\"call\":\"launch_vlc\"}\n"); return 0; }
int system_kodi_installed(void) { return 1; }
int system_launch_kodi(void) { emit("{\"call\":\"launch_kodi\"}\n"); return 0; }
