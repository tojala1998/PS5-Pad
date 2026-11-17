#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#include "owner_monitor.h"
void owner_monitor_init(struct owner_monitor *m) {
    memset(m,0,sizeof *m); m->fd=-1; m->enabled=1;
#ifdef PADD_HOST_TEST
    m->enabled=getenv("PADD_TEST_LOG_PORT")!=NULL;
#endif
}
void owner_monitor_close(struct owner_monitor *m) {
    if(m->fd>=0) close(m->fd);
    m->fd=-1; m->connecting=m->synced=0; m->length=0; m->overflow=0;
    memset(m->controllers,0,sizeof m->controllers);
}
int owner_monitor_poll(struct owner_monitor *m,uint64_t now,
                       void (*event)(void *,struct owner_event),void *context) {
    if(!m->enabled) return 1;
    if(m->fd<0) {
        if(now<m->retry_at) return 0;
        m->retry_at=now+2000; m->fd=socket(AF_INET,SOCK_STREAM,0);
        if(m->fd<0) return 0;
        if(fcntl(m->fd,F_SETFL,O_NONBLOCK)<0) {owner_monitor_close(m);return 0;}
        struct sockaddr_in a={0}; a.sin_family=AF_INET; a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
        int port=3232;
#ifdef PADD_HOST_TEST
        port=atoi(getenv("PADD_TEST_LOG_PORT"));
#endif
        a.sin_port=htons((uint16_t)port); m->connect_at=now;
        if(connect(m->fd,(struct sockaddr *)&a,sizeof a)<0 && errno!=EINPROGRESS) {owner_monitor_close(m);return 0;}
        m->connecting=1;
    }
    if(m->connecting) {
        struct pollfd p={m->fd,POLLOUT,0};
        int result=poll(&p,1,0);
        if(result<=0) {if(now-m->connect_at>1000) owner_monitor_close(m);return 0;}
        int error=0; socklen_t size=sizeof error;
        if(getsockopt(m->fd,SOL_SOCKET,SO_ERROR,&error,&size)<0 || error) {owner_monitor_close(m);return 0;}
        m->connecting=0;
    }
    char buf[4096];
    for(int round=0;round<16;round++) {
        ssize_t n=recv(m->fd,buf,sizeof buf,0);
        if(n<0 && (errno==EAGAIN || errno==EWOULDBLOCK)) {m->synced=1;return 1;}
        if(n<0 && errno==EINTR) continue;
        if(n<=0) {owner_monitor_close(m);return 0;}
        for(ssize_t i=0;i<n;i++) {
            if(buf[i]!='\n') {
                if(m->length+1<sizeof m->line) m->line[m->length++]=buf[i];
                else m->overflow=1;
                continue;
            }
            m->line[m->length]=0;
            if(!m->overflow) {
                struct owner_event e=owner_parse(m->line);
                int slot=-1,empty=-1;
                for(int j=0;j<64;j++) {if(m->controllers[j]==e.device && e.device) slot=j; if(!m->controllers[j]) empty=j;}
                if(e.kind==OWNER_ADD && e.controller && slot<0 && empty>=0) m->controllers[empty]=e.device;
                if(e.kind==OWNER_CHANGE) e.controller=slot>=0;
                if(e.kind==OWNER_REMOVE && slot>=0) m->controllers[slot]=0;
                if(m->synced && e.kind!=OWNER_NONE) event(context,e);
            }
            m->length=0; m->overflow=0;
        }
    }
    return m->synced;
}
