"""Socket tests: manual text has bounded lifetime and never survives disconnect."""
import json
from pathlib import Path
import socket
import struct
from tempfile import TemporaryDirectory
import time
import unittest
from initialization_test import Listener, send, receive

class TextTests(unittest.TestCase):
    def events(self,path):
        return [] if not path.exists() else [json.loads(line) for line in path.read_text().splitlines()]
    def test_typing_completes_removes_keyboard_and_never_presses_enter(self):
        with TemporaryDirectory() as directory:
            path=Path(directory,'keys.jsonl')
            with Listener(PADD_TEST_KEYBOARD_TRACE=path) as d:
                d.request(129)
                send(d.client,133,b'192.168.0.246')
                deadline=time.monotonic()+4
                while True:
                    send(d.client,3,struct.pack('<I',1))
                    kind,body=receive(d.client)
                    if kind==133: break
                    self.assertEqual(kind,3)
                    if time.monotonic()>deadline: self.fail('Text did not complete')
                    time.sleep(.15)
                self.assertEqual(struct.unpack('<iI',body),(0,13))
                events=self.events(path)
                self.assertEqual(events[0]['action'],'open');self.assertEqual(events[-1]['action'],'close')
                self.assertEqual(len([e for e in events if e['action']=='report' and e['key']]),13)
                self.assertFalse(any(e['key']==40 for e in events))
    def test_invalid_text_rejected_before_keyboard_created(self):
        with TemporaryDirectory() as directory:
            path=Path(directory,'keys.jsonl')
            with Listener(PADD_TEST_KEYBOARD_TRACE=path) as d:
                d.request(129)
                for value in (b'',b'x'*129,b'hello\n',b'abc\xff'):
                    send(d.client,133,value);kind,body=receive(d.client)
                    self.assertEqual(kind,133);self.assertNotEqual(struct.unpack('<iI',body)[0],0)
                self.assertFalse(path.exists())
    def test_disconnect_and_silent_client_remove_keyboard(self):
        for disconnect in (True,False):
            with self.subTest(disconnect=disconnect), TemporaryDirectory() as directory:
                path=Path(directory,'keys.jsonl')
                with Listener(PADD_TEST_KEYBOARD_TRACE=path) as d:
                    d.request(129);send(d.client,133,b'a'*128);time.sleep(.25)
                    if disconnect: d.client.close()
                    deadline=time.monotonic()+2.5
                    while not self.events(path) or self.events(path)[-1]['action']!='close':
                        if time.monotonic()>deadline:self.fail('Keyboard persisted after disconnect/lease expiry')
                        time.sleep(.03)
                    events=self.events(path); count=len(events);time.sleep(.1)
                    self.assertEqual(len(self.events(path)),count)
                    self.assertEqual(events[-2]['key'],0)
                    self.assertLess(len([e for e in events if e['key']]),128)

if __name__=='__main__':unittest.main()
