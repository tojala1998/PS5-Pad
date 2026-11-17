"""Offline regression contract: .13 controller implementation + power-only integration."""
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
