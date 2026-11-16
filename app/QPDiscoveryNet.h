#ifndef QP_DISCOVERY_NET_H
#define QP_DISCOVERY_NET_H
#include "PMCP.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

enum { QP_SCAN_CONCURRENCY=48, QP_SCAN_TIMEOUT_MS=650, QP_SCAN_MAX_HOSTS=254 };

/* Addresses are host order. Never sweep more than the current /24 of a larger LAN. */
static inline int qp_scan_range(uint32_t address, uint32_t mask, uint32_t *first, uint32_t *last) {
    uint32_t inverse=~mask;
    if(!mask || (inverse & (inverse+1)) || inverse<3) return 0;
    int limited=inverse>255;
    if(limited) mask=0xffffff00;
    *first=(address&mask)+1; *last=(address|~mask)-1;
    return limited?2:1;
}
/* Prioritize the previously added console, then alternate low/high addresses.
 * Every valid host appears once; never probe our own, network or broadcast IP. */
static inline size_t qp_scan_candidates(uint32_t address,uint32_t mask,uint32_t preferred,uint32_t hosts[QP_SCAN_MAX_HOSTS]) {
    uint32_t first,last; if(!qp_scan_range(address,mask,&first,&last)) return 0;
    size_t count=0;
    if(preferred>=first && preferred<=last && preferred!=address) hosts[count++]=preferred;
    for(uint32_t low=first,high=last;low<=high;low++,high--) {
        if(low!=address && low!=preferred) hosts[count++]=low;
        if(high!=low && high!=address && high!=preferred) hosts[count++]=high;
    }
    return count;
}
static inline int qp_discovery_reply(const uint8_t *frame, size_t size) {
    if(size<8 || !qp_valid_header(frame) || size!=(size_t)8+qp_u16(frame+6)) return 0;
    if(frame[5]==QP_HELLO && size==28 && qp_u16(frame+8)==1 && (qp_u32(frame+20)&0x10000)) return 1;
    if(frame[5]==QP_ERROR && size>=12 && qp_u32(frame+8)==5) return 2;
    return 0;
}
static inline int64_t qp_scan_ms(void) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC,&now);
    return (int64_t)now.tv_sec*1000+now.tv_nsec/1000000;
}
/* Read-only hello: sends no controller reports, initialization or app launch. */
static inline int qp_probe(uint32_t address, uint16_t port, int timeout_ms) {
    int fd=socket(AF_INET,SOCK_STREAM,0); if(fd<0) return 0;
    int old=fcntl(fd,F_GETFL,0), result=0;
    if(old<0 || fcntl(fd,F_SETFL,old|O_NONBLOCK)<0) { close(fd); return 0; }
    struct sockaddr_in target={0}; target.sin_family=AF_INET;
    target.sin_port=htons(port); target.sin_addr.s_addr=htonl(address);
    int64_t deadline=qp_scan_ms()+timeout_ms;
    int rc=connect(fd,(const struct sockaddr *)&target,sizeof target);
    if(rc<0 && errno!=EINPROGRESS) goto done;
    if(rc<0) {
        struct pollfd p={fd,POLLOUT,0};
        if(poll(&p,1,timeout_ms)<=0) goto done;
        int error=0; socklen_t length=sizeof error;
        if(getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&length)<0 || error) goto done;
    }
    uint8_t bytes[264]; size_t used=0,needed=8;
    while(used<needed) {
        int remaining=(int)(deadline-qp_scan_ms()); if(remaining<=0) goto done;
        struct pollfd p={fd,POLLIN,0};
        if(poll(&p,1,remaining)<=0) goto done;
        ssize_t count=recv(fd,bytes+used,needed-used,0);
        if(count<0 && (errno==EAGAIN || errno==EINTR)) continue;
        if(count<=0) goto done;
        used+=(size_t)count;
        if(used==8) {
            if(!qp_valid_header(bytes)) goto done;
            needed=8+qp_u16(bytes+6);
        }
    }
    result=qp_discovery_reply(bytes,used);
done:
    close(fd); return result;
}
#endif
