#include <assert.h>
#include <stdio.h>
static int calls, result;
int sceSystemStateMgrTurnOff(void) { calls++; return result; }
int qp_request_full_power_off(void);
int main(void) {
    assert(qp_request_full_power_off()==0 && calls==1);
    result=-42;
    assert(qp_request_full_power_off()==-42 && calls==2);
    puts("PASS: standalone power payload calls the full-off API once and propagates failure; host stub only.");
}
