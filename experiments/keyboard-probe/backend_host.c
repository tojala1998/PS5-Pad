/* SPDX-License-Identifier: GPL-3.0-only. Local fake backend; never shipped in the ELF. */
#include "backend.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static int active;
static void event(char kind, unsigned a, unsigned b) {
    const char *path=getenv("UH_PROBE_TEST_LOG"); if(!path) abort();
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts);
    FILE *f=fopen(path,"a"); if(!f) abort();
    fprintf(f,"%c %lld %u %u\n",kind,(long long)ts.tv_sec*1000+ts.tv_nsec/1000000,a,b); fclose(f);
}
uint32_t backend_firmware(void) { return 0x13000040; }
int backend_open(void) { if(active) abort(); active=1; event('O',0,0); return 0; }
int backend_report(uint8_t mod,uint8_t key) { if(!active) abort(); event('R',mod,key); return 0; }
int backend_close(void) { if(!active) abort(); event('R',0,0); event('C',0,0); active=0; return 0; }
