"""Power commands run only against the recording host backend, never a PS5."""
import errno,struct,unittest
from initialization_test import Listener,send,receive

class PowerOffTests(unittest.TestCase):
    def power(self,d):
        send(d.client,137,b'OFF!');kind,body=receive(d.client)
        self.assertEqual(kind,137);return struct.unpack('<i',body)[0]
    def test_idle_status_reconnect_and_service_exit_never_power_off(self):
        with Listener() as d:
            self.assertTrue(d.hello[4]&0x4000000)
            d.request(128);d.client.close();d.reconnect();d.request(128)
            self.assertFalse(d.events('power_off'))
            self.assertEqual(d.shutdown(),0);self.assertFalse(d.events('power_off'))
    def test_confirmation_required(self):
        with Listener() as d:
            for body in (b'',b'OFF',b'OFF!x',b'ON!!',b'\0'*4):
                send(d.client,137,body);kind,_=receive(d.client);self.assertEqual(kind,5)
            self.assertFalse(d.events('power_off'))
    def test_success_once_even_after_reconnect(self):
        with Listener() as d:
            self.assertEqual(self.power(d),0)
            self.assertEqual(self.power(d),errno.EALREADY)
            d.client.close();d.reconnect()
            self.assertEqual(self.power(d),errno.EALREADY)
            self.assertEqual(len(d.events('power_off')),1)
            self.assertFalse(d.events('pad_add'))
    def test_system_error_returned_without_retry(self):
        with Listener(PADD_TEST_POWER_OFF_ERROR=errno.EPERM) as d:
            self.assertEqual(self.power(d),errno.EPERM)
            d.request(128)
            self.assertEqual(len(d.events('power_off')),1)
if __name__=='__main__':unittest.main()
