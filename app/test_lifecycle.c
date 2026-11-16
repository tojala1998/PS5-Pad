#include "QPLifecycle.h"
#include "QPInitialization.h"
#include <assert.h>
#include <stdio.h>

/* Event-order harness around the production lifecycle component. The app-wide
 * state deliberately remains inactive when sceneDidBecomeActive fires. UIKit
 * wiring is checked alongside this test by check_ui_contract.py. */
typedef struct {
    QPLifecycle lifecycle;
    QPEnsureSession ensure;
    QPInitialization initialization;
    bool savedHost,wantsConnection,autoAttempted,aggregateAppActive;
    unsigned connects,inits,reuses;
} App;
static uint64_t scene_active(App *a) {
    qp_lifecycle_activate(&a->lifecycle);
    return qp_lifecycle_queue_start(&a->lifecycle);
}
static uint64_t view_loaded(App *a) {
    a->savedHost=true; a->wantsConnection=true;
    qp_lifecycle_view_ready(&a->lifecycle);
    return qp_lifecycle_queue_start(&a->lifecycle);
}
static void deferred_activation(App *a,uint64_t token) {
    if(!qp_lifecycle_take_start(&a->lifecycle,token)) return;
    if(!a->savedHost || !a->wantsConnection || qp_initialization_pending(&a->initialization)) return;
    a->autoAttempted=false;
    qp_ensure_begin(&a->ensure);
    unsigned delay=99;
    assert(qp_ensure_next(&a->ensure,false,&delay)==QP_ENSURE_CONNECT && delay==0);
    a->connects++;
}
static void suspend_app(App *a) {
    qp_lifecycle_suspend(&a->lifecycle); qp_ensure_cancel(&a->ensure);
    qp_initialization_cancel(&a->initialization);
}
static void status_received(App *a,bool success,bool padReady) {
    qp_ensure_cancel(&a->ensure); /* A valid HELLO already stopped reconnect/load. */
    if(!a->lifecycle.active || !a->wantsConnection) return;
    if(qp_resume_reuses_controller(true,success,padReady,false)) { a->reuses++; return; }
    if(qp_should_auto_initialize(a->autoAttempted,true,success,padReady,false,true,success?0:-1)) {
        a->autoAttempted=true;
        assert(qp_initialization_request(&a->initialization,false));
        assert(qp_initialization_step(&a->initialization,true,false,false,true,false)==QP_INIT_SEND);
        a->inits++;
    }
}
int main(void) {
    App before={0};
    assert(!view_loaded(&before));
    assert(!qp_lifecycle_queue_start(&before.lifecycle)); /* viewDidAppear before activation */
    uint64_t token=scene_active(&before);
    assert(token && !before.aggregateAppActive);
    deferred_activation(&before,token);
    assert(before.connects==1 && before.lifecycle.starts==1);
    status_received(&before,true,true); assert(before.reuses==1 && before.inits==0);
    assert(!scene_active(&before)); /* duplicate activation callback */
    assert(!qp_lifecycle_queue_start(&before.lifecycle)); /* later viewDidAppear */
    deferred_activation(&before,token); assert(before.connects==1);

    App after={0};
    assert(!scene_active(&after)); /* scene callback precedes view/defaults hydration */
    uint64_t generation=after.lifecycle.generation;
    assert(!qp_lifecycle_queue_start(&after.lifecycle));
    assert(after.lifecycle.generation==generation && !after.lifecycle.started);
    token=view_loaded(&after); assert(token);
    deferred_activation(&after,token);
    assert(after.connects==1 && !after.aggregateAppActive);
    status_received(&after,false,false); assert(after.inits==0); /* failed STATUS is not absence */

    /* Lock/unlock reuses the service-owned controller without a new INIT. */
    suspend_app(&before); token=scene_active(&before);
    deferred_activation(&before,token); status_received(&before,true,true);
    assert(before.connects==2 && before.reuses==2 && before.inits==0);
    /* A genuinely absent pad initializes once, only after fresh STATUS. */
    suspend_app(&before); token=scene_active(&before); deferred_activation(&before,token);
    assert(before.inits==0); status_received(&before,true,false); status_received(&before,true,false);
    assert(before.inits==1);

    /* Stale queued work cannot reconnect after a fast lock or replace the new activation. */
    App rapid={0}; view_loaded(&rapid); uint64_t old=scene_active(&rapid);
    suspend_app(&rapid); deferred_activation(&rapid,old); assert(rapid.connects==0);
    token=scene_active(&rapid); deferred_activation(&rapid,old);
    assert(rapid.lifecycle.queued && rapid.connects==0);
    deferred_activation(&rapid,token); assert(rapid.connects==1);
    /* Explicit Disconnect remains respected across sleep/awake. */
    rapid.wantsConnection=false; qp_ensure_cancel(&rapid.ensure);
    suspend_app(&rapid); token=scene_active(&rapid); deferred_activation(&rapid,token);
    status_received(&rapid,true,false); assert(rapid.connects==1 && rapid.inits==0);
    /* A manual Initialize can arrive before queued activation work. Activation
     * must not clear its one-attempt latch or start a competing connection. */
    App overlap={0}; view_loaded(&overlap); token=scene_active(&overlap);
    assert(qp_initialization_request(&overlap.initialization,true));
    overlap.autoAttempted=true;
    deferred_activation(&overlap,token);
    assert(overlap.connects==0 && overlap.autoAttempted);
    assert(qp_initialization_step(&overlap.initialization,true,false,false,true,false)==QP_INIT_SEND);
    overlap.inits++;
    qp_initialization_complete(&overlap.initialization,false);
    status_received(&overlap,true,false); assert(overlap.inits==1);
    puts("PASS: production scene lifecycle handles inactive aggregate state, both view orders, duplicates, suspend/cancel, reuse and explicit disconnect.");
}
