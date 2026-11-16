/* SPDX-License-Identifier: GPL-3.0-only */
#ifndef UH_PROBE_ASCII_H
#define UH_PROBE_ASCII_H
#include <stdint.h>
#include <string.h>
/* USB HID keyboard usages for the US layout. No Unicode/transliteration. */
static inline int ascii_key(uint8_t c, uint8_t *mod, uint8_t *key) {
    *mod = 0; *key = 0;
    if (c >= 'a' && c <= 'z') { *key = (uint8_t)(4+c-'a'); return 1; }
    if (c >= 'A' && c <= 'Z') { *mod = 2; *key = (uint8_t)(4+c-'A'); return 1; }
    if (c >= '1' && c <= '9') { *key = (uint8_t)(30+c-'1'); return 1; }
    if (c == '0') { *key = 39; return 1; }
    if (c == ' ') { *key = 44; return 1; }
    const char *plain = "-=[]\\;'`,./";
    const char *shift = "_+{}|:\"~<>?";
    const uint8_t codes[] = {45,46,47,48,49,51,52,53,54,55,56};
    const char *p = strchr(plain, c);
    if (p && c) { *key = codes[p-plain]; return 1; }
    p = strchr(shift, c);
    if (p && c) { *mod = 2; *key = codes[p-shift]; return 1; }
    const char *shift_digits = "!@#$%^&*()";
    p = strchr(shift_digits, c);
    if (p && c) { *mod = 2; *key = (uint8_t)(30+p-shift_digits); return 1; }
    return 0;
}
#endif
