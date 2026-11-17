"""Real host-daemon/socket tests for reciprocal controller ownership."""
import socket
import struct
import time
import unittest
from initialization_test import Listener, send, receive, STATE

READY=1; ASSIGNED=0x80000; PENDING=0x100000; YIELDED=0x200000; MONITOR=0x400000
PREFIX='<118>#LOGIN MGR# Receive Event : SCE_MBUS_EVENT_DEVICE_'

class HandoffTests(unittest.TestCase):
    def setUp(self):
        self.server=socket.socket(); self.server.bind(('127.0.0.1',0)); self.server.listen(1)
        self.server.settimeout(2)
        self.daemon=Listener(PADD_TEST_LOG_PORT=self.server.getsockname()[1])
        self.log,_=self.server.accept(); self.log.settimeout(2)
        self.wait_status(lambda s:s[5]&MONITOR)
    def tearDown(self):
        self.log.close(); self.server.close(); self.daemon.close()
    def wait_status(self,predicate):
        deadline=time.monotonic()+2
        while True:
            status=self.daemon.request(128)
            if predicate(status): return status
            if time.monotonic()>deadline: self.fail(f'Status did not converge: {status}')
            time.sleep(.015)
    def event(self,kind,device,extra=''):
        self.log.sendall(f'{PREFIX}{kind} [DeviceId:0x{device:x}]{extra}\n'.encode())
    def init_assigned(self):
        s=self.daemon.request(129); self.assertEqual(s[0],0); self.assertTrue(s[5]&PENDING)
        self.assertFalse(s[5]&ASSIGNED)
        pad=s[4]; user=self.daemon.events('pad_add')[-1]['user_id']
        self.event('ADDED',pad,'[type:1][subType:22][capabilityBattery:0]')
        self.event('OWNER_CHANGED',pad,f'[UserId:0x{user:x}]')
        self.wait_status(lambda s:s[5]&ASSIGNED)
        return pad,user
    def test_physical_takeover_removes_only_our_pad_and_never_recreates(self):
        pad,user=self.init_assigned()
        physical=0x1c0300
        self.event('ADDED',physical,'[type:1][subType:22][capabilityBattery:1]')
        self.event('OWNER_CHANGED',physical,f'[UserId:0x{user:x}]')
        kind,error=receive(self.daemon.client); self.assertEqual(kind,5); self.assertEqual(struct.unpack('<I',error[:4])[0],8)
        self.daemon.client.close(); self.daemon.reconnect()
        s=self.daemon.request(128); self.assertEqual(s[4],-1); self.assertTrue(s[5]&YIELDED)
        self.assertFalse(s[5]&READY); self.assertFalse(s[5]&ASSIGNED)
        time.sleep(.1)
        self.assertEqual(len(self.daemon.events('pad_add')),1)
        self.assertEqual([e['handle'] for e in self.daemon.events('pad_remove')],[pad])
        # Explicitly turning the phone controller back on starts profile selection.
        s=self.daemon.request(129); self.assertEqual(s[0],0); self.assertTrue(s[5]&PENDING)
        self.assertFalse(s[5]&ASSIGNED); self.assertNotEqual(s[4],pad)
    def test_other_profile_and_noncontroller_events_do_not_take_over(self):
        pad,user=self.init_assigned()
        self.event('ADDED',999,'[type:1][subType:22]'); self.event('OWNER_CHANGED',999,f'[UserId:0x{user+1:x}]')
        self.event('ADDED',888,'[type:2][subType:1]'); self.event('OWNER_CHANGED',888,f'[UserId:0x{user:x}]')
        self.log.sendall(b'x'*2100+f'{PREFIX}OWNER_CHANGED [DeviceId:0x{pad:x}][UserId:0xffffffff]\n'.encode())
        time.sleep(.05); s=self.daemon.request(128)
        self.assertEqual(s[4],pad); self.assertTrue(s[5]&ASSIGNED)
        self.assertEqual(self.daemon.events('pad_remove'),[])
    def test_monitor_loss_yields_instead_of_claiming_assignment(self):
        pad,_=self.init_assigned(); self.log.close()
        kind,error=receive(self.daemon.client); self.assertEqual(kind,5)
        self.daemon.client.close(); self.daemon.reconnect()
        s=self.daemon.request(128); self.assertFalse(s[5]&ASSIGNED); self.assertEqual(s[4],-1)
        s=self.daemon.request(129); self.assertNotEqual(s[0],0)
        self.assertEqual(len(self.daemon.events('pad_add')),1)
    def test_pending_profile_restricts_input_and_media_launch(self):
        s=self.daemon.request(129); self.assertTrue(s[5]&PENDING)
        send(self.daemon.client,2,struct.pack('<II6B14x',1,0xffffffff,0,255,0,255,255,255))
        kind,_=receive(self.daemon.client); self.assertEqual(kind,4)
        last=self.daemon.events('pad_report')[-1]
        self.assertEqual(last['buttons'],0x60f0)
        self.assertEqual([last[k] for k in ('lx','ly','rx','ry','l2','r2')],[128,128,128,128,0,0])
        send(self.daemon.client,131); kind,payload=receive(self.daemon.client)
        self.assertEqual(kind,131); self.assertNotEqual(struct.unpack('<i',payload)[0],0)

if __name__=='__main__': unittest.main()
