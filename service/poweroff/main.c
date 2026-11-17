/* One-shot orderly full shutdown, independent of the controller/profile service.
 * Reference: Marice/ps5-homeassistant src/power.c at 92dea18d4efca5cb792ab68a5d8721458549086a.
 * No HID, profile initialization, standby, ShellCore, or raw-reboot fallback.
 * Only delivered after the app's explicit destructive confirmation. */
int sceSystemStateMgrTurnOff(void);
int qp_request_full_power_off(void) { return sceSystemStateMgrTurnOff(); }
#ifndef QP_POWER_TEST
int main(void) { return qp_request_full_power_off() ? 1 : 0; }
#endif
