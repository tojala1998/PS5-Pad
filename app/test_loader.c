#include "QPLoaderPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    unsigned char elf[64]={0x7f,'E','L','F',2,1};elf[18]=62;
    assert(qp_loader_image_valid(elf,sizeof elf));assert(!qp_loader_image_valid(elf,63));
    elf[18]=183;assert(!qp_loader_image_valid(elf,64));elf[18]=62;elf[4]=1;assert(!qp_loader_image_valid(elf,64));
    assert(!qp_loader_image_valid(NULL,64));
    assert(qp_loader_fallback_allowed(false,false));
    assert(!qp_loader_fallback_allowed(true,false));assert(!qp_loader_fallback_allowed(true,true));assert(!qp_loader_fallback_allowed(false,true));
    /* Reproduce iOS waiting/refused and waiting/timeout, not just failed. */
    assert(qp_loader_service_absent(false,false,true,true,false));
    assert(qp_loader_service_absent(false,false,false,true,false));
    assert(!qp_loader_service_absent(false,false,true,false,false));
    assert(qp_loader_service_absent(false,false,true,false,true));
    assert(!qp_loader_service_absent(false,true,true,true,true));
    assert(!qp_loader_service_absent(true,false,true,true,true));
    assert(!qp_loader_service_absent(false,false,false,false,true));
    const char *stem="uhnmeyker-ps5pad-abc",*name="uhnmeyker-ps5pad-abc.elf";
    assert(qp_loader_owned_path("/data/pldmgr/payloads/local/uhnmeyker-ps5pad-abc/uhnmeyker-ps5pad-abc.elf",stem,name));
    assert(qp_loader_owned_path("/data/pldmgr/payloads/uhnmeyker-ps5pad-abc/uhnmeyker-ps5pad-abc.elf",stem,name));
    assert(!qp_loader_owned_path("/mnt/usb0/uhnmeyker-ps5pad-abc.elf",stem,name));
    assert(!qp_loader_owned_path("/data/pldmgr/payloads/other/uhnmeyker-ps5pad-abc.elf",stem,name));
    assert(!qp_loader_owned_path("/data/pldmgr/payloads/local/uhnmeyker-ps5pad-abc/../uhnmeyker-ps5pad-abc.elf",stem,name));
    unsigned char hello[28]={0};qp_header(hello,QP_HELLO,20);hello[8]=1;hello[10]=8;hello[11]=2;qp_put32(hello+20,QP_CAP_CONTROL);
    assert(qp_loader_hello_valid(hello,28,true));assert(!qp_loader_hello_valid(hello,27,true));
    hello[10]=7;assert(!qp_loader_hello_valid(hello,28,true));assert(qp_loader_hello_valid(hello,28,false));
    hello[10]=6;assert(!qp_loader_hello_valid(hello,28,true));assert(qp_loader_hello_valid(hello,28,false));
    hello[5]=QP_ERROR;assert(!qp_loader_hello_valid(hello,28,false));
    puts("PASS: loader image, fallback/no-duplicate policy, owned paths, and helper greeting/version validation.");
}
