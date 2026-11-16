#include "QPDiscoveryNet.h"
#include <assert.h>
#include <stdio.h>
#include <sys/wait.h>

static int serve(const uint8_t *bytes,size_t count,int slow) {
    int listener=socket(AF_INET,SOCK_STREAM,0); assert(listener>=0);
    struct sockaddr_in address={0}; address.sin_family=AF_INET; address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    assert(!bind(listener,(struct sockaddr *)&address,sizeof address)); assert(!listen(listener,1));
    socklen_t size=sizeof address; assert(!getsockname(listener,(struct sockaddr *)&address,&size));
    pid_t child=fork(); assert(child>=0);
    if(!child) {
        int peer=accept(listener,NULL,NULL); if(peer<0) _exit(2);
        if(slow) { struct timespec delay={0,180000000}; nanosleep(&delay,NULL); }
        else for(size_t i=0;i<count;i++) { if(send(peer,bytes+i,1,0)!=1) break; }
        /* Discovery must not write any input or initialization packet. */
        uint8_t unexpected; ssize_t read_count=recv(peer,&unexpected,1,0);
        close(peer); close(listener); _exit(read_count==0?0:3);
    }
    int found=qp_probe(INADDR_LOOPBACK,ntohs(address.sin_port),100);
    int status; waitpid(child,&status,0); close(listener);
    assert(WIFEXITED(status) && WEXITSTATUS(status)==0); return found;
}
int main(void) {
    uint32_t first,last;
    assert(qp_scan_range(0xc0a8000a,0xffffff00,&first,&last)==1 && first==0xc0a80001 && last==0xc0a800fe);
    assert(qp_scan_range(0x0a030405,0xffff0000,&first,&last)==2 && first==0x0a030401 && last==0x0a0304fe);
    assert(!qp_scan_range(1,0,&first,&last)); assert(!qp_scan_range(1,0xffff00ff,&first,&last));
    assert(!qp_scan_range(1,0xfffffffe,&first,&last));
    uint8_t hello[28]={0}; qp_header(hello,QP_HELLO,20); hello[8]=1; qp_put32(hello+20,0x10000);
    assert(serve(hello,sizeof hello,0)==1);
    hello[4]=2; assert(serve(hello,8,0)==0); hello[4]=1;
    qp_put32(hello+20,0); assert(serve(hello,sizeof hello,0)==0);
    uint8_t busy[12]={0}; qp_header(busy,QP_ERROR,4); qp_put32(busy+8,5);
    assert(serve(busy,sizeof busy,0)==2);
    assert(serve(NULL,0,1)==0);
    assert(!qp_discovery_reply(hello,27));
    puts("PASS: bounded subnet discovery, fragmented hello, busy response, invalid services and read-only timeout.");
    return 0;
}
