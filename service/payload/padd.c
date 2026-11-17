/* padd: long-running virtual-pad daemon for ps5-mcp.
 *
 * - One instance: the listening port is the lock.
 * - This variant creates one virtual pad for the foreground user.
 * - One client at a time; each STATE carries the whole pad state and is ACKed by seq.
 * - Safety: no STATE for watchdog_ms, or a disconnect, forces neutral. A client
 *   silent for idle_ms is dropped. Those network events never remove the pad.
 *   Explicit QP_DISCONNECT_CONTROLLER removes our pad but keeps the service alive;
 *   SHUTDOWN, SIGTERM/SIGINT and normal exit also remove it.
 * - Logs JSON lines to <log_dir>/padd-XXXXXX.
 */
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "protocol.h"
#include "system.h"
#include "owner_monitor.h"
#include "text_input.h"
#include "live_keyboard.h"

#define PADD_VERSION 0x0208
#define PAD_DETACH_SETTLE_MS 180u
#define PAD_NEUTRAL_WARMUP_MS 200u

struct config {
    int port;
    const char *log_dir;
    unsigned tick_ms;
    unsigned watchdog_ms;
    unsigned idle_ms;
};

struct daemon {
    int power_off_requested;
    struct config cfg;
    int listen_fd, client_fd;
    uint8_t rx[PMCP_HEADER_BYTES + PMCP_MAX_PAYLOAD];
    size_t rx_len;
    struct pad {
        int32_t user_id, handle;
        int ready;
        struct pmcp_state state;
    } pad;
    struct owner_monitor ownership;
    struct text_job text;
    struct live_keyboard keyboard;
    int profile_assigned, yielded, handoff_pending;
    uint64_t last_handoff_retry;
    int add_status;
    int32_t other_connected, other_status, user_status;
    uint32_t initialization_count;
    uint64_t started_ms, last_state_ms, last_rx_ms, last_report_ms, last_detach_ms;
    uint64_t reports_sent;
    uint32_t report_failures, neutral_events;
    int last_report_status;
    int running;
};

static volatile sig_atomic_t stop_requested;

static void on_signal(int sig) {
    (void)sig;
    stop_requested = 1;
}

static uint64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}

static void log_event(const char *event, const char *fmt, ...) {
    printf("{\"event\":\"%s\"", event);
    if (fmt && *fmt) {
        va_list args;
        va_start(args, fmt);
        putchar(',');
        vprintf(fmt, args);
        va_end(args);
    }
    puts("}");
    fflush(stdout);
    fsync(STDOUT_FILENO);
}

static void neutral(struct pmcp_state *state) {
    memset(state, 0, sizeof *state);
    state->lx = state->ly = state->rx = state->ry = 0x80;
}

static int is_neutral(const struct pmcp_state *state) {
    struct pmcp_state n, copy = *state;
    neutral(&n);
    copy.seq = 0;
    return memcmp(&copy, &n, sizeof n) == 0;
}

static int send_message(struct daemon *d, uint8_t type, const void *payload, uint16_t length) {
    uint8_t buffer[PMCP_HEADER_BYTES + PMCP_MAX_PAYLOAD];
    if (d->client_fd < 0 || length > PMCP_MAX_PAYLOAD) return -1;
    memcpy(buffer, PMCP_MAGIC, 4);
    buffer[4] = PMCP_VERSION;
    buffer[5] = type;
    buffer[6] = (uint8_t)(length & 0xff);
    buffer[7] = (uint8_t)(length >> 8);
    if (length) memcpy(buffer + PMCP_HEADER_BYTES, payload, length);
    size_t total = PMCP_HEADER_BYTES + length, sent = 0;
    while (sent < total) {
        ssize_t n = send(d->client_fd, buffer + sent, total - sent, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        sent += (size_t)n;
    }
    return 0;
}

static void send_error_fd(int fd, uint32_t code, const char *message) {
    uint8_t buffer[PMCP_HEADER_BYTES + 4 + 64];
    size_t length = 4 + strnlen(message, 64);
    memcpy(buffer, PMCP_MAGIC, 4);
    buffer[4] = PMCP_VERSION;
    buffer[5] = PMCP_ERROR;
    buffer[6] = (uint8_t)length;
    buffer[7] = 0;
    memcpy(buffer + 8, &code, 4);
    memcpy(buffer + 12, message, length - 4);
    (void)!send(fd, buffer, PMCP_HEADER_BYTES + length, 0);
}

static void send_error(struct daemon *d, uint32_t code, const char *message) {
    if (d->client_fd >= 0) send_error_fd(d->client_fd, code, message);
}

static int report_owned(struct daemon *d, struct pad *pad) {
    if (pad->handle < 0) return PMCP_ERR_NO_PAD;
    int status = pad_report(pad->handle, &pad->state);
    d->reports_sent++;
    d->last_report_ms = now_ms();
    if (status) {
        d->report_failures++;
        if (status != d->last_report_status) log_event("report_failed", "\"status\":%d", status);
    }
    d->last_report_status = status;
    return status;
}

static int report(struct daemon *d, struct pad *pad) {
    if (!pad->ready) return PMCP_ERR_NO_PAD;
    return report_owned(d, pad);
}

static int apply(struct daemon *d) { return report(d, &d->pad); }

static void force_neutral(struct daemon *d, const char *reason) {
    if (is_neutral(&d->pad.state)) return;
    neutral(&d->pad.state);
    d->neutral_events++;
    log_event("neutral", "\"reason\":\"%s\"", reason);
    apply(d);
}

static void drop_client(struct daemon *d, const char *reason) {
    if (d->client_fd < 0) return;
    text_cancel(&d->text,ECANCELED);
    live_cancel(&d->keyboard,ECANCELED); d->keyboard.busy=0;
    close(d->client_fd);
    d->client_fd = -1;
    d->rx_len = 0;
    log_event("client_closed", "\"reason\":\"%s\"", reason);
    force_neutral(d, "disconnect");
}

static uint32_t flags(const struct daemon *d) {
    return (d->pad.ready ? PMCP_FLAG_PAD_READY : 0) | PMCP_FLAG_TOUCH_UNMAPPED |
        QP_FLAG_CONTROLS | QP_FLAG_DISCONNECT_CONTROLLER | QP_FLAG_TEXT_INPUT | QP_FLAG_LIVE_KEYBOARD | QP_FLAG_APP_STATE | QP_FLAG_POWER_OFF |
        (d->ownership.enabled ? QP_FLAG_OWNERSHIP : 0) |
        (d->ownership.enabled && d->ownership.synced ? QP_FLAG_MONITOR_READY : 0) |
        (d->profile_assigned ? QP_FLAG_PROFILE_ASSIGNED : 0) |
        (d->ownership.enabled && d->pad.ready && !d->profile_assigned ? QP_FLAG_PROFILE_PENDING : 0) |
        (d->yielded ? QP_FLAG_YIELDED : 0);
}

static void controller_status(struct daemon *d, uint8_t type, int status) {
    int32_t user;
    d->user_status = system_foreground_user(&user);
    struct qp_status reply = {status, d->user_status, d->other_connected, d->other_status,
        d->pad.handle, flags(d), (uint32_t)(system_vlc_installed() | (system_kodi_installed()<<1)), d->initialization_count};
    send_message(d, type, &reply, sizeof reply);
}

static int initialize_controller(struct daemon *d) {
    if(d->text.active || d->text.cleanup) return EBUSY;
    if(d->ownership.enabled && !d->ownership.synced) return EAGAIN;
    d->profile_assigned=0; d->yielded=0;
    int32_t user;
    int rc = system_foreground_user(&user);
    d->user_status = rc;
    if (rc) return rc;
    force_neutral(d, "initialize");
    if (d->pad.handle >= 0) {
        rc = pad_remove(d->pad.handle);
        if (rc) {
            d->pad.ready = 0;
            return rc; /* Never create a duplicate if removal failed. */
        }
        d->pad.ready = 0; d->pad.handle = -1;
        d->last_detach_ms = now_ms();
    }
    d->pad.ready = 0; d->pad.handle = -1;
    /* Removal is asynchronous, including cleanup of a failed initialization.
     * The gap must not depend on the optional libScePad snapshot succeeding. */
    while (d->last_detach_ms && now_ms() - d->last_detach_ms < PAD_DETACH_SETTLE_MS) usleep(1000);
    d->other_status = system_controller_connected(user, &d->other_connected);
    d->pad.user_id = user;
    neutral(&d->pad.state);
    d->add_status = pad_add(user, &d->pad.handle);
    if (!d->add_status && d->pad.handle < 0) d->add_status = EIO;
    d->pad.ready = !d->add_status && d->pad.handle >= 0;
    d->initialization_count++;
    /* Feed neutral reports through attachment before acknowledging success.
     * Accepted reports still do not prove that the TV's user picker assigned
     * this controller: the person must confirm that on the console. */
    if (d->pad.ready) {
        const uint64_t attached = now_ms();
        do {
            rc = apply(d);
            if (rc) break;
            usleep(d->cfg.tick_ms * 1000u);
        } while (now_ms() - attached < PAD_NEUTRAL_WARMUP_MS);
        if (rc) {
            d->add_status = rc;
            d->pad.ready = 0;
            int cleanup = pad_remove(d->pad.handle);
            log_event("initialize_cleanup", "\"status\":%d,\"handle\":%d", cleanup, d->pad.handle);
            /* Keep a failed-removal handle for the next initialize or exit. */
            if (!cleanup) {
                d->pad.handle = -1;
                d->last_detach_ms = now_ms();
            }
        }
    }
    d->last_state_ms = now_ms();
    log_event("initialized", "\"status\":%d,\"other_connected\":%d,\"other_status\":%d,\"handle\":%d",
        d->add_status, d->other_connected, d->other_status, d->pad.handle);
    return d->add_status;
}

/* Session end must be explicit. EOF, heartbeat loss and phone sleep only
 * neutralize input, because they cannot distinguish sleep from an ended session. */
static int disconnect_controller(struct daemon *d) {
    text_cancel(&d->text,ECANCELED);
    live_cancel(&d->keyboard,ECANCELED);
    neutral(&d->pad.state);
    d->last_state_ms = now_ms();
    d->pad.ready = 0; d->profile_assigned=0;
    if (d->pad.handle < 0) return 0;
    /* A prior failed removal retains ownership but not readiness. Retry neutral
     * on that same handle before removing it; never look up or remove other pads. */
    d->neutral_events++;
    int neutral_status = report_owned(d, &d->pad);
    int handle = d->pad.handle;
    int rc = pad_remove(handle);
    if (!rc) {
        d->pad.handle = -1;
        d->last_detach_ms = now_ms();
    }
    log_event("controller_disconnected", "\"status\":%d,\"neutral_status\":%d,\"handle\":%d",
        rc, neutral_status, handle);
    return rc;
}

static void yield_controller(struct daemon *d,const char *reason) {
    if(d->pad.handle<0) return;
    d->yielded=1;
    d->handoff_pending=disconnect_controller(d)!=0;
    d->last_handoff_retry=now_ms();
    log_event("controller_yielded","\"removal_pending\":%d",d->handoff_pending);
    send_error(d,8,reason); drop_client(d,"controller_yielded");
}
static void ownership_event(void *context,struct owner_event e) {
    struct daemon *d=context;
    if(d->pad.handle<0) return;
    if(e.device==(uint32_t)d->pad.handle) {
        if(e.kind==OWNER_CHANGE) {
            if(e.user && e.user!=UINT32_MAX) {
                d->pad.user_id=(int32_t)e.user; d->profile_assigned=1;
                log_event("profile_assigned","\"handle\":%d",d->pad.handle);
            } else yield_controller(d,"Profile released. Turn on the controller to choose a profile.");
        } else if(e.kind==OWNER_REMOVE) {
            d->pad.handle=-1; d->pad.ready=0; d->profile_assigned=0; d->yielded=1;
            send_error(d,8,"Controller turned off. Turn it on to reconnect."); drop_client(d,"system_removed_controller");
        }
    } else if(e.kind==OWNER_CHANGE && e.controller && e.user && e.user!=UINT32_MAX && e.user==(uint32_t)d->pad.user_id) {
        yield_controller(d,"Physical controller took control. Turn on PS5 Pad to switch back.");
    }
}

static void handle_message(struct daemon *d, uint8_t type, const uint8_t *payload, uint16_t length) {
    switch (type) {
    case QP_POWER_OFF: {
        if(length!=4 || memcmp(payload,"OFF!",4)) {send_error(d,PMCP_ERR_BAD_LENGTH,"Power off requires explicit confirmation");return;}
        int32_t result=d->power_off_requested?EALREADY:system_power_off();
        if(!result)d->power_off_requested=1;
        log_event("power_off_requested","\"status\":%d",result);
        send_message(d,type,&result,sizeof result);return;
    }
    case QP_APP_STATE: {
        if(length!=4){send_error(d,PMCP_ERR_BAD_LENGTH,"APP_STATE requires a token");return;}
        struct qp_app_state state={0};memcpy(&state.token,payload,4);
        system_app_state(&state);send_message(d,type,&state,sizeof state);return;
    }
    case QP_KEYBOARD_LEASE:
        if(length==1 && payload[0]==1) {live_cancel(&d->keyboard,ECANCELED);return;}
        if(length) {send_error(d,PMCP_ERR_BAD_LENGTH,"lease must be empty");return;}
        if(d->keyboard.opened && !d->keyboard.cleanup) d->keyboard.lease=now_ms()+1800;
        return;
    case QP_LIVE_KEYBOARD: {
        int32_t status=(d->ownership.enabled && !d->profile_assigned)?EACCES:
            ((d->text.active||d->text.cleanup)?EBUSY:live_request(&d->keyboard,d->pad.user_id,payload,length,now_ms()));
        if(status) {int32_t result[2]={status,d->keyboard.opened};send_message(d,type,result,sizeof result);}
        return;
    }
    case QP_TYPE_TEXT: {
        int32_t status=(d->ownership.enabled && !d->profile_assigned)?EACCES:
            ((d->keyboard.opened||d->keyboard.cleanup)?EBUSY:text_begin(&d->text,d->pad.user_id,payload,length,now_ms()));
        if(status) {int32_t result[2]={status,0};send_message(d,type,result,sizeof result);}
        return;
    }
    case QP_STATUS:
    case QP_INITIALIZE:
        if (length) { send_error(d, PMCP_ERR_BAD_LENGTH, "request must be empty"); return; }
        controller_status(d, type, type == QP_INITIALIZE ? initialize_controller(d) : 0);
        return;
    case QP_DISCONNECT_CONTROLLER:
        if (length) { send_error(d, PMCP_ERR_BAD_LENGTH, "request must be empty"); return; }
        controller_status(d, type, disconnect_controller(d));
        return;
    case QP_VLC:
    case QP_KODI: {
        if (length) { send_error(d, PMCP_ERR_BAD_LENGTH, "request must be empty"); return; }
        if(d->ownership.enabled && !d->profile_assigned) {
            int32_t denied=EACCES; send_message(d,type,&denied,sizeof denied); return;
        }
        int32_t result = type == QP_VLC ? system_launch_vlc() : system_launch_kodi();
        log_event(type == QP_VLC ? "launch_vlc" : "launch_kodi", "\"status\":%d", result);
        send_message(d, type, &result, sizeof result);
        return;
    }
    case PMCP_STATE: {
        if (length != sizeof(struct pmcp_state)) {
            send_error(d, PMCP_ERR_BAD_LENGTH, "STATE must be 28 bytes");
            return;
        }
        struct pad *pad = &d->pad;
        memcpy(&pad->state, payload, sizeof pad->state);
        if(d->ownership.enabled && !d->profile_assigned) {
            /* Only profile-picker navigation is allowed before assignment. */
            pad->state.buttons &= 0x60F0u; /* D-pad, Cross and Circle */
            pad->state.lx=pad->state.ly=pad->state.rx=pad->state.ry=128;
            pad->state.l2=pad->state.r2=0;
        }
        d->last_state_ms = now_ms();
        struct pmcp_ack ack = {pad->state.seq, apply(d)};
        send_message(d, PMCP_ACK, &ack, sizeof ack);
        return;
    }
    case PMCP_PING: {
        struct pmcp_pong pong = {0};
        if (length >= 4) memcpy(&pong.token, payload, 4);
        pong.protocol = PMCP_VERSION;
        pong.payload_version = PADD_VERSION;
        pong.uptime_ms = now_ms() - d->started_ms;
        pong.pad_handle = d->pad.handle;
        pong.flags = flags(d);
        pong.reports_sent = d->reports_sent;
        pong.report_failures = d->report_failures;
        pong.neutral_events = d->neutral_events;
        send_message(d, PMCP_PING, &pong, sizeof pong);
        return;
    }
    case PMCP_GET_STATE:
        send_message(d, PMCP_STATE, &d->pad.state, sizeof d->pad.state);
        return;
    case PMCP_SHUTDOWN: {
        struct pmcp_ack ack = {0, 0};
        log_event("shutdown_requested", "");
        send_message(d, PMCP_ACK, &ack, sizeof ack);
        d->running = 0;
        return;
    }
    default:
        send_error(d, PMCP_ERR_UNKNOWN_TYPE, "unknown message type");
    }
}

static void read_client(struct daemon *d) {
    ssize_t n = recv(d->client_fd, d->rx + d->rx_len, sizeof d->rx - d->rx_len, 0);
    if (n < 0 && (errno == EINTR || errno == EAGAIN)) return;
    if (n <= 0) {
        drop_client(d, n == 0 ? "eof" : "recv_error");
        return;
    }
    d->rx_len += (size_t)n;
    d->last_rx_ms = now_ms();
    while (d->running && d->client_fd >= 0 && d->rx_len >= PMCP_HEADER_BYTES) {
        if (memcmp(d->rx, PMCP_MAGIC, 4) != 0) {
            send_error(d, PMCP_ERR_BAD_MAGIC, "bad magic");
            drop_client(d, "bad_magic");
            return;
        }
        if (d->rx[4] != PMCP_VERSION) {
            send_error(d, PMCP_ERR_BAD_VERSION, "unsupported protocol version");
            drop_client(d, "bad_version");
            return;
        }
        uint16_t length = (uint16_t)(d->rx[6] | (d->rx[7] << 8));
        if (length > PMCP_MAX_PAYLOAD) {
            send_error(d, PMCP_ERR_BAD_LENGTH, "payload too long");
            drop_client(d, "bad_length");
            return;
        }
        size_t total = PMCP_HEADER_BYTES + length;
        if (d->rx_len < total) return;
        handle_message(d, d->rx[5], d->rx + PMCP_HEADER_BYTES, length);
        if (d->client_fd < 0) return;
        memmove(d->rx, d->rx + total, d->rx_len - total);
        d->rx_len -= total;
    }
}

static void accept_client(struct daemon *d) {
    int fd = accept(d->listen_fd, NULL, NULL);
    if (fd < 0) return;
    if (d->client_fd >= 0) {
        send_error_fd(fd, PMCP_ERR_BUSY, "another client is connected");
        close(fd);
        log_event("client_rejected", "\"reason\":\"busy\"");
        return;
    }
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
#ifdef SO_NOSIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
    d->client_fd = fd;
    d->rx_len = 0;
    d->last_rx_ms = d->last_state_ms = now_ms();
    log_event("client_connected", "");
    struct pmcp_hello hello = {PMCP_VERSION, PADD_VERSION, d->pad.handle, -1, flags(d),
                               (uint32_t)d->add_status};
    send_message(d, PMCP_HELLO, &hello, sizeof hello);
}

static int open_log(const char *dir) {
    char path[256];
    if (mkdir(dir, 0755) != 0 && errno != EEXIST) return -1;
    snprintf(path, sizeof path, "%s/padd-XXXXXX", dir);
    int fd = mkstemp(path);
    if (fd < 0 || dup2(fd, STDOUT_FILENO) < 0) return -1;
    close(fd);
    return 0;
}

static void parse_args(struct config *cfg, int argc, char **argv) {
    for (int i = 1; i + 1 < argc; i += 2) {
        if (!strcmp(argv[i], "--port")) cfg->port = atoi(argv[i + 1]);
        else if (!strcmp(argv[i], "--log-dir")) cfg->log_dir = argv[i + 1];
        else if (!strcmp(argv[i], "--tick-ms")) cfg->tick_ms = (unsigned)atoi(argv[i + 1]);
        else if (!strcmp(argv[i], "--watchdog-ms")) cfg->watchdog_ms = (unsigned)atoi(argv[i + 1]);
        else if (!strcmp(argv[i], "--idle-ms")) cfg->idle_ms = (unsigned)atoi(argv[i + 1]);
    }
}

int main(int argc, char **argv) {
    static struct daemon d;
    d.cfg = (struct config){PMCP_PORT, "/data/ps5-mcp/logs", 8, 1000, 5000};
    parse_args(&d.cfg, argc, argv);
    d.listen_fd = d.client_fd = -1;
    d.pad.handle = d.pad.user_id = -1;
    d.other_connected = -1;
    owner_monitor_init(&d.ownership);
    neutral(&d.pad.state);
    d.running = 1;
    d.started_ms = now_ms();

    mkdir("/data/ps5-mcp", 0755);
    if (open_log(d.cfg.log_dir) != 0) {
        perror("open log");
        return 2;
    }
    signal(SIGPIPE, SIG_IGN);
    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    log_event("startup", "\"schema\":1,\"protocol\":%d,\"version\":\"%d.%d\",\"port\":%d,\"tick_ms\":%u,"
              "\"watchdog_ms\":%u,\"idle_ms\":%u", PMCP_VERSION, PADD_VERSION >> 8, PADD_VERSION & 0xff,
              d.cfg.port, d.cfg.tick_ms, d.cfg.watchdog_ms, d.cfg.idle_ms);

    /* The port is the single-instance lock; claim it before touching the pad. */
    d.listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(d.listen_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)d.cfg.port);
#ifdef PADD_HOST_TEST
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
#else
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
#endif
    if (bind(d.listen_fd, (struct sockaddr *)&addr, sizeof addr) != 0 || listen(d.listen_fd, 2) != 0) {
        int error = errno;
        log_event("already_running", "\"errno\":%d", error);
        log_event("exit_requested", "\"code\":3");
        return 3;
    }
    log_event("listening", "\"port\":%d", d.cfg.port);

    /* Loading/checking the service must never open the controller picker.
     * Only an explicit QP_INITIALIZE request creates our virtual controller. */
    struct pad *first = &d.pad;
    d.other_status = EAGAIN;
    log_event("awaiting_controller_turn_on", "");

    uint64_t last_stats = now_ms();
    while (d.running && !stop_requested) {
        int was_monitored=d.ownership.synced;
        int monitored=owner_monitor_poll(&d.ownership,now_ms(),ownership_event,&d);
        if(was_monitored && !monitored && d.pad.handle>=0)
            yield_controller(&d,"Controller monitor unavailable. Controller turned off.");
        if(d.handoff_pending && now_ms()-d.last_handoff_retry>=500) {
            d.handoff_pending=disconnect_controller(&d)!=0; d.last_handoff_retry=now_ms();
        }
        struct pollfd fds[2] = {{d.listen_fd, POLLIN, 0}, {d.client_fd, POLLIN, 0}};
        int count = d.client_fd >= 0 ? 2 : 1;
        int ready = poll(fds, (nfds_t)count, (int)d.cfg.tick_ms);
        /* Read the client first: when its close and the next connect arrive together, the next one is not busy. */
        if (ready > 0 && count == 2 && (fds[1].revents & (POLLIN | POLLHUP | POLLERR))) read_client(&d);
        if (ready > 0 && (fds[0].revents & POLLIN)) accept_client(&d);

        uint64_t now = now_ms();
        if(live_tick(&d.keyboard,now)) {
            int32_t result[2]={d.keyboard.status,d.keyboard.opened};
            send_message(&d,QP_LIVE_KEYBOARD,result,sizeof result);
        }
        if(d.text.active && (d.client_fd<0 || now-d.last_rx_ms>1800)) text_cancel(&d.text,ECANCELED);
        if(text_tick(&d.text,now)) {
            int32_t result[2]={d.text.status,(int32_t)d.text.index};
            send_message(&d,QP_TYPE_TEXT,result,sizeof result);
        }
        if (d.client_fd >= 0 && now - d.last_state_ms > d.cfg.watchdog_ms) force_neutral(&d, "watchdog");
        if (d.client_fd >= 0 && now - d.last_rx_ms > d.cfg.idle_ms) drop_client(&d, "idle");
        /* Keep feeding the pads like a real controller does. */
        if (d.pad.ready && now - d.last_report_ms >= d.cfg.tick_ms) {
            apply(&d);
        }
        if (now - last_stats >= 60000) {
            log_event("stats", "\"reports_sent\":%llu,\"report_failures\":%u,\"neutral_events\":%u",
                      (unsigned long long)d.reports_sent, d.report_failures, d.neutral_events);
            last_stats = now;
        }
    }

    live_cancel(&d.keyboard,ECANCELED);
    while(d.keyboard.cleanup) {live_tick(&d.keyboard,now_ms());if(d.keyboard.cleanup) usleep(100000);}
    text_cancel(&d.text,ECANCELED);
    while(d.text.cleanup) {text_tick(&d.text,now_ms());if(d.text.cleanup) usleep(100000);}
    if (stop_requested) log_event("signal", "");
    force_neutral(&d, "exit");
    if (d.client_fd >= 0) close(d.client_fd);
    close(d.listen_fd);
    int remove_status = first->handle >= 0 ? pad_remove(first->handle) : 0;
    log_event("pad_removed", "\"status\":%d", remove_status);
    log_event("stats", "\"reports_sent\":%llu,\"report_failures\":%u,\"neutral_events\":%u",
              (unsigned long long)d.reports_sent, d.report_failures, d.neutral_events);
    owner_monitor_close(&d.ownership);
    system_shutdown();
    log_event("exit_requested", "\"code\":%d", remove_status ? 1 : 0);
    return remove_status ? 1 : 0;
}
