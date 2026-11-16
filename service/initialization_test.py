"""Exercise initialization failures with the host backend, never a real console."""
import errno
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory
import time
import unittest

from smoke_test import receive, send

PROGRAM = str(Path(sys.argv.pop(1)).resolve())
STATUS = struct.Struct('<iiiiiIII')
PAD_READY = 1


class Listener:
    def __init__(self, **faults):
        self.temp = TemporaryDirectory()
        self.trace = Path(self.temp.name, 'trace.jsonl')
        with socket.socket() as reserved:
            reserved.bind(('127.0.0.1', 0))
            port = reserved.getsockname()[1]
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith('PADD_TEST_') and key not in ('PADD_FAIL_ADD', 'PADD_FAIL_ADD_USER')}
        environment.update({'PADD_TRACE': str(self.trace), 'PADD_TEST_ENFORCE_SINGLE_PAD': '1',
                            'PADD_TEST_TRACE_REPORTS': '1'})
        environment.update({key: str(value) for key, value in faults.items()})
        self.process = subprocess.Popen([PROGRAM, '--port', str(port), '--log-dir', self.temp.name],
                                        env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 3
        while True:
            try:
                self.client = socket.create_connection(('127.0.0.1', port), timeout=2)
                break
            except ConnectionRefusedError:
                if self.process.poll() is not None or time.monotonic() > deadline:
                    self.close()
                    raise RuntimeError('Host listener did not start')
                time.sleep(.02)
        kind, hello = receive(self.client)
        if kind != 1 or len(hello) != 20:
            raise RuntimeError('Host listener returned an invalid greeting')

    def request(self, kind):
        send(self.client, kind)
        actual, payload = receive(self.client)
        if actual != kind:
            raise AssertionError(f'Expected response {kind}, received {actual}')
        return STATUS.unpack(payload)

    def events(self, call=None):
        events = [] if not self.trace.exists() else [json.loads(line) for line in self.trace.read_text().splitlines()]
        return [event for event in events if call is None or event['call'] == call]

    def shutdown(self):
        send(self.client, 6)
        kind, _ = receive(self.client)
        if kind != 4:
            raise AssertionError('Missing shutdown acknowledgement')
        self.client.close()
        return self.process.wait(timeout=3)

    def close(self):
        if hasattr(self, 'client'):
            self.client.close()
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.process.stderr.close()
        self.temp.cleanup()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


class InitializationTests(unittest.TestCase):
    def test_query_failure_does_not_skip_detach_settle(self):
        with Listener(PADD_TEST_CONTROLLER_QUERY_ERROR=errno.EIO, PADD_TEST_READD_SETTLE_MS=180) as listener:
            first = listener.request(129)
            self.assertEqual(first[0], 0)
            self.assertEqual(first[3], errno.EIO)
            self.assertEqual(first[2], -1)
            second = listener.request(129)
            self.assertEqual(second[0], 0, 'Re-add must wait even when the controller query fails immediately')
            self.assertTrue(second[5] & PAD_READY)
            self.assertNotEqual(first[4], second[4])
            removed = listener.events('pad_remove')[-1]
            added = listener.events('pad_add')[-1]
            self.assertGreaterEqual(added['ms'] - removed['ms'], 180)
            self.assertFalse(added['duplicate'])

    def test_success_feeds_neutral_before_reporting_ready(self):
        with Listener() as listener:
            self.assertEqual(listener.events('pad_add'), [])
            state = listener.request(128)
            self.assertFalse(state[5] & PAD_READY)
            result = listener.request(129)
            self.assertEqual(result[0], 0)
            self.assertTrue(result[5] & PAD_READY)
            reports = listener.events('pad_report')
            self.assertGreaterEqual(len(reports), 5)
            self.assertGreaterEqual(reports[-1]['ms'] - reports[0]['ms'], 175)
            self.assertTrue(all(event['result'] == 0 and event['buttons'] == 0 and
                                [event[key] for key in ('lx','ly','rx','ry','l2','r2')] == [128,128,128,128,0,0]
                                for event in reports))

    def test_first_and_later_neutral_report_failure_are_errors(self):
        for attempt in (1, 3):
            with self.subTest(attempt=attempt), Listener(PADD_TEST_FAIL_REPORT_AT=attempt) as listener:
                result = listener.request(129)
                self.assertEqual(result[0], errno.EIO)
                self.assertFalse(result[5] & PAD_READY)
                self.assertEqual(result[4], -1)
                self.assertFalse(listener.request(128)[5] & PAD_READY)
                added = listener.events('pad_add')[0]['handle']
                removed = listener.events('pad_remove')
                self.assertEqual(len(removed), 1)
                self.assertEqual(removed[0]['handle'], added)
                self.assertEqual(removed[0]['result'], 0)
                self.assertEqual(len(listener.events('pad_add')), 1)

    def test_failed_cleanup_retains_handle_and_prevents_duplicate_add(self):
        with Listener(PADD_TEST_FAIL_REPORT_AT=1, PADD_TEST_FAIL_REMOVE_COUNT=2) as listener:
            first = listener.request(129)
            self.assertNotEqual(first[0], 0)
            self.assertFalse(first[5] & PAD_READY)
            self.assertGreaterEqual(first[4], 0, 'Failed cleanup must retain the handle for retry')
            second = listener.request(129)
            self.assertNotEqual(second[0], 0)
            self.assertFalse(second[5] & PAD_READY)
            self.assertEqual(second[4], first[4])
            self.assertEqual(len(listener.events('pad_add')), 1, 'No second add while removal still fails')
            third = listener.request(129)
            self.assertEqual(third[0], 0)
            self.assertTrue(third[5] & PAD_READY)
            self.assertNotEqual(third[4], first[4])
            self.assertEqual(len(listener.events('pad_add')), 2)
            self.assertTrue(all(not event['duplicate'] for event in listener.events('pad_add')))
            self.assertEqual([event['handle'] for event in listener.events('pad_remove')], [first[4]] * 3)

    def test_failed_cleanup_is_retried_on_exit(self):
        with Listener(PADD_TEST_FAIL_REPORT_AT=1, PADD_TEST_FAIL_REMOVE_COUNT=1) as listener:
            failed = listener.request(129)
            self.assertFalse(failed[5] & PAD_READY)
            self.assertGreaterEqual(failed[4], 0)
            self.assertEqual(listener.shutdown(), 0)
            removed = listener.events('pad_remove')
            self.assertEqual([event['handle'] for event in removed], [failed[4], failed[4]])
            self.assertEqual([event['result'] for event in removed], [errno.EIO, 0])

    def test_successful_add_with_negative_handle_is_rejected(self):
        with Listener(PADD_TEST_NEGATIVE_HANDLE=1) as listener:
            result = listener.request(129)
            self.assertEqual(result[0], errno.EIO)
            self.assertFalse(result[5] & PAD_READY)
            self.assertEqual(result[4], -1)
            self.assertEqual(listener.events('pad_report'), [])
            self.assertEqual(listener.events('pad_remove'), [])


if __name__ == '__main__':
    unittest.main()
