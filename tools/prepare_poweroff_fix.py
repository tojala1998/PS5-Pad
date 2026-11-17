"""One-shot, main-only source preparation; never contacts either device."""
from pathlib import Path
import hashlib, json, plistlib, re, subprocess

BASE='1a9d44f2df606093c3a65de692f850111b27fff7'
HELPER_SHA='d14cd155fab7712e0ad4ec8cbd890db988426261fa6632e2399d9477c6f7418a'

def run(*args):
    return subprocess.check_output(args)

def write(path, text):
    p=Path(path); p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text,encoding='utf-8')

def patch(path, old, new):
    p=Path(path); raw=p.read_bytes().decode(); nl='\r\n' if '\r\n' in raw else '\n'
    old=old.replace('\n',nl); new=new.replace('\n',nl)
    if raw.count(old)!=1: raise RuntimeError(f'{path}: expected one match for {old[:90]!r}, got {raw.count(old)}')
    p.write_bytes(raw.replace(old,new).encode())

assert plistlib.loads(Path('app/Info.plist').read_bytes())['CFBundleShortVersionString']=='0.4.14'
# Restore the user's actual working source, not a reconstruction of .14.
paths=run('git','ls-tree','-r','--name-only',BASE,'app','service').decode().splitlines()
for path in paths:
    Path(path).parent.mkdir(parents=True,exist_ok=True)
    Path(path).write_bytes(run('git','show',f'{BASE}:{path}'))
assert hashlib.sha256(Path('service/prebuilt/padd-controller-2.7.elf').read_bytes()).hexdigest()==HELPER_SHA
baseline_main=Path('app/main.m').read_text()

write('app/QPPowerPolicy.h',r'''#ifndef QP_POWER_POLICY_H
#define QP_POWER_POLICY_H
#include <stdbool.h>
typedef struct { bool active, sent; } QPPowerAttempt;
/* Deliberately independent of profile, pad, helper version and controller busy. */
static inline bool qp_power_available(bool hostKnown, const QPPowerAttempt *p) {
    return hostKnown && !p->active && !p->sent;
}
static inline bool qp_power_begin(QPPowerAttempt *p, bool confirmed, bool hostKnown) {
    if (!confirmed || !qp_power_available(hostKnown,p)) return false;
    p->active=true; return true;
}
static inline bool qp_power_send_once(QPPowerAttempt *p) {
    if (!p->active || p->sent) return false;
    p->sent=true; return true;
}
static inline void qp_power_finish(QPPowerAttempt *p) { p->active=false; }
#endif
''')
write('app/QPPowerOff.h',r'''#import <Foundation/Foundation.h>
@interface QPPowerOff : NSObject
@property(nonatomic,readonly) BOOL available;
@property(nonatomic,copy) void (^completed)(NSString *message);
- (void)requestAt:(NSString *)host confirmed:(BOOL)confirmed;
- (void)cancel;
@end
''')
write('app/QPPowerOff.m',r'''#import "QPPowerOff.h"
#import "QPPowerPolicy.h"
#import "QPLoaderPolicy.h"
#import <Network/Network.h>
#include <errno.h>

@interface QPPowerOff () {
    nw_connection_t _socket;
    NSData *_image;
    QPPowerAttempt _attempt;
    NSUInteger _generation;
}
@end
@implementation QPPowerOff
- (BOOL)available { return qp_power_available(true,&_attempt); }
- (void)finish:(NSString *)message {
    if(!_attempt.active)return;
    qp_power_finish(&_attempt);
    nw_connection_t socket=_socket; _socket=nil;
    if(socket)nw_connection_cancel(socket);
    _image=nil;
    if(_completed)_completed(message);
}
- (void)cancel {
    if(!_attempt.active)return;
    [self finish:_attempt.sent?@"Shutdown result unknown. Check the PS5; the command was not retried.":@"Power off cancelled before sending a shutdown command."];
}
- (void)requestAt:(NSString *)host confirmed:(BOOL)confirmed {
    if(!qp_power_begin(&_attempt,confirmed,host.length>0))return;
    _image=[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"ps5pad-poweroff" ofType:@"elf"]];
    if(!qp_loader_image_valid(_image.bytes,_image.length)) {
        [self finish:@"The dedicated power-off payload is missing or invalid. No shutdown command was sent."];return;
    }
    NSUInteger generation=++_generation;
    nw_connection_t socket=nw_connection_create(nw_endpoint_create_host(host.UTF8String,"9021"),nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION));
    _socket=socket;
    nw_connection_set_queue(socket,dispatch_get_main_queue());
    nw_connection_set_state_changed_handler(socket,^(nw_connection_state_t state,nw_error_t error){
        if(generation!=self->_generation||!self->_attempt.active||self->_socket!=socket)return;
        if(state==nw_connection_state_ready) {
            if(!qp_power_send_once(&self->_attempt))return;
            dispatch_data_t data=dispatch_data_create(self->_image.bytes,self->_image.length,dispatch_get_main_queue(),DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            /* One complete ELF, then TCP write half-close, as used by .13's loader.
             * Never send PMCP 137 to an old controller helper, replace that helper,
             * initialize a controller, or retry an ambiguous transfer. */
            nw_connection_send(socket,data,NW_CONNECTION_FINAL_MESSAGE_CONTEXT,true,^(nw_error_t sendError){
                if(generation!=self->_generation||!self->_attempt.active||self->_socket!=socket)return;
                [self finish:sendError?@"Shutdown result unknown. Check the PS5; the command was not retried.":@"Full-power-off request sent. Check that the PS5 turns fully off, not into Rest Mode. It was not retried."];
            });
        } else if(state==nw_connection_state_failed || (state==nw_connection_state_waiting&&error)) {
            [self finish:self->_attempt.sent?@"Shutdown result unknown. Check the PS5; the command was not retried.":@"Cannot reach the PS5 ELF loader on port 9021. No shutdown command was sent. Start the ELF loader and try again."];
        }
    });
    nw_connection_start(socket);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(generation!=self->_generation||!self->_attempt.active||self->_socket!=socket)return;
        [self finish:self->_attempt.sent?@"Shutdown result unknown. Check the PS5; the command was not retried.":@"The PS5 ELF loader did not connect. No shutdown command was sent."];
    });
}
@end
''')
write('app/test_poweroff.c',r'''#include "QPPowerPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    QPPowerAttempt p={0};
    assert(!qp_power_begin(&p,false,true));
    assert(!qp_power_begin(&p,true,false));
    assert(!qp_power_send_once(&p));
    /* No profile/helper/pad argument exists: pending ownership cannot block power. */
    assert(qp_power_available(true,&p));
    assert(qp_power_begin(&p,true,true));
    assert(!qp_power_begin(&p,true,true));
    qp_power_finish(&p); /* failure before a transfer permits a fresh confirmation */
    assert(!qp_power_begin(&p,false,true));
    assert(qp_power_begin(&p,true,true));
    assert(qp_power_send_once(&p));
    assert(!qp_power_send_once(&p));
    qp_power_finish(&p); /* success, cancellation, error and timeout never auto-retry */
    assert(!qp_power_available(true,&p));
    assert(!qp_power_begin(&p,true,true));
    assert(!qp_power_send_once(&p));
    puts("PASS: power needs explicit confirmation, not profile assignment; single send and no uncertain retry.");
}
''')
write('service/poweroff/main.c',r'''/* One-shot orderly full shutdown, independent of the controller/profile service.
 * Reference: Marice/ps5-homeassistant src/power.c at 92dea18d4efca5cb792ab68a5d8721458549086a.
 * No HID, profile initialization, standby, ShellCore, or raw-reboot fallback.
 * Only delivered after the app's explicit destructive confirmation. */
int sceSystemStateMgrTurnOff(void);
int qp_request_full_power_off(void) { return sceSystemStateMgrTurnOff(); }
#ifndef QP_POWER_TEST
int main(void) { return qp_request_full_power_off() ? 1 : 0; }
#endif
''')
write('service/poweroff/test.c',r'''#include <assert.h>
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
''')

patch('app/main.m','#import "QPLifecycle.h"','#import "QPLifecycle.h"\n#import "QPPowerOff.h"')
patch('app/main.m','@property(nonatomic,strong) QPConnection *link;\n@property(nonatomic,strong) UIView *canvas;',
      '@property(nonatomic,strong) QPConnection *link;\n@property(nonatomic,strong) QPPowerOff *powerOffSender;\n@property(nonatomic,strong) UIView *canvas;')
old_power=baseline_main.split('- (void)confirmPowerOff {',1)[1].split('- (void)showConnection {',1)[0]
new_power=r'''- (void)confirmPowerOff {
    if(!_host.length||(_powerOffSender&&!_powerOffSender.available))return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Power Off PS5?" message:@"Request full shutdown through the PS5 ELF loader. No profile selection is required. This closes running apps and ends the jailbreak; you must turn the console on and jailbreak again before reconnecting." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Power Off" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        (void)a;if(!self.host.length||(self.powerOffSender&&!self.powerOffSender.available))return;
        [self cancelEnsureSession];qp_initialization_cancel(&self->_initialization);
        self.wantsConnection=NO;self.needsInitializePrompt=NO;self.autoInitializeAttempted=YES;
        [self clearControls];[self.link disconnect:@"Requesting full power off…"];
        if(!self.powerOffSender)self.powerOffSender=[QPPowerOff new];
        __weak QPViewController *weakSelf=self;
        self.powerOffSender.completed=^(NSString *message){
            QPViewController *controller=weakSelf;if(!controller)return;
            controller.result.text=message;
            if(!controller->_lifecycle.active||!controller.view.window||controller.presentedViewController)return;
            UIAlertController *result=[UIAlertController alertControllerWithTitle:@"Power Off" message:message preferredStyle:UIAlertControllerStyleAlert];
            [result addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [controller presentViewController:result animated:YES completion:nil];
        };
        [self.powerOffSender requestAt:self.host confirmed:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
'''
patch('app/main.m','- (void)confirmPowerOff {'+old_power,new_power)
old_enable='    power.enabled=_link.ready&&_link.supportsPowerOff&&!_link.controlBusy&&!_link.keyboardActive&&!_link.disconnectingController;'
new_enable='    power.enabled=_host.length>0&&(!_powerOffSender||_powerOffSender.available);'
patch('app/main.m',old_enable,new_enable)
patch('app/main.m','    qp_lifecycle_suspend(&_lifecycle); _lifecycleBlockedReason=@"Scene inactive";',
      '    qp_lifecycle_suspend(&_lifecycle); _lifecycleBlockedReason=@"Scene inactive";\n    [_powerOffSender cancel];')
patch('app/Info.plist','<string>0.4.13</string>','<string>0.4.15</string>')
patch('app/Info.plist','<string>19</string>','<string>21</string>')
# Host-only portability fixes; console/controller implementation remains .13.
patch('app/test_discovery.c','#include <sys/wait.h>', '#include <sys/wait.h>\n#ifndef INADDR_LOOPBACK\n#define INADDR_LOOPBACK 0x7f000001u\n#endif')
patch('service/payload/system_host.c','(void)fgets(state,sizeof state,f);fclose(f);','if(!fgets(state,sizeof state,f)){fclose(f);return;}fclose(f);')

# Guard every original controller file byte-for-byte, apart from the enumerated power/UI or host-test changes.
changed={'app/main.m','app/Info.plist','app/verify_ipa.py','app/test_discovery.c','service/payload/system_host.c'}
locked={p:hashlib.sha256(run('git','show',f'{BASE}:{p}')).hexdigest() for p in paths
        if (p.startswith('app/') or p.startswith('service/payload/')) and p not in changed}
locked['service/prebuilt/padd-controller-2.7.elf']=HELPER_SHA
write('tools/controller-0.4.13-lock.json',json.dumps(locked,indent=2)+'\n')
write('tools/check_poweroff_scope.py',r'''"""Offline regression contract: .13 controller implementation + power-only integration."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parent.parent
for path,digest in json.loads((root/'tools/controller-0.4.13-lock.json').read_text()).items():
    assert hashlib.sha256((root/path).read_bytes()).hexdigest()==digest, 'Unexpected controller change: '+path
main=(root/'app/main.m').read_text()
power=main.split('- (void)confirmPowerOff {',1)[1].split('- (void)showConnection {',1)[0]
assert 'requestAt:self.host confirmed:YES' in power
for forbidden in ('supportsPowerOff','profileAssigned','waitingForProfile','controlBusy','padReady','initializeController','[self.link powerOff]'):
    assert forbidden not in power, 'Power depends on controller state: '+forbidden
assert 'power.enabled=_host.length>0&&(!_powerOffSender||_powerOffSender.available);' in main
sender=(root/'app/QPPowerOff.m').read_text()
assert 'NW_CONNECTION_FINAL_MESSAGE_CONTEXT' in sender and 'qp_power_send_once' in sender
assert 'QP_POWER_OFF' not in sender and '9305' not in sender
payload=(root/'service/poweroff/main.c').read_text()
assert 'int qp_request_full_power_off(void) { return sceSystemStateMgrTurnOff(); }' in payload
for forbidden in ('sceShellCoreUtilRequestShutdown','sceSystemStateMgrEnterStandby','reboot(','pad_add('):
    assert forbidden not in payload
print('PASS: .13 controller files/ELF unchanged; Power Off is independent of profile and controller readiness.')
''')
# Packaging verifies the exact two payloads, not a version label.
patch('app/verify_ipa.py',"        elf=archive.read(prefix+'padd-controller.elf')",r'''        poweroff=archive.read(prefix+'ps5pad-poweroff.elf')
        expected_poweroff=Path(__file__).resolve().parent.parent/'service/prebuilt/ps5pad-poweroff-1.0.elf'
        assert poweroff==expected_poweroff.read_bytes(), 'Dedicated power payload differs from this build'
        assert poweroff[:6]==b'\x7fELF\x02\x01' and struct.unpack_from('<H',poweroff,18)[0]==62, 'Invalid power ELF'
        elf=archive.read(prefix+'padd-controller.elf')''')
patch('app/verify_ipa.py',"            'service_sha256':hashlib.sha256(elf).hexdigest(),", "            'service_sha256':hashlib.sha256(elf).hexdigest(),\n            'poweroff_sha256':hashlib.sha256(poweroff).hexdigest(),")
patch('tools/build.sh','for source in main QPConnection QPDiscovery QPLocalNetworkAccess QPHelperLoader; do', 'for source in main QPConnection QPDiscovery QPLocalNetworkAccess QPHelperLoader QPPowerOff; do')
patch('tools/build.sh','"$BUILD/QPHelperLoader.o" \\', '"$BUILD/QPHelperLoader.o" "$BUILD/QPPowerOff.o" \\')
patch('tools/build.sh','python3 check_ui_contract.py "$SDK"','python3 check_ui_contract.py "$SDK"\npython3 "$ROOT/tools/check_poweroff_scope.py"\ncc -std=c11 -Wall -Wextra -Werror test_poweroff.c -o "$BUILD/test_poweroff"\n"$BUILD/test_poweroff"')
patch('tools/build.sh','cp "$ELF" "$APP/padd-controller.elf"', 'cp "$ELF" "$APP/padd-controller.elf"\ncp "$ROOT/service/prebuilt/ps5pad-poweroff-1.0.elf" "$APP/ps5pad-poweroff.elf"')

# Keep the tested publishing pipeline, changing only which payloads are built/bundled.
workflow=Path('.github/workflows/unsigned-build.yml').read_text()
a=workflow.index('          make -C service all BUILD=')
b=workflow.index('      - name: Upload verified ELF',a)
compile_block=r'''          python3 tools/check_poweroff_scope.py
          cc -std=c11 -Wall -Wextra -Werror app/test_poweroff.c -o "$RUNNER_TEMP/test-power-policy"
          "$RUNNER_TEMP/test-power-policy"
          cc -std=c11 -Wall -Wextra -Werror -DQP_POWER_TEST service/poweroff/main.c service/poweroff/test.c -o "$RUNNER_TEMP/test-power-api"
          "$RUNNER_TEMP/test-power-api"
          mkdir -p dist
          # Reuse the EXACT .13 controller helper. Only the one-shot shutdown ELF is new.
          echo "d14cd155fab7712e0ad4ec8cbd890db988426261fa6632e2399d9477c6f7418a  service/prebuilt/padd-controller-2.7.elf" | sha256sum --check
          cp service/prebuilt/padd-controller-2.7.elf dist/
          "$PS5_PAYLOAD_SDK/bin/prospero-clang" -std=c11 -Wall -Wextra -Werror -O1 -o dist/ps5pad-poweroff-1.0.elf service/poweroff/main.c -lSceSystemService
          python3 - <<'PY'
          from pathlib import Path
          import struct
          p=Path('dist/ps5pad-poweroff-1.0.elf').read_bytes()
          assert len(p)>=64 and p[:6]==b'\x7fELF\x02\x01' and struct.unpack_from('<H',p,18)[0]==62
          print('Dedicated shutdown ELF format verified; no console commands were run.')
          PY
          sha256sum dist/*.elf
'''
workflow=workflow[:a]+compile_block+workflow[b:]
workflow=workflow.replace('path: dist/padd-controller-*.elf','path: dist/*.elf')
workflow=workflow.replace("          shutil.copy2(matching[0],Path('staged/service/prebuilt')/matching[0].name)","          shutil.copy2(matching[0],Path('staged/service/prebuilt')/matching[0].name)\n          power=Path('service/prebuilt/ps5pad-poweroff-1.0.elf')\n          assert hashlib.sha256(power.read_bytes()).hexdigest()==report['poweroff_sha256']\n          shutil.copy2(power,Path('staged/service/prebuilt')/power.name)")
workflow=workflow.replace('git add -- source.json "releases/$version" service/prebuilt/padd-controller-*.elf','git add -- source.json "releases/$version" service/prebuilt/padd-controller-*.elf service/prebuilt/ps5pad-poweroff-*.elf')
workflow=workflow.replace("      - 'service/prebuilt/*.elf'", "      - 'service/prebuilt/*.elf'\n      - '.github/workflows/prepare-poweroff.yml'\n      - 'tools/prepare_poweroff_fix.py'")
write('tools/unsigned-build.next.yml',workflow)
write('docs/PS5-Pad-0.4.15-notes.txt', '''PS5 Pad 0.4.15 (build 21) — 0.4.13 controller baseline, independent Power Off

Restores the 0.4.13 controller, keyboard, discovery and initialization source.
Bundles the exact original helper 2.7 from 0.4.13, verified by SHA-256; it is
not rebuilt or silently replaced while running.

Power Off is now a separate, explicitly confirmed one-shot request through the
PS5 ELF loader on port 9021. It calls sceSystemStateMgrTurnOff and does not
require a profile selection, controller initialization, a helper version check,
or successful controller ownership detection. It never sends the old helper's
Rest Mode-producing command, and never automatically retries an uncertain send.
The result is shown independently of the controller/profile status message.

The ELF loader must be running. A transfer acknowledgment is not proof of a
physical shutdown. Full shutdown behavior still needs an on-console test.
A full shutdown closes running apps and ends the jailbreak; power on and run
the jailbreak again before reconnecting. Existing running helpers are left alone.
''')
with Path('README.md').open('a') as f:
    f.write('''\n## 0.4.15 power-off correction\n\nThe controller implementation and bundled helper are restored to 0.4.13.\nPower Off uses a separate one-shot payload through ELF loader TCP 9021, after\nexplicit confirmation, without waiting for controller/profile assignment.\nOnly that shutdown payload is newly compiled; the original controller ELF is\nchecksum-pinned. Existing running helpers are not replaced. No automatic\nretry follows an ambiguous transfer. Physical shutdown remains device-test-only.\n''')
# Check the exact source before committing it; neither test can contact the PS5.
subprocess.run(['python3','tools/check_poweroff_scope.py'],check=True)
subprocess.run(['bash','-n','tools/build.sh'],check=True)
for path in ('app/verify_ipa.py','tools/check_poweroff_scope.py'):
    compile(Path(path).read_text(),path,'exec')
# Workflow files are promoted separately through the GitHub connector;
# GITHUB_TOKEN is not given or assumed to have workflows write permission.
print('Prepared .15 source from the actual .13 baseline; ready for CI, no devices touched.')
