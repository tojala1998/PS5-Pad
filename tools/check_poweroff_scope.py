"""Preserve controller behavior; allow the explicitly authorized client helper updater."""
from pathlib import Path
import hashlib,json,re
root=Path(__file__).resolve().parent.parent
updater_paths={'app/QPConnection.m','app/QPHelperLoader.m','app/QPLoaderPolicy.h'}
for path,digest in json.loads((root/'tools/controller-0.4.13-lock.json').read_text()).items():
    if path in updater_paths: continue
    assert hashlib.sha256((root/path).read_bytes()).hexdigest()==digest, 'Unexpected controller change: '+path
required=re.search(r'QP_BUNDLED_HELPER_VERSION\s+0x([0-9a-fA-F]+)',(root/'app/QPHelperVersion.h').read_text())
bundled=re.search(r'PADD_VERSION\s+0x([0-9a-fA-F]+)',(root/'service/payload/padd.c').read_text())
assert required and bundled and int(required[1],16)==int(bundled[1],16), 'Client/helper version mismatch'
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
print('PASS: controller baseline preserved outside authorized helper updater; bundled version matches; Power Off remains independent.')
