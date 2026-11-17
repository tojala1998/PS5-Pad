/* Read-only running-title probe. No app launch/kill/suspend or controller calls. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
int sceLncUtilInitialize(void);
int sceLncUtilGetAppIdOfRunningBigApp(void);
int sceLncUtilGetAppTitleId(uint32_t app_id,char *title_id);
int sceSystemServiceGetAppIdOfRunningBigApp(void);
static void safe_title(char *title) {
    for(int i=0;i<9;i++) if(!((title[i]>='A'&&title[i]<='Z')||(title[i]>='0'&&title[i]<='9'))) {title[0]=0;return;}
    title[9]=0;
}
int main(void) {
    int fd=open("/data/ps5pad-app-detection-20261116.jsonl",O_WRONLY|O_CREAT|O_EXCL,0600);
    if(fd<0)return 1;
    FILE *f=fdopen(fd,"w");if(!f){close(fd);return 2;}
    int init=sceLncUtilInitialize();
    for(int i=0;i<3;i++) {
        int system_id=sceSystemServiceGetAppIdOfRunningBigApp();
        int app_id=sceLncUtilGetAppIdOfRunningBigApp();
        char title[256]={0};int rc=app_id>0?sceLncUtilGetAppTitleId((uint32_t)app_id,title):-1;
        if(rc)title[0]=0;else safe_title(title);
        fprintf(f,"{\"sample\":%d,\"lnc_init_status\":%d,\"system_app_id\":%d,\"lnc_app_id\":%d,\"title_status\":%d,\"title_id\":\"%s\"}\n",i,init,system_id,app_id,rc,title);
        fflush(f);usleep(250000);
    }
    fclose(f);return 0;
}
