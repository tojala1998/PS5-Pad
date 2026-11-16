uhnmeyker PS5 keyboard probe 0.1.0

Experimental, isolated console-side keyboard input test. It is not PS5 Pad's
production controller service and does not implement keyboard-popup detection.
The build process itself uses host tests. A separate console test is recorded below.

Loading the ELF only opens TCP 9306 and reads the firmware number. It does not
create a keyboard or send input. The process exits after five minutes. Each client
has a five-second idle deadline; partial commands do not keep it alive. A created
keyboard is released and removed when the connection ends, times out or stops.
Only the handle created by this instance is removed. No controller, mouse,
application launch, ShellUI attach, settings or security operations are used.

The test server accepts unauthenticated commands on the console's network
interfaces while running, like the existing controller service. Use only on the
trusted local network. It is an experiment rather than a persistent service.

CLI (Windows Python or WSL; only standard-library dependencies):

  python ps5-keyboard-probe-client.py CONSOLE_IP status
  python ps5-keyboard-probe-client.py CONSOLE_IP open-test
  python ps5-keyboard-probe-client.py CONSOLE_IP type --text "192.168.0.10:8080/test"
  python ps5-keyboard-probe-client.py CONSOLE_IP key --key BACKSPACE
  python ps5-keyboard-probe-client.py CONSOLE_IP key --key ENTER
  python ps5-keyboard-probe-client.py CONSOLE_IP stop

STATUS is read-only. open-test explicitly creates a keyboard, waits 150 ms, and
removes it. type/key explicitly create a keyboard, send the requested input and
remove it, all in one connection. Use a disposable field that the owner has
opened. TYPE never automatically presses Enter. The text is not logged or echoed
by the server/client; shell command history may still contain a supplied argument.

At most 128 printable US-ASCII characters are accepted. The entire string is
validated before its first key. Other keyboard layouts, Unicode and arbitrary
text replacement are unsupported. Each key is held for 40 ms, followed by a
40 ms release interval. Keyboard creation has a 150 ms settling interval.

Wire format: newline-terminated uppercase commands; one persistent client.
The first reply and STATUS contain JSON with raw firmware_hex, probe version,
keyboard_open, supported_input="experimental", keyboard_detection=false,
idle/total timeouts and remaining lifetime. Firmware is left as the SDK's raw
hex value; it is not decoded into a claimed compatibility version.

Commands: STATUS, OPEN, TYPE <hex bytes>, KEY BACKSPACE|ENTER|ESCAPE,
RELEASE, CLOSE, QUIT (this client), STOP (whole probe). Replies contain result,
error code and accepted key count, never the entered text. This identifies the
service; the greeting is not authentication or proof that typing is supported.

Build: WSL Ubuntu, make, C compiler, unzip, Python3, the existing SDK v0.43 zip.
  bash build.sh /path/to/ps5-payload-sdk-v0.43.zip
build.sh extracts the SDK to a temporary directory, compiles the console ELF,
runs local socket tests against a fake backend and verifies that unused mouse
code was removed by the linker. It never contacts a console or iPhone.
With an already extracted SDK, use:
  make PS5_PAYLOAD_SDK=/path/to/ps5-payload-sdk all check

Validation: host tests cover read-only startup/STATUS, explicit-open requirement,
whole-string validation and bounds, ASCII HID mapping, key/creation delays,
neutral releases, disconnect cleanup, partial-command idle timeout and STOP.
Host tests alone do not establish compatibility or visible text input on a real PS5.

Live validation, November 16, 2026: on PS5 firmware 13.60 (0x13600007), the
payload created a keyboard and sent a 13-character dotted IPv4 address into an
empty Kodi field opened by the owner. All reports succeeded, and the owner
confirmed the exact text appeared. No Enter was sent. Keyboard removal and STOP
both returned success. No controller service was replaced or app switched.
This validates that one Kodi text field; it does not establish other apps,
keyboard layouts, Unicode or automatic keyboard-popup detection.

Upstream evidence: ProsperoSunshine documents direct browser text input on
firmware 13.00. The separate Kodi test above adds evidence on 13.60; Prospero
and other text fields remain unverified.
https://github.com/Darkatek7/ProsperoSunshine/blob/6e33be0adbccf579e4c14c432d4bb2becbb333c9/docs/re/keyboard-mouse.md

License: GPL-3.0-only. See LICENSE and THIRD_PARTY.txt. The source archive contains
the corresponding source and pinned upstream files; no Sony modules are included.
