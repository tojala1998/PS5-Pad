# System-wide keyboard research

Investigated on November 16, 2026. Version 0.4.9 includes a manual live keyboard
editor through the three-dot menu and service 2.5. Automatic keyboard-open/close
detection remains unverified. The isolated backend test succeeded on firmware
13.60, but the owner reported no text from the integrated 0.4.7 batch sender.
The 0.4.9 persistent editor has passed host tests and awaits TV confirmation.
See [0.4.9 notes](PS5-Pad-0.4.9-notes.txt). The contextual-detection design below
remains a proposal, not shipped behavior.

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

Upstream evidence alone does not prove compatibility with another firmware or
typing in Kodi/Prospero. HID key reports also depend on the console's keyboard layout and
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

## Separate live keyboard test

The isolated [keyboard probe](../experiments/keyboard-probe/README.txt) reuses
ProsperoSunshine's pinned keyboard implementation and carries GPL-3.0-only
notices. Its startup and STATUS commands create no input device. It listens on
TCP 9306, expires after five minutes, and creates a keyboard only after an explicit
OPEN command. Input is bounded to printable US-ASCII; disconnect and idle timeout
release and remove only its own keyboard. It neither replaces the controller
service nor calls video/audio, Remote Play, app-launch or ShellUI attachment code.

The owner's console reported firmware **13.60**, raw SDK value `0x13600007`.
The owner opened an empty Kodi text field. The probe sent a 13-character dotted
IPv4 address without Enter; every report returned success, and the owner confirmed
the exact text appeared. Keyboard removal and STOP both returned success.

This establishes direct real keyboard input in that Kodi field on this console.
Other apps, layouts, Unicode, text replacement and automatic keyboard-open/close
detection remain unverified. No firmware hooks or console settings were changed.

Two named files in `/system_ex/common_ex/lib/` were then copied using existing FTP
read access: `Sce.PlayStation.Ime.dll.sprx` and `Sce.Vsh.Ime.dll.sprx`. Both contain
CLI metadata signatures. Local metadata inspection can identify candidate methods
without executing the assemblies, attaching ShellUI or changing process credentials.
Neither system file is included in this repository or the source deliverables.

## Offline metadata findings on firmware 13.60

The two local copies were inspected with .NET `MetadataReaderProvider`, without
loading the assemblies or reading/executing their method bodies. The parser
validated the embedded metadata stream bounds and decoded type ownership,
member names and signatures. `Sce.PlayStation.Ime` contains 113 types, 268 methods
and eight properties; `Sce.Vsh.Ime` contains five types, 19 methods and three
properties. Neither assembly declares CLR events. The private firmware files and
full metadata inventory remain outside this repository.

The following are actual metadata declarations in namespace
`Sce.PlayStation.Core.Ime`, not verified runtime behavior:

| Declaration | What it establishes and what remains unknown |
| --- | --- |
| `ImeClient.Open(ImeParam)` and `Close()` | Concrete lifecycle method candidates. Their call sites and behavior were not examined. |
| `ImeClient.GetShowWindowType(out ImeWindowType)` | An instance method returning a window-type enum. The class has a private `UInt64 imeClientAccessor`; there is no evidence that another process can use this method to query the console's active keyboard. |
| `ImeWindowType.Default`, `Inline`, `Dialog` | Actual enum member names. None is an established global visible/hidden flag. |
| `ImeParam.Handler : ImeEventHandler`, whose `Invoke` accepts `ImeEvent` | A callback mechanism exists for an IME client. It is not a discovered external subscription API. |
| `ImeEventId.Open`, `PressClose`, `Abort`, `ImeEventTerminate`, `ImeEventExitFocus`, `ImeEventEnterFocusToKeyboard`, `ImeEventChangeWindowType` | Actual enum member names that identify lifecycle candidates. Event delivery, ordering and interpretation remain unverified. |
| `IOskDialog.Open(ImeDialogPositionInfo)` and `Close()` | Abstract interface declarations, not concrete hook implementations. |
| `openStateControl.resistOpenInfo(...)` and `unResistOpenInfo(UInt64)` | The internal static type has a private `openList` of accessor/parameter records. No public state/count accessor was found, and its scope across processes or managed runtimes is unknown. |

`Sce.Vsh.Ime` mainly exposes voice-input components. Its `VoiceInputStatus` does
not establish whether the on-screen keyboard is visible. The distinct
`Sce.Vsh.ShellUI.Ime.dll.sprx` from the public module inventory has not been
inspected in this offline pass.

These findings narrow the search, but **runtime global keyboard visibility is
still unverified**. Successful HID typing does not validate any of these lifecycle
candidates, and none is currently wired into PS5 Pad.

## External observation boundary and next investigation

No reviewed implementation establishes global IME visibility through an existing
read-only external observer without Remote Play, process injection, attachment
or credential changes. Static files can reveal declarations, but do not change
with the current keyboard session. Foreground application and generic system-UI
overlay state cannot distinguish an IME from other overlays. The SDK's
[`sceImeDialogGetStatus` stub](https://github.com/ps5-payload-dev/sdk/blob/8816aee4cd88fc47b07819d2b6f4769c095a074b/sce_stubs/libSceImeDialog.c)
establishes an export name, not the semantics of a cross-process query.

The SDK's
[`mdbg_copyout`](https://github.com/ps5-payload-dev/sdk/blob/8816aee4cd88fc47b07819d2b6f4769c095a074b/crt/mdbg.c)
does not ptrace-attach or stop the target, but temporarily changes the caller's
authid and capabilities. Calling it is therefore not a zero-security-change
observation. The
[`kernel_proc_copyout` implementation](https://github.com/ps5-payload-dev/sdk/blob/8816aee4cd88fc47b07819d2b6f4769c095a074b/crt/kernel_procio.c)
tries that helper first; switching to this wrapper does not avoid that behavior.
Neither route is part of the current investigation or production design.

The next bounded research step is to identify the remaining ShellUI IME assembly
through existing permitted file access, if available, and inspect its metadata
offline for concrete lifecycle implementations or references to an externally
observable interface. Candidate declarations then need implementation evidence
and controlled open/close observations before they can drive a feature. If no
such external interface is found, record automatic detection as unsupported;
do not substitute guessed visibility or silently introduce a ShellUI agent.

## Required production keyboard lifetime

These are design requirements, not implemented production behavior. PS5 Pad must
only own a virtual keyboard during an active keyboard session:

- Require all three conditions: the iPhone app is active in the foreground, its
  current direct LAN connection is live, and a supported observer freshly reports
  that the console keyboard is visible. Unknown, stale or unsupported visibility
  must not create a keyboard or present the contextual editor.
- Create the virtual keyboard only for that session. A scan, service connection,
  controller initialization or idle app must not create one. Session identifiers
  must distinguish newly opened keyboards from expired or reconnected sessions;
  reject delayed reports from an old session.
- On observed keyboard close, cancellation, visibility becoming unknown, app
  backgrounding, connection loss, explicit disconnect, lease expiry or service
  shutdown: send an all-keys-up report, remove only this session's virtual
  keyboard, invalidate its session and dismiss the iPhone editor. Cleanup must be
  idempotent and must not remove physical devices or another service's devices.
- Enforce a short lease on the console independently of iOS cleanup. A proposed
  starting point is a two-second monotonic deadline refreshed every 500 ms only
  while all eligibility conditions remain true. The server must check expiry
  even when a client goes silent, is killed or sends a partial request; network
  handlers must not block that cleanup. These timings require testing on this
  console before they become a compatibility promise.
- A disconnect or expired lease must release held modifiers and ordinary keys
  even if the last key-up report was lost. Graceful shutdown and lease expiry
  need separate checks; cleanup after a payload crash must not be assumed from
  the successful explicit STOP test.
- Do not leave a persistent keyboard, override the user's controller permanently,
  disable physical input or change console settings. Reconnection requires fresh
  visibility and a new eligible session, rather than restoring stale ownership.
- Observe session state only. Do not read or log the console field's text; do not
  retain typed content in diagnostics. Text supplied by the user for delivery is
  distinct from reading an existing console text field.

Before release, verify normal close/cancel, app backgrounding, connection loss,
client termination, expired/delayed session messages and service shutdown while
a modifier is held. Confirm that keys are released, the owned keyboard disappears
and the physical controller remains usable. These checks must use a disposable
field in the current app and must not switch applications without authorization.
