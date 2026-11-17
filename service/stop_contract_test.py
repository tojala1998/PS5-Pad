"""Frozen release contract: deliberately do not import current protocol constants.

Run against current host builds and archived public helper host builds.
This only uses loopback and fake controllers; never touches a PS5.
"""
import socket
import struct
import unittest
from initialization_test import Listener
from smoke_test import read_exact

class FrozenStopContract(unittest.TestCase):
    def test_original_wire_stops_and_cleans_owned_controller(self):
        d=Listener()
        try:
            self.assertEqual(d.hello[0],1)
            self.assertTrue(d.hello[4]&0x10000)
            self.assertEqual(d.request(129)[0],0)
            # Hold Cross; STOP must neutralize it and remove only our own pad.
            frame=b'PMCP\x01\x02\x1c\x00'+struct.pack('<II4B16x',1,0x4000,128,128,128,128)
            d.client.sendall(frame)
            self.assertEqual(bytes(read_exact(d.client,16)),b'PMCP\x01\x04\x08\x00'+struct.pack('<Ii',1,0))
            d.client.sendall(b'PMCP\x01\x06\x00\x00')
            # ACK means accepted, not cleanup completed. Wait for EOF and exit.
            self.assertEqual(bytes(read_exact(d.client,16)),b'PMCP\x01\x04\x08\x00'+bytes(8))
            self.assertEqual(d.client.recv(1),b'')
            self.assertEqual(d.process.wait(timeout=3),0)
            events=d.events();removals=[e for e in events if e['call']=='pad_remove']
            self.assertEqual(len(removals),1)
            reports=[e for e in events if e['call']=='pad_report']
            self.assertTrue(any(e['buttons']==0x4000 for e in reports))
            self.assertEqual(reports[-1]['buttons'],0)
            self.assertEqual(removals[0]['handle'],reports[-1]['handle'])
            with self.assertRaises(ConnectionRefusedError):
                socket.create_connection(('127.0.0.1',d.port),timeout=1)
        finally:d.close()

    def test_original_wire_stops_without_a_profile_or_controller(self):
        d=Listener()
        try:
            d.client.sendall(b'PMCP\x01\x06\x00\x00')
            self.assertEqual(bytes(read_exact(d.client,16)),b'PMCP\x01\x04\x08\x00'+bytes(8))
            self.assertEqual(d.client.recv(1),b'')
            self.assertEqual(d.process.wait(timeout=3),0)
            self.assertFalse(d.events('pad_add'))
        finally:d.close()

if __name__=='__main__':unittest.main()
