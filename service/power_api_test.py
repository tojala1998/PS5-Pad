"""Source-only regression guard. A physical PS5 test is still required."""
from pathlib import Path

source = Path("payload/system_ps5.c").read_text()
assert "int sceSystemStateMgrTurnOff(void);" in source
assert "int system_power_off(void) { return sceSystemStateMgrTurnOff(); }" in source
assert "sceShellCoreUtilRequestShutdown" not in source
assert "reboot(" not in source
print("PASS: full power-off API is used without a ShellCore or reboot fallback.")
