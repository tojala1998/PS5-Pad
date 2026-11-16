/* SPDX-License-Identifier: GPL-3.0-only */
#include "backend.h"
#include "third_party/kbm.h"
#include <ps5/kernel.h>
#include <stddef.h>
#include <errno.h>

int sceUserServiceInitialize(void *parameters);
int sceUserServiceGetForegroundUser(int32_t *user);
static ps_keyboard *keyboard;
static int user_service_ready;

uint32_t backend_firmware(void) { return kernel_get_fw_version(); }

int backend_open(void) {
    if (keyboard) return 0;
    if (!user_service_ready) {
        int rc = sceUserServiceInitialize(NULL);
        if (rc) return rc;
        user_service_ready = 1;
    }
    int32_t user = -1;
    int rc = sceUserServiceGetForegroundUser(&user);
    if (rc) return rc;
    if (user < 0) return -ENOENT;
    return ps_keyboard_open((uint32_t)user, &keyboard);
}

int backend_report(uint8_t modifiers, uint8_t key) {
    if (!keyboard) return -ENODEV;
    return ps_keyboard_send(keyboard, modifiers, key ? &key : NULL, key ? 1 : 0);
}

int backend_close(void) {
    int rc = ps_keyboard_close(keyboard);
    keyboard = NULL;
    return rc;
}
