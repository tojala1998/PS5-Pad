/* Console side of padd: the /dev/hid virtual pad plus system services. */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "system.h"

int sceUserServiceInitialize(void *params);
int sceUserServiceGetForegroundUser(int32_t *user_id);
int sceUserServiceTerminate(void);
int scePadInit(void);
int scePadOpen(int user, int type, int index, void *param);
int scePadReadState(int handle, void *data);
int scePadClose(int handle);
struct launch_param {
    uint32_t size, user_id, app_opt;
    uint64_t crash_report;
    uint32_t check_flag;
};
int sceSystemServiceLaunchApp(const char *title, const char **args, struct launch_param *param);
#define IOCTL_PAD_ADD    0xC018482AUL
#define IOCTL_PAD_REPORT 0x8018482CUL
#define IOCTL_PAD_REMOVE 0x80104850UL
#define OP_ADD    3
#define OP_REMOVE 5

#define DESCRIPTOR_BYTES  168
#define DESC_PROTOCOL_AT  0x00
#define DESC_USER_AT      0x1C
#define DESC_CLASS_AT     0x20

#define REPORT_BYTES      0xA0
#define REPORT_BUTTONS_AT 0x0C
#define REPORT_STICKS_AT  0x10
#define REPORT_L2_AT      0x14
#define REPORT_R2_AT      0x15
#define REPORT_ACTIVE_AT  0x17
#define REPORT_MOTION_AT  0x78

struct pad_request { uint32_t op_or_handle; uint32_t unused; void *in; void *out; };
struct pad_remove_request { uint8_t op; uint8_t unused[7]; uint32_t handle; uint32_t unused2; };

static int hid_fd = -1;
static int user_service_ready;
static int user_service_init(void) {
    if (user_service_ready) return 0;
    int rc = sceUserServiceInitialize(NULL);
    if (rc) return rc;
    user_service_ready = 1;
    return 0;
}

int system_foreground_user(int32_t *user_id) {
    int rc = user_service_init();
    return rc ? rc : sceUserServiceGetForegroundUser(user_id);
}

int pad_add(int32_t user_id, int32_t *handle) {
    if (hid_fd < 0 && (hid_fd = open("/dev/hid", O_RDWR)) < 0) return errno;
    uint8_t descriptor[DESCRIPTOR_BYTES] = {0};
    descriptor[DESC_PROTOCOL_AT] = 3;
    memcpy(descriptor + DESC_USER_AT, &user_id, sizeof user_id);
    descriptor[DESC_CLASS_AT] = 1;
    struct pad_request request = {OP_ADD, 0, descriptor, handle};
    *handle = -1;
    return ioctl(hid_fd, IOCTL_PAD_ADD, &request) ? errno : 0;
}

int pad_report(int32_t handle, const struct pmcp_state *state) {
    uint8_t report[REPORT_BYTES] = {0};
    const float quaternion_w = 1.0f;
    memcpy(report + REPORT_BUTTONS_AT, &state->buttons, sizeof state->buttons);
    report[REPORT_STICKS_AT + 0] = state->lx;
    report[REPORT_STICKS_AT + 1] = state->ly;
    report[REPORT_STICKS_AT + 2] = state->rx;
    report[REPORT_STICKS_AT + 3] = state->ry;
    report[REPORT_L2_AT] = state->l2;
    report[REPORT_R2_AT] = state->r2;
    report[REPORT_ACTIVE_AT] = 1;
    memcpy(report + REPORT_MOTION_AT + 12, &quaternion_w, sizeof quaternion_w);
    /* Touch points have no known place in this report yet (PMCP_FLAG_TOUCH_UNMAPPED). */
    struct pad_request request = {(uint32_t)handle, 0, report, NULL};
    return ioctl(hid_fd, IOCTL_PAD_REPORT, &request) ? errno : 0;
}

int pad_remove(int32_t handle) {
    struct pad_remove_request request = {.op = OP_REMOVE, .handle = (uint32_t)handle};
    return ioctl(hid_fd, IOCTL_PAD_REMOVE, &request) ? errno : 0;
}

/* A snapshot of the standard port, taken ONLY when QuietPad's own pad is absent.
 * No input is injected and no physical controller is closed or reassigned here.
 * The PS5 PadData connected byte is offset 76 (ps5-payload-dev/SDL PS5_PadData).
 * A failed query remains unknown; creating a virtual pad is not proof of assignment. */
int system_controller_connected(int32_t user_id, int32_t *connected) {
    static int initialized;
    *connected = -1;
    if (!initialized) {
        int rc = scePadInit();
        if (rc) return rc;
        initialized = 1;
    }
    int handle = scePadOpen(user_id, 0, 0, NULL);
    if (handle < 0) return handle;
    uint64_t data[128] = {0};
    /* Allow hotplug removal to propagate before sampling. */
    usleep(180000);
    int rc = scePadReadState(handle, data);
    if (!rc) {
        unsigned value = ((uint8_t *)data)[76];
        if (value > 1) rc = EPROTO;
        else *connected = (int32_t)value;
    }
    scePadClose(handle);
    return rc;
}

int system_vlc_installed(void) {
    FILE *file = fopen("/user/app/PPSA85300/sce_sys/param.json", "rb");
    if (!file) return 0;
    fclose(file); return 1;
}

int system_kodi_installed(void) {
    FILE *file = fopen("/user/app/PPSA99420/sce_sys/param.json", "rb");
    if (!file) return 0;
    fclose(file); return 1;
}

static int launch_title(const char *title) {
    int32_t user;
    int rc = system_foreground_user(&user);
    if (rc) return rc;
    struct launch_param param = {sizeof param, (uint32_t)user, 0, 0, 0};
    /* Normal launch only: no forced close, license bypass, or update-check flags. */
    rc = sceSystemServiceLaunchApp(title, NULL, &param);
    return rc < 0 ? rc : 0;
}
int system_launch_vlc(void) { return system_vlc_installed() ? launch_title("PPSA85300") : ENOENT; }
int system_launch_kodi(void) { return system_kodi_installed() ? launch_title("PPSA99420") : ENOENT; }

/* LncUtil calls fail with 0x80940004 until the client is initialised. */
/* ShellCore orderly power-off, type 2; API signature/value verified in
 * StonedModder/PS5-SystemStateManager commit 414b905 (src + include).
 * No direct reboot syscall or fallback with different shutdown semantics. */
int sceShellCoreUtilRequestShutdown(int type);
int system_power_off(void) { return sceShellCoreUtilRequestShutdown(2); }

void system_shutdown(void) {
    if (hid_fd >= 0) close(hid_fd);
    hid_fd = -1;
    if (user_service_ready) sceUserServiceTerminate();
    user_service_ready = 0;
}

/* Read-only title/focus queries. The focused-status buffer is deliberately 256
 * bytes: public bindings disagree on 16 vs 64 bytes. On 13.60 the app id is the
 * first u32 (the next u32 is status, not the high half of a 64-bit id).
 * No focus setter, launch, suspend or controller operation is used here. */
int sceLncUtilInitialize(void);
int sceSystemServiceGetAppId(const char *title);
int sceSystemServiceGetAppFocusedAppStatus(void *status);
int sceLncUtilGetAppTitleId(uint32_t app,char *title);
void system_app_state(struct qp_app_state *out) {
    static int initialized;
    out->flags=0;out->focused_app=-1;out->kodi_app=-1;memset(out->focused_title,0,sizeof out->focused_title);
    if(!initialized) {int rc=sceLncUtilInitialize();if(rc){out->status=rc;return;}initialized=1;}
    int kodi=sceSystemServiceGetAppId("PPSA99420");
    if(kodi>=0 || kodi==-1) {out->flags|=QP_APP_RUNNING_KNOWN;out->kodi_app=kodi;if(kodi>=0)out->flags|=QP_APP_KODI_RUNNING;}
    uint32_t focus[64]={0};int rc=sceSystemServiceGetAppFocusedAppStatus(focus);
    out->status=rc;
    if((uint32_t)rc==0x80A10009u) {out->flags|=QP_APP_FOCUS_KNOWN;out->status=0;return;}
    if(rc)return;
    if(!focus[0] || focus[0]>0x7fffffffu) {out->status=EPROTO;return;}
    char title[256]={0};rc=sceLncUtilGetAppTitleId(focus[0],title);
    if(rc){out->status=rc;return;}
    for(int i=0;i<9;i++) if(!((title[i]>='A'&&title[i]<='Z')||(title[i]>='0'&&title[i]<='9'))) {out->status=EPROTO;return;}
    if(title[9]) {out->status=EPROTO;return;}
    out->focused_app=(int32_t)focus[0];out->flags|=QP_APP_FOCUS_KNOWN;
    memcpy(out->focused_title,title,9);
    if(!strcmp(title,"PPSA99420") && kodi==(int)focus[0]) out->flags|=QP_APP_KODI_FOCUSED;
}
