# System-wide keyboard research

Investigated on November 16, 2026. This is a feasibility record, not a claim that
PS5 Pad currently supports text entry. Version 0.4.1 contains no keyboard changes.

The requested behavior is an iPhone keyboard that appears when the console opens
its text keyboard, across Kodi, VLC, Prospero and other apps. The connection must
remain direct LAN, with no Remote Play session, video/audio stream or PC relay.

## Findings

Two independent capabilities are needed: send real text/key input, and detect the
console's keyboard session opening and closing. Existing projects provide the
first. No PS5 implementation of the second, independent of Remote Play, has been
verified in this investigation.

| Project | Actual implementation | Use for PS5 Pad |
| --- | --- | --- |
| ProsperoSunshine | Real virtual keyboard via `/dev/hid`, with upstream evidence of typing into the PS5 browser's active text field on firmware 13.00 | Best candidate for the input backend; its small keyboard module does not depend on video streaming |
| PS5Upload | Separate `ps5u-vinput` process using `libSceKeyboard`; upstream measured HID events on firmware 13.60 | Useful alternative implementation and device-lifetime handling; its automatic keyboard open/close feature uses Remote Play |
| PS4 ThumbGrid IME | GoldHEN plugin hooks the calling game's IME lifecycle and exchanges session state with a ShellUI overlay | Concrete reference for lifecycle detection, but PS4-specific and not a ready PS5 payload |
| Ghostpad / Ghostcontrol / PS5-KBM-Bridge | Virtual controller input, physical keyboard-to-controller mappings, or the project's own text-entry widgets | These do not establish detection or remote typing into another PS5 app's system keyboard |
| PS5 MCP | `type_text` / `close_keyboard` are Remote Play operations | Not usable under this project's transport requirements |

## Preferred input implementation

ProsperoSunshine's [`kbm.c`](https://github.com/Darkatek7/ProsperoSunshine/blob/6e33be0adbccf579e4c14c432d4bb2becbb333c9/src/platform/ps5/kbm.c)
implements a keyboard independently of its streaming components. Its
[research record](https://github.com/Darkatek7/ProsperoSunshine/blob/6e33be0adbccf579e4c14c432d4bb2becbb333c9/docs/re/keyboard-mouse.md)
documents creation/removal, HID reports and observed browser text input on 13.00.
The module is GPL-3.0-only. Reuse must retain its license and attribution and ship
corresponding source; the existing PS5 Pad service is AGPL-3.0.

Upstream observations relevant to a port: wait after creating the keyboard before
its first report, keep presses long enough to be sampled, and release all held
keys on disconnect. It reports that calling `sceKeyboardInit` from its probe
crashed that payload; the raw-device implementation avoids that path.

This evidence does not prove compatibility with the user's firmware or typing in
Kodi/Prospero. HID key reports also depend on the console's keyboard layout and
are not arbitrary Unicode text replacement. The first test should cover digits,
dots, colons, slashes, letters, Shift, Backspace and Enter in a disposable field.

PS5Upload's [companion design](https://github.com/phantomptr/ps5upload/blob/008acea51fe0d026b1365d1213f2142f10afee4b/payload/vinput/README.md)
and [`vinput_dev.c`](https://github.com/phantomptr/ps5upload/blob/008acea51fe0d026b1365d1213f2142f10afee4b/payload/src/vinput_dev.c)
provide an alternative using exported Sony functions. Its 13.60 measurements
prove delivery to a keyboard reader; the code explicitly distinguishes that
from acceptance by games. The companion is isolated because initialization
previously hung its main helper. It includes a two-second release timeout and
cleanup for virtual devices left behind by a terminated process.

## Automatic appearance remains separate

PS5Upload's [`rp_stream/keyboard.rs`](https://github.com/phantomptr/ps5upload/blob/008acea51fe0d026b1365d1213f2142f10afee4b/engine/crates/ps5upload-core/src/rp_stream/keyboard.rs)
uses Remote Play control messages for keyboard-open, text-change and close events.
Reusing those messages would introduce a Remote Play session and does not meet
this project's requirements.

The [ThumbGrid source](https://github.com/Zenalios/ps4-thumbgrid-ime/blob/9e4fbc9f39f207ce4f08f1ec635bca5fa5bb90f1/src/ime_hook.c)
hooks `sceImeDialogInit`, `GetStatus`, `GetResult` and `Term` inside a PS4 game.
Its [architecture](https://github.com/Zenalios/ps4-thumbgrid-ime/blob/9e4fbc9f39f207ce4f08f1ec635bca5fa5bb90f1/README.md)
depends on GoldHEN game plugins and a PS4 ShellUI overlay. It is an implementation
reference, not proof that the same hooks can be installed across native PS5 apps.

The PS5 SDK's `sceImeDialogGetStatus` export and Kodi's local IME state do not by
themselves establish a global query that a separate payload can call. Symbol
names, emulator stubs and an unrelated system-overlay flag must not be treated
as a working detector. Apps with their own custom keyboards also need separate
consideration.

A [PS5 module inventory](https://github.com/buzzer-re/playstation_research_utils/blob/c0d7f7acb8f421b4b8ae3ee4766de48f3371d5a7/sce_ui_experiments/README.md)
identifies `Sce.Vsh.Ime.dll.sprx`, `Sce.Vsh.ShellUI.Ime.dll.sprx` and
`Sce.PlayStation.Ime.dll.sprx` in ShellUI. These are concrete places to inspect for
lifecycle events, not known callable detection APIs.
[Kabuki](https://github.com/stupiditytries/kabuki-ps5/blob/187180b39c5490c1cbc1ed5979bd8d8f9ea6e9a1/docs/ARCHITECTURE.md)
provides PS5 ShellUI loader/worker and managed-method infrastructure, with
upstream testing on 13.20 and GPL-3.0-or-later licensing. It does not implement a
keyboard detector. Any reuse needs firmware validation and attribution.
PS5Upload's [focus-probe notes](https://github.com/phantomptr/ps5upload/blob/008acea51fe0d026b1365d1213f2142f10afee4b/payload/include/focus_probe.h)
document UI freezes from attaching to ShellUI with ptrace; repeated attachment
must not be used as a casual polling strategy. A future observer should report
session state without reading or logging the text entered by the user.

## Implementation gates

1. Read the actual console firmware and identify supported keyboard entry points.
2. Build an isolated keyboard test using the documented implementation, retaining
   upstream notices. It must create no controller, change no active app, and send
   no text until an explicit test command.
3. Have the owner open a disposable text field in the current app, then verify
   input and cleanup on that console. No phone UI automation is needed.
4. Establish an observable PS5 IME lifecycle signal. Test open, close, cancellation,
   app exit and reconnection before using it to present the iPhone keyboard.
5. Extend the existing protocol with separate supported-input and supported-detection
   capabilities. Unsupported or unknown state must remain explicit; it must never
   trigger a guessed keyboard popup. Then add the contextual iOS text editor.

No replacement ELF, firmware hooks, console settings changes or experimental
keyboard input were deployed during this research.
