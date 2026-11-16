/* SPDX-License-Identifier: GPL-3.0-only
 * Isolated uhnmeyker keyboard experiment. No input/device creation at startup.
 * No application, controller, mouse, settings, security or ShellUI operations.
 */
#include "backend.h"
#include "ascii.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#ifndef PROBE_PORT
#define PROBE_PORT 9306
#endif
#ifndef PROBE_LIFETIME_MS
#define PROBE_LIFETIME_MS 300000
#endif
#ifndef PROBE_IDLE_MS
#define PROBE_IDLE_MS 5000
#endif
#define MAX_TEXT 128
#define MAX_LINE (2*MAX_TEXT+8)
#define PRESS_MS 40
#define RELEASE_MS 40
#define SETTLE_MS 150
static volatile sig_atomic_t stopping;
static int opened;
static uint32_t firmware;
static int64_t expires;

static int64_t now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec*1000+ts.tv_nsec/1000000;
}
static void sleep_ms(int ms) {
    struct timespec ts = {ms/1000, (ms%1000)*1000000L};
    while (nanosleep(&ts, &ts) && errno == EINTR && !stopping) {}
}
static void stop_signal(int signal_number) { (void)signal_number; stopping = 1; }
static int cleanup(void) {
    int rc = opened ? backend_close() : 0;
    opened = 0; return rc;
}
static int disconnected(int fd) {
    char c; ssize_t n = recv(fd, &c, 1, MSG_PEEK | MSG_DONTWAIT);
    return n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR);
}
static int send_all(int fd, const char *s) {
    size_t left = strlen(s); int64_t deadline = now_ms()+500;
    while (left && !stopping) {
        int remaining = (int)(deadline-now_ms()); if (remaining <= 0) return -1;
        struct pollfd p = {fd, POLLOUT, 0};
        if (poll(&p, 1, remaining) <= 0) return -1;
        ssize_t n = send(fd, s, left, MSG_DONTWAIT);
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (n <= 0) return -1;
        s += n; left -= (size_t)n;
    }
    return left ? -1 : 0;
}
static int answer(int fd, int rc, const char *action, unsigned count) {
    char line[300];
    snprintf(line, sizeof line,
        "{\"ok\":%s,\"action\":\"%s\",\"rc\":%d,\"count\":%u,\"keyboard_open\":%s}\n",
        rc ? "false" : "true", action, rc, count, opened ? "true" : "false");
    return send_all(fd, line);
}
static int status(int fd) {
    char line[500];
    snprintf(line, sizeof line,
        "{\"service\":\"uhnmeyker-keyboard-probe\",\"version\":\"0.1.0\","
        "\"firmware_hex\":\"0x%08x\",\"keyboard_open\":%s,\"keyboard_detection\":false,"
        "\"supported_input\":\"experimental\",\"input_validation\":\"unverified-on-this-console\",\"layout\":\"US-ASCII\","
        "\"idle_timeout_ms\":%d,\"total_timeout_ms\":%d,\"remaining_ms\":%lld}\n", firmware, opened ? "true" : "false", PROBE_IDLE_MS, PROBE_LIFETIME_MS,
        (long long)(expires-now_ms()));
    return send_all(fd, line);
}
static int nibble(char c) {
    if (c >= '0' && c <= '9') return c-'0';
    if (c >= 'a' && c <= 'f') return c-'a'+10;
    if (c >= 'A' && c <= 'F') return c-'A'+10;
    return -1;
}
static int press(int fd, uint8_t mod, uint8_t key) {
    if (stopping || now_ms() >= expires || disconnected(fd)) return -ECANCELED;
    int rc = backend_report(mod, key);
    if (!rc) sleep_ms(PRESS_MS);
    int release = backend_report(0, 0);
    sleep_ms(RELEASE_MS);
    return rc ? rc : release;
}
/* Returns -1 to close this client; STOP also ends the process. */
static int command(int fd, const char *line) {
    if (!strcmp(line, "STATUS")) return status(fd);
    if (!strcmp(line, "OPEN")) {
        int rc = 0;
        if (!opened) { rc = backend_open(); if (!rc) { opened = 1; sleep_ms(SETTLE_MS); } }
        return answer(fd, rc, "open", 0);
    }
    if (!strcmp(line, "CLOSE")) { int rc = cleanup(); return answer(fd, rc, "close", 0); }
    if (!strcmp(line, "QUIT")) { int rc = cleanup(); (void)answer(fd, rc, "quit", 0); return -1; }
    if (!strcmp(line, "STOP")) {
        int rc = cleanup(); (void)answer(fd, rc, "stop", 0); stopping = 1; return -1;
    }
    if (!strcmp(line, "RELEASE")) return answer(fd, opened ? backend_report(0, 0) : 0, "release", 0);
    if (!strncmp(line, "TYPE ", 5)) {
        const char *hex = line+5; size_t n = strlen(hex);
        if (!n || n%2 || n > MAX_TEXT*2) return answer(fd, -EINVAL, "invalid-text", 0);
        uint8_t mods[MAX_TEXT], keys[MAX_TEXT];
        for (size_t i=0; i<n/2; i++) {
            int hi=nibble(hex[i*2]), lo=nibble(hex[i*2+1]);
            if (hi<0 || lo<0 || !ascii_key((uint8_t)((hi<<4)|lo), &mods[i], &keys[i]))
                return answer(fd, -EINVAL, "invalid-text", 0);
        }
        if (!opened) return answer(fd, -ENODEV, "type", 0);
        unsigned count=0; int rc=0;
        for (; count<n/2; count++) if ((rc=press(fd, mods[count], keys[count]))) break;
        if (rc) (void)cleanup();
        return answer(fd, rc, "type", count);
    }
    if (!strncmp(line, "KEY ", 4)) {
        uint8_t key = !strcmp(line+4,"BACKSPACE") ? 42 : !strcmp(line+4,"ENTER") ? 40 :
                      !strcmp(line+4,"ESCAPE") ? 41 : 0;
        if (!key) return answer(fd, -EINVAL, "invalid-key", 0);
        int rc = opened ? press(fd, 0, key) : -ENODEV;
        if (rc && opened) (void)cleanup();
        return answer(fd, rc, "key", rc ? 0 : 1);
    }
    return answer(fd, -EINVAL, "unknown-command", 0);
}
static void serve(int fd) {
    if (status(fd)) return;
    char line[MAX_LINE]; size_t used=0;
    int64_t deadline=now_ms()+PROBE_IDLE_MS;
    while (!stopping && now_ms()<expires) {
        int wait=(int)(deadline-now_ms()); if (wait<=0) break;
        if (wait>250) wait=250;
        struct pollfd p={fd,POLLIN,0}; int polled=poll(&p,1,wait);
        if (polled<0 && errno==EINTR) continue;
        if (polled<0) break;
        if (!polled) continue;
        char c; ssize_t n=recv(fd,&c,1,MSG_DONTWAIT);
        if (n<0 && (errno==EAGAIN || errno==EINTR)) continue;
        if (n<=0) break;
        /* A slow or unfinished line does not extend the deadline. */
        if (c=='\n') {
            line[used]=0;
            if (command(fd,line)) break;
            used=0; deadline=now_ms()+PROBE_IDLE_MS;
        } else if (c=='\r') {
            (void)answer(fd,-EINVAL,"invalid-line",0); break;
        } else if ((unsigned char)c<32 || (unsigned char)c>126 || used+1>=sizeof line) {
            (void)answer(fd,-EINVAL,"invalid-line",0); break;
        } else line[used++]=c;
    }
    (void)cleanup();
}
int main(int argc, char **argv) {
    (void)argc; (void)argv;
    signal(SIGPIPE,SIG_IGN); signal(SIGINT,stop_signal); signal(SIGTERM,stop_signal);
    firmware=backend_firmware(); expires=now_ms()+PROBE_LIFETIME_MS;
    int listener=socket(AF_INET,SOCK_STREAM,0); if (listener<0) return 1;
    int yes=1; setsockopt(listener,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof yes);
    struct sockaddr_in addr={0}; addr.sin_family=AF_INET; addr.sin_port=htons(PROBE_PORT);
#ifdef PROBE_HOST_TEST
    addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
#else
    addr.sin_addr.s_addr=htonl(INADDR_ANY);
#endif
    if (bind(listener,(struct sockaddr *)&addr,sizeof addr) || listen(listener,1)) { close(listener); return 2; }
    while (!stopping && now_ms()<expires) {
        struct pollfd p={listener,POLLIN,0}; int rc=poll(&p,1,250);
        if (rc<=0) continue;
        int fd=accept(listener,NULL,NULL); if (fd<0) continue;
        serve(fd); close(fd);
    }
    (void)cleanup(); close(listener); return 0;
}
