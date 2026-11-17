"""Real socket tests for a client-scoped live keyboard; never contact a console."""
import json,select,struct,time,unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from initialization_test import Listener,send,receive
class LiveTests(unittest.TestCase):
    def events(self,p): return [] if not p.exists() else [json.loads(s) for s in p.read_text().splitlines()]
    def request(self,d,p):
        send(d.client,134,p);end=time.monotonic()+25
        while time.monotonic()<end:
            send(d.client,135)
            if select.select([d.client],[],[],.2)[0]:
                kind,b=receive(d.client);self.assertEqual(kind,134);return struct.unpack('<iI',b)
        self.fail('keyboard reply timeout')
    def test_persistent_live_edits_then_enter(self):
        with TemporaryDirectory() as td:
            p=Path(td,'keys')
            with Listener(PADD_TEST_KEYBOARD_TRACE=p) as d:
                d.request(129)
                self.assertEqual(self.request(d,b'\0'),(0,1))
                self.assertFalse(any(e['action']=='report' and e['key'] for e in self.events(p)))
                self.assertEqual(self.request(d,b'\1\0\0hello'),(0,1))
                self.assertEqual(self.request(d,b'\1\1\0!'),(0,1))
                self.assertFalse(any(e['action']=='close' for e in self.events(p)))
                self.assertEqual(self.request(d,b'\3'),(0,0))
                events=self.events(p);keys=[e['key'] for e in events if e['action']=='report' and e['key']]
                self.assertEqual(keys,[11,8,15,15,18,42,30,40])
                self.assertEqual([e['action'] for e in events].count('open'),1)
                self.assertEqual(events[-1]['action'],'close')
    def test_close_never_submits_and_invalid_edits_do_not_type(self):
        with TemporaryDirectory() as td:
            p=Path(td,'keys')
            with Listener(PADD_TEST_KEYBOARD_TRACE=p) as d:
                d.request(129);self.request(d,b'\0')
                for bad in (b'\1',b'\1\x81\0',b'\1\0\0abc\n',b'\0oops'):
                    self.assertNotEqual(self.request(d,bad)[0],0)
                self.assertEqual(self.request(d,b'\2'),(0,0))
                self.assertFalse(any(e['key'] for e in self.events(p)))
    def test_general_pings_do_not_keep_keyboard_alive(self):
        with TemporaryDirectory() as td:
            p=Path(td,'keys')
            with Listener(PADD_TEST_KEYBOARD_TRACE=p) as d:
                d.request(129);self.request(d,b'\0');end=time.monotonic()+2.4
                while time.monotonic()<end:
                    send(d.client,3,struct.pack('<I',1));self.assertEqual(receive(d.client)[0],3);time.sleep(.1)
                self.assertEqual(self.events(p)[-1]['action'],'close')
                self.assertNotEqual(self.request(d,b'\1\0\0x')[0],0)
    def test_disconnect_stops_pending_keys_without_replay(self):
        with TemporaryDirectory() as td:
            p=Path(td,'keys')
            with Listener(PADD_TEST_KEYBOARD_TRACE=p) as d:
                d.request(129);self.request(d,b'\0');send(d.client,134,b'\1\0\0'+b'a'*128);time.sleep(.12)
                d.client.close();time.sleep(.2);events=self.events(p)
                self.assertEqual(events[-1]['action'],'close');count=len(events)
                d.reconnect();d.request(128);time.sleep(.1);self.assertEqual(len(self.events(p)),count)
    def test_close_interrupts_queued_typing(self):
        with TemporaryDirectory() as td:
            p=Path(td,'keys')
            with Listener(PADD_TEST_KEYBOARD_TRACE=p) as d:
                d.request(129);self.request(d,b'\0');send(d.client,134,b'\1\0\0'+b'a'*128);time.sleep(.12)
                send(d.client,135,b'\1');kind,body=receive(d.client)
                self.assertEqual(kind,134);self.assertEqual(struct.unpack('<iI',body)[1],0)
                events=self.events(p);self.assertEqual(events[-1]['action'],'close')
                self.assertLess(len([e for e in events if e['key']]),128)
                count=len(events);time.sleep(.15);self.assertEqual(len(self.events(p)),count)
    def test_controller_disconnect_cleans_up_keyboard(self):
        with TemporaryDirectory() as td:
            p=Path(td,'keys')
            with Listener(PADD_TEST_KEYBOARD_TRACE=p) as d:
                d.request(129);self.request(d,b'\0');d.request(132);time.sleep(.1)
                self.assertEqual(self.events(p)[-1]['action'],'close')
if __name__=='__main__':unittest.main()
