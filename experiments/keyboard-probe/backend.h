/* SPDX-License-Identifier: GPL-3.0-only */
#ifndef UH_PROBE_BACKEND_H
#define UH_PROBE_BACKEND_H
#include <stdint.h>
uint32_t backend_firmware(void);
int backend_open(void);
int backend_report(uint8_t modifiers, uint8_t key);
int backend_close(void);
#endif
