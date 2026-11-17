"""Read-only app-state socket tests, including reconnect and unknown states."""
import json,struct,unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from initialization_test import Listener,send,receive
class AppStateTests(unittest.TestCase):
    def query(self,d,token):
        send(d.client,136,struct.pack('<I',token));kind,body=receive(d.client)
        self.assertEqual(kind,136);self.assertEqual(len(body),32)
        values=struct.unpack('<IiIii12s',body);self.assertEqual(values[0],token);return values
    def test_kodi_home_closed_and_unknown_never_create_controller(self):
        with TemporaryDirectory() as td:
            path=Path(td,'app-state')
            with Listener(PADD_TEST_APP_STATE_FILE=path) as d:
                self.assertTrue(d.hello[4]&0x2000000)
                for token,(state,flags) in enumerate([('kodi',15),('home',7),('closed',5),('unknown',0)],1):
                    path.write_text(state);reply=self.query(d,token)
                    self.assertEqual(reply[2],flags)
                    self.assertEqual(reply[5].rstrip(b'\0'),b'PPSA99420' if state=='kodi' else b'')
                self.assertFalse(d.events('pad_add'));self.assertFalse(d.events('launch_kodi'))
    def test_reconnect_reads_current_state_not_previous_session(self):
        with TemporaryDirectory() as td:
            path=Path(td,'app-state');path.write_text('kodi')
            with Listener(PADD_TEST_APP_STATE_FILE=path) as d:
                self.assertEqual(self.query(d,7)[2],15)
                d.client.close();path.write_text('closed');d.reconnect()
                self.assertEqual(self.query(d,8)[2],5)
    def test_malformed_request_rejected_without_mutation(self):
        with Listener() as d:
            send(d.client,136,b'');kind,body=receive(d.client);self.assertEqual(kind,5)
            self.assertFalse(d.events('pad_add'))
if __name__=='__main__':unittest.main()
