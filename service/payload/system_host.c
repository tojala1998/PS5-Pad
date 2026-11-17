/* Host stub for padd tests: records pad activity instead of touching hardware.
 *
 * PADD_TRACE=<file> receives one JSON line per state *change* and per call, so
 * tests can assert what the console would have seen.
 * PADD_FAIL_ADD=<errno> makes pad_add fail; PADD_FAIL_ADD_USER=<user id> limits that to one user.
 * PADD_TEST_* faults below exist only in this host backend. They never enter the console ELF.
 * CONTROLLER_QUERY_ERROR: fail the other-controller query immediately.
 * READD_SETTLE_MS: return EBUSY when re-add follows successful removal too quickly.
 * FAIL_REPORT_AT / REPORT_ERROR: fail one 1-based report call (default EIO).
 * FAIL_REMOVE_COUNT / REMOVE_ERROR: fail the first N removals (-1 means always).
 * NEGATIVE_HANDLE: successful add returns -1 without creating a simulated device.
 * ENFORCE_SINGLE_PAD: reject duplicate simulated devices; TRACE_REPORTS: trace repeats too.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

#include "system.h"

static FILE *trace;
/* The last state traced per pad (padd feeds up to two), so a repeat is skipped but each pad's first report shows. */
static struct {
    int32_t handle;
    struct pmcp_state state;
} last[16];
static int lasts;
static int32_t next_handle = 1000;
static int32_t active_handle = -1;
static unsigned report_calls, remove_calls;
static uint64_t removed_ms;

static long fault_value(const char *name, long fallback) {
    const char *value = getenv(name);
    return value ? strtol(value, NULL, 0) : fallback;
}

static uint64_t monotonic_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}

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
    int result = 0;
    uint64_t now = monotonic_ms();
    long settle = fault_value("PADD_TEST_READD_SETTLE_MS", 0);
    int duplicate = active_handle >= 0;
    *handle = -1;
    if (fail && (!only || strtol(only, NULL, 0) == user_id)) result = atoi(fail);
    else if (duplicate && fault_value("PADD_TEST_ENFORCE_SINGLE_PAD", 0)) result = EBUSY;
    else if (settle > 0 && removed_ms && now - removed_ms < (uint64_t)settle) result = EBUSY;
    else if (!fault_value("PADD_TEST_NEGATIVE_HANDLE", 0)) {
        *handle = next_handle++;
        active_handle = *handle;
    }
    char line[256];
    snprintf(line, sizeof line, "{\"call\":\"pad_add\",\"user_id\":%d,\"ms\":%llu,\"result\":%d,\"handle\":%d,\"duplicate\":%s}\n",
             user_id, (unsigned long long)now, result, *handle, duplicate ? "true" : "false");
    emit(line);
    return result;
}

int pad_report(int32_t handle, const struct pmcp_state *state) {
    report_calls++;
    int result = fault_value("PADD_TEST_FAIL_REPORT_AT", 0) == (long)report_calls ?
                 (int)fault_value("PADD_TEST_REPORT_ERROR", EIO) : 0;
    struct pmcp_state copy = *state;
    copy.seq = 0;
    int i = 0;
    while (i < lasts && last[i].handle != handle) i++;
    if (!result && !fault_value("PADD_TEST_TRACE_REPORTS", 0) &&
        i < lasts && memcmp(&copy, &last[i].state, sizeof copy) == 0) return 0;
    if (i == lasts) {
        if (lasts == 16) i = lasts - 1;  /* many old handles: reuse the newest slot */
        else lasts++;
    }
    last[i].handle = handle;
    last[i].state = copy;
    char line[384];
    snprintf(line, sizeof line,
             "{\"call\":\"pad_report\",\"handle\":%d,\"buttons\":%u,\"lx\":%u,\"ly\":%u,\"rx\":%u,\"ry\":%u,"
             "\"l2\":%u,\"r2\":%u,\"ms\":%llu,\"attempt\":%u,\"result\":%d}\n", handle, state->buttons, state->lx, state->ly, state->rx, state->ry,
             state->l2, state->r2, (unsigned long long)monotonic_ms(), report_calls, result);
    emit(line);
    return result;
}

int pad_remove(int32_t handle) {
    remove_calls++;
    long count = fault_value("PADD_TEST_FAIL_REMOVE_COUNT", 0);
    int result = count < 0 || remove_calls <= (unsigned long)count ?
                 (int)fault_value("PADD_TEST_REMOVE_ERROR", EIO) : 0;
    uint64_t now = monotonic_ms();
    char line[192];
    snprintf(line, sizeof line, "{\"call\":\"pad_remove\",\"handle\":%d,\"ms\":%llu,\"attempt\":%u,\"result\":%d}\n",
             handle, (unsigned long long)now, remove_calls, result);
    emit(line);
    if (!result) {
        if (active_handle == handle) active_handle = -1;
        removed_ms = now;
    }
    return result;
}

void system_shutdown(void) {
    emit("{\"call\":\"shutdown\"}\n");
    if (trace) fclose(trace);
    trace = NULL;
}

int system_controller_connected(int32_t user_id, int32_t *connected) {
    (void)user_id;
    int result = (int)fault_value("PADD_TEST_CONTROLLER_QUERY_ERROR", 0);
    *connected = result ? -1 : 1;
    char line[160];
    snprintf(line, sizeof line, "{\"call\":\"controller_query\",\"ms\":%llu,\"result\":%d}\n",
             (unsigned long long)monotonic_ms(), result);
    emit(line);
    return result;
}
int system_vlc_installed(void) { return 1; }
int system_launch_vlc(void) { emit("{\"call\":\"launch_vlc\"}\n"); return 0; }
int system_kodi_installed(void) { return 1; }
int system_launch_kodi(void) { emit("{\"call\":\"launch_kodi\"}\n"); return 0; }

void system_app_state(struct qp_app_state *out) {
    out->flags=0;out->status=EIO;out->focused_app=out->kodi_app=-1;
    memset(out->focused_title,0,sizeof out->focused_title);
    const char *path=getenv("PADD_TEST_APP_STATE_FILE");if(!path)return;
    FILE *f=fopen(path,"r");if(!f)return;char state[32]={0};(void)fgets(state,sizeof state,f);fclose(f);
    if(!strcmp(state,"unknown"))return;
    out->status=0;out->flags=QP_APP_RUNNING_KNOWN|QP_APP_FOCUS_KNOWN;
    if(!strcmp(state,"kodi") || !strcmp(state,"home")) {out->kodi_app=123;out->flags|=QP_APP_KODI_RUNNING;}
    if(!strcmp(state,"kodi")){out->focused_app=123;out->flags|=QP_APP_KODI_FOCUSED;strcpy(out->focused_title,"PPSA99420");}
}
