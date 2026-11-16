"""Host socket/behavior tests against a fake backend; never contacts a console."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

PROGRAM = Path(sys.argv.pop(1)).resolve()
PORT = 19306

class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.log = Path(self.temp.name) / 'backend.log'
        self.process = subprocess.Popen([str(PROGRAM)], env={**os.environ, 'UH_PROBE_TEST_LOG': str(self.log)})
        deadline = time.monotonic() + 3
        while True:
            try:
                self.sock = socket.create_connection(('127.0.0.1', PORT), timeout=1)
                break
            except OSError:
                if self.process.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError('Host probe failed to start')
                time.sleep(.02)
        self.sock.settimeout(15)
        self.reader = self.sock.makefile('rb')
        self.hello = self.read()

    def tearDown(self):
        self.reader.close()
        self.sock.close()
        if self.process.poll() is None:
            self.process.terminate()
        self.process.wait(timeout=3)
        self.temp.cleanup()

    def read(self):
        return json.loads(self.reader.readline())

    def cmd(self, text):
        self.sock.sendall(text.encode('ascii') + b'\n')
        return self.read()

    def events(self):
        if not self.log.exists():
            return []
        return [(p[0], *map(int, p[1:])) for line in self.log.read_text().splitlines() if (p := line.split())]

    def test_startup_and_status_never_create_device(self):
        self.assertFalse(self.hello['keyboard_open'])
        self.assertFalse(self.hello['keyboard_detection'])
        self.assertEqual(self.hello['supported_input'], 'experimental')
        self.assertEqual(self.hello['firmware_hex'], '0x13000040')
        for _ in range(4):
            self.assertFalse(self.cmd('STATUS')['keyboard_open'])
        self.assertFalse(self.cmd('TYPE 6869')['ok'])
        self.assertEqual(self.events(), [])

    def test_ascii_mapping_press_duration_and_release(self):
        self.assertTrue(self.cmd('OPEN')['ok'])
        before = time.monotonic()
        self.assertEqual(self.cmd('TYPE ' + b'Aa0:./'.hex())['count'], 6)
        self.assertGreaterEqual(time.monotonic() - before, .45)
        events = self.events()
        reports = [e for e in events if e[0] == 'R']
        self.assertEqual([(e[2], e[3]) for e in reports],
                         [(2,4),(0,0),(0,4),(0,0),(0,39),(0,0),(2,51),(0,0),(0,55),(0,0),(0,56),(0,0)])
        self.assertGreaterEqual(reports[0][1] - events[0][1], 145)
        for down, up in zip(reports[::2], reports[1::2]):
            self.assertGreaterEqual(up[1] - down[1], 35)
        self.assertTrue(self.cmd('CLOSE')['ok'])
        self.assertEqual(self.events()[-1][0], 'C')

    def test_invalid_payload_rejected_before_any_keys(self):
        self.cmd('OPEN')
        for text in ['TYPE 41ff', 'TYPE 4100', 'TYPE 410a', 'TYPE f', 'TYPE zz', 'TYPE ', 'KEY DELETE']:
            self.assertFalse(self.cmd(text)['ok'])
        self.assertEqual([e[0] for e in self.events()], ['O'])
        self.sock.sendall(b'TYPE ' + b'41'*129 + b'\n')
        self.assertFalse(self.read()['ok'])
        self.assertEqual([e[0] for e in self.events()], ['O'])

    def test_disconnect_closes_only_owned_device(self):
        self.cmd('OPEN')
        self.reader.close(); self.sock.close()
        time.sleep(.1)
        self.assertEqual([e[0] for e in self.events()], ['O','R','C'])

    def test_idle_partial_line_does_not_keep_keyboard_open(self):
        self.cmd('OPEN')
        self.sock.sendall(b'TYPE ')
        time.sleep(.7)
        self.assertEqual(self.reader.readline(), b'')
        self.assertEqual([e[0] for e in self.events()], ['O','R','C'])

    def test_special_keys_and_stop(self):
        self.cmd('OPEN')
        for key in ('BACKSPACE','ENTER','ESCAPE'):
            self.assertTrue(self.cmd('KEY '+key)['ok'])
        self.assertEqual([e[3] for e in self.events() if e[0]=='R' and e[3]], [42,40,41])
        self.assertTrue(self.cmd('STOP')['ok'])
        self.assertEqual(self.process.wait(timeout=3), 0)
        self.assertEqual(self.events()[-1][0], 'C')

if __name__ == '__main__':
    unittest.main()
