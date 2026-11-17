"""Exercise the app updater's shutdown wire sequence against the actual host daemon."""
import socket
import struct
import unittest
from initialization_test import Listener, send, receive

class HelperUpdateTests(unittest.TestCase):
    def test_legacy_stop_path_removes_owned_pad_without_command_132(self):
        d=Listener()
        try:
            self.assertEqual(d.request(129)[0],0)
            handle=d.request(128)[4]
            send(d.client,6)
            kind,body=receive(d.client)
            self.assertEqual((kind,struct.unpack('<Ii',body)),(4,(0,0)))
            self.assertEqual(d.client.recv(1),b'')
            self.assertEqual(d.process.wait(timeout=3),0)
            self.assertEqual([e['handle'] for e in d.events('pad_remove')],[handle])
        finally:d.close()

    def test_release_ack_eof_and_port_closed_before_replacement(self):
        d=Listener()
        try:
            self.assertEqual(d.request(129)[0],0)
            handle=d.request(128)[4]
            result=d.request(132)
            self.assertEqual(result[0],0)
            self.assertEqual(result[4],-1)
            self.assertFalse(result[5]&1)
            # Use fragmented stop writes, just as TCP is permitted to deliver them.
            frame=struct.pack('<4sBBH',b'PMCP',1,6,0)
            d.client.sendall(frame[:3]);d.client.sendall(frame[3:])
            kind,body=receive(d.client)
            self.assertEqual((kind,struct.unpack('<Ii',body)),(4,(0,0)))
            self.assertEqual(d.client.recv(1),b'')
            self.assertEqual(d.process.wait(timeout=3),0)
            with self.assertRaises(ConnectionRefusedError):
                socket.create_connection(('127.0.0.1',d.port),timeout=1)
            self.assertEqual([e['handle'] for e in d.events('pad_remove')],[handle])
            self.assertEqual(len(d.events('pad_add')),1)
        finally:d.close()

    def test_failed_detach_leaves_listener_and_prevents_stop(self):
        d=Listener(PADD_TEST_FAIL_REMOVE_COUNT=1,PADD_TEST_REMOVE_ERROR=5)
        try:
            d.request(129)
            result=d.request(132)
            self.assertNotEqual(result[0],0)
            self.assertGreaterEqual(result[4],0)
            self.assertIsNone(d.process.poll())
            self.assertGreaterEqual(d.request(128)[4],0)
        finally:d.close()

if __name__=='__main__':unittest.main()
