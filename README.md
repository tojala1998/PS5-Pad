# PS5 Pad

A native iPhone remote for a jailbroken PS5, currently focused on Kodi. It sends controller input directly over the local network: no Remote Play, audio/video stream, or Windows relay.

[Download the unsigned 0.4.7 IPA](releases/0.4.7/PS5-Pad-0.4.7-unsigned.ipa)  |  [Build notes](docs/PS5-Pad-0.4.7-notes.txt)  |  [Controller ELF](service/prebuilt/padd-controller-2.4.elf)

<img src="docs/PS5-Pad-icon.png" width="130" alt="White PS5 Pad icon">

## Current build

The large swipe surface handles navigation and Cross/Select. Triangle, Square and Circle sit along its edges. The top row has L1, touchpad click, PS, Options and R1. The bottom row provides Kodi previous chapter, rewind, Play/Pause, fast-forward and next chapter.

During Kodi video playback, chapter buttons send D-pad Down/Up, rewind and fast-forward use Left/Right step seeking, and Play/Pause sends Options. These are Kodi's controller mappings, not a universal Sony media-remote hook. Files without chapters may use Kodi's large-seek fallback. VLC support is deferred.

Version 0.4.1 separates Local Network permission from scanning and offers Initialize Controller after adding a console. It retains the 0.4.0 touch-callback correction and the input queue that preserves quick presses through delayed acknowledgements. Build and local regression checks pass. The standalone 0.4.1 installation was verified over USB and its owner confirmed that it opens; **the new permission flow, scan timing and physical button behavior still need on-device confirmation**.

Version 0.4.2 fixes resuming with a connection prompt still open: stale prompts are dismissed so the app can reconnect and offer a fresh Initialize Controller prompt. Discovery and its address-entry form are preserved. The unsigned build, USB transfer and standalone 0.4.2 installation are verified; this resume scenario still needs on-device confirmation.

Version 0.4.3 clears stale success text during initialization, shows progress, handles initialization failures and labels the service connection separately from virtual-controller readiness. Service 2.2 adds an unconditional detach interval and verifies neutral reports before returning initialization success. Profile assignment remains a TV step; the owner still reported two attempts in 0.4.3. Its logs showed one initialization plus a duplicate service-load attempt, identifying a separate connection-flow problem. See the [build notes](docs/PS5-Pad-0.4.3-notes.txt).

Version 0.4.4 adds one-action initialization with a compact Service → Controller → Done progress strip. It checks the existing service, loads it at most once if needed, and initializes once. It automatically initializes after a successful status check reports no PS5 Pad virtual controller; this is not detection of physical-controller ownership. Pending work cancels on background, disconnect, console change or failure. Service 2.3 adds an explicit **Disconnect controller** command. Its standalone installation was verified over USB; the owner confirmed initialization and face-button feedback working in Kodi. The subsequent lock/resume report is addressed in 0.4.5.

Button feedback follows a matching, successful controller-report acknowledgment. Each face button (including the swipe pad's Cross) flashes only for its own registered press; repeated neutral/held reports do not retrigger feedback. The hit area stays fixed, and drag tracking uses the same bounds as the painted control. Short confirmed presses remain visible even when their release follows immediately. Confirmation means the service accepted the HID report, not proof that the TV profile or Kodi acted on it.

Version 0.4.5 automatically reconnects to the saved console on launch and unlock, reusing its existing virtual controller. Bounded foreground retries accommodate network wakeup; if the service is unavailable, it may load the bundled service once. Busy, unrecognized and permission-blocked services do not trigger loading. Only a fresh successful status reporting no pad allows automatic initialization. Returning to a healthy controller does not re-arm Initialize. The helper remains 2.3; no controller replacement is needed to deploy this app update. The owner installed 0.4.5 and reported both resume tests failing: the app stayed Offline/Paused. USB diagnostics showed zero automatic attempts, identifying a lifecycle-start problem addressed in 0.4.6.

Version 0.4.6 starts foreground connection work from the scene lifecycle and reconciles it after view setup. It removes the app-wide state gate and the cancellation-generation startup latch that could drop activation before any network attempt. Lifecycle diagnostics distinguish each process, deferred startup and canceled work. See the [0.4.6 notes](docs/PS5-Pad-0.4.6-notes.txt). Standalone 0.4.6 build 12 was verified over USB, and the owner confirmed both lock/unlock and closing/reopening reconnect automatically with Kodi responding. The latest diagnostics mark the controller reused, with one connection attempt and zero report failures.

A fresh installation opens Find your PS5 and checks Local Network access before enabling Scan Wi-Fi. Allow the iOS prompt, then scan, select a detected console and tap Add PS5. Access is confirmed by discovering a unique temporary Bonjour service; a timeout or failed connection never counts as permission granted. No console scan starts during the permission check.

Discovery checks the attached IPv4 subnet (the nearest /24 on larger networks). It prioritizes the saved address, alternates low and high addresses, checks up to 48 at once and stops at the first valid service reply. Manual entry is also available. The address is saved only after Add PS5. No settings or device data are packaged.

“PS5 Pad service available” means the app received a valid PMCP greeting with the PS5 Pad control capability from TCP port 9305. An open port alone is insufficient. A recognized busy-service reply appears separately. Discovery sends no input, initialization or app-launch commands; service availability does not establish controller ownership.

Version 0.4.7 and service 2.4 track controller assignment through the console's existing TCP 3232 log server. A physical controller assigned to our profile causes removal of only PS5 Pad's virtual controller. The phone stays disconnected until **••• → Turn On Controller**; a fresh app launch begins the saved-console flow. Until the console confirms profile assignment, only picker navigation is allowed. Monitoring loss releases our controller. This depends on the console log service and event format, not a universal ownership API. The new helper's standby startup and monitoring connection are verified on firmware 13.60; the owner confirmed physical-controller takeover works after installing 0.4.7. USB inspection verified standalone build 13. Full account synchronization, authenticated pairing and foreground-app detection are not implemented. Use only on a trusted LAN; the service accepts unauthenticated connections.

A small green bar pulses during connection/initialization, flashes when profile assignment confirms readiness, then disappears. The previous persistent progress strip is removed.

**••• → Keyboard…** provides manual text entry after opening a text field on the TV. Send supports 1–128 printable US-ASCII characters on a US layout and does not press Enter. A temporary keyboard is removed after typing, disconnection, handoff or a short traffic timeout; failed removal retries. Text is not logged or saved. The isolated backend typed correctly in Kodi on firmware 13.60, but the integrated UI still requires a live test. Automatic keyboard-popup detection remains unverified. See [research](docs/keyboard-research.md) and [0.4.7 notes](docs/PS5-Pad-0.4.7-notes.txt).

## Sleep and controller sessions

The PS5 service owns the virtual controller separately from the phone connection.
It continues neutral reports during phone sleep and has no ten-minute removal
timer. Leaving the app releases held input and closes its network connection.
**Disconnect controller** explicitly removes only PS5 Pad's controller after
the PS5 acknowledges the request; it leaves the service running.

iOS does not guarantee a callback when a suspended app is force-closed, and may
close network connections during suspension. Therefore loss of TCP or missed
heartbeats cannot reliably distinguish screen lock from force-quit. Preserving
sleep means the virtual controller may survive force-quit until explicitly
disconnected. No continuous background-execution or automatic force-quit cleanup
guarantee is claimed. See [Apple's networking clarification](https://developer.apple.com/forums/thread/840808)
and [termination callback documentation](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationwillterminate(_:)).

Neutral-report success is not proof that the console still routes input to the
pad. The owner reported a disconnect while the app was open. A bounded console
log read identified the old service's controller removal during an update and
the replacement's creation/assignment; it did not identify a later replacement
removal. A console-side inactivity policy has not been established or disabled.
No synthetic keep-awake button presses, console settings changes or guessed
power-control calls are used.

## Build an unsigned IPA on Windows

Requirements: WSL Ubuntu 24.04, LLVM 18 (`clang-18` and `ld64.lld-18`), a C compiler, Python 3, and a compatible iPhoneOS SDK. The tested SDK is iPhoneOS 16.5. No Apple Account or signing key is used to build.

```powershell
.\Build.ps1 -IosSdk 'C:\path\to\iPhoneOS16.5.sdk'
```

Linux/WSL equivalent:

```sh
bash tools/build.sh /path/to/iPhoneOS16.5.sdk
```

The script uses a fresh `work/` directory, runs input/wire tests, compiles with warnings treated as errors, validates the archive and writes the unsigned IPA and verification report to `dist/`.

## Transfer to an iPhone

The USB transfer needs an already trusted iPhone, LiveContainer, and a Python environment with `pymobiledevice3` installed. It copies the IPA into LiveContainer's Documents folder and reads it back to verify the bytes. It does not sign, install, launch apps, change phone settings or modify the Home Screen.

```powershell
.\Transfer-IPA.ps1 -Ipa .\releases\0.4.7\PS5-Pad-0.4.7-unsigned.ipa
# Or build and transfer:
.\Build.ps1 -IosSdk 'C:\path\to\iPhoneOS16.5.sdk' -Transfer
```

The default Python path matches the original Windows tool setup; pass `-Python` to `Transfer-IPA.ps1` for a different environment. Automatic discovery selects a single LiveContainer installation. The Python tool accepts `--bundle-id` if the device has multiple hosts. Existing files with different bytes are preserved.

Use SideStore separately to sign and update the app. The display name is PS5 Pad and the bundle identifier is `com.uhnmeyker.ps5pad`. This is a fresh app identity, separate from old QuietPad. Signing tools may append the development team identifier. A new Apple provisioning profile is required. No old settings are migrated.

## Console service

Upload `service/prebuilt/padd-controller-2.4.elf` to Payload Manager and load it if it is not already running. It requires the existing TCP 3232 log server for ownership monitoring, listens on TCP 9305, starts in standby and creates its controller only after an explicit Initialize request. It assumes the console is already jailbroken; neither the iPhone app nor the service performs a jailbreak.

The source and its original license are under `service/`. Build with [PS5 Payload SDK v0.43](https://github.com/ps5-payload-dev/sdk/releases/tag/v0.43):

```sh
make -C service PS5_PAYLOAD_SDK=/path/to/ps5-payload-sdk
make -C service check
```

The service derives from [leolobato/ps5-mcp](https://github.com/leolobato/ps5-mcp) at commit `3b3269fc6689aedb9b5cd438d52a486bbc395cac`; see its retained [AGPL-3.0 license](service/LICENSE). Native app sources, icon generation and local tests are under `app/`. The source archive contains no Apple credentials, certificates, pairing records or device backups.

Kodi mapping references: [PS5 input](https://github.com/VivaLaVent/PS5MC/blob/ps5mc-piers/xbmc/platform/ps5/input/PS5PadInput.cpp), [keyboard actions](https://github.com/VivaLaVent/PS5MC/blob/ps5mc-piers/system/keymaps/keyboard.xml).

The top Kodi shortcut uses the unmodified [official Kodi logo](https://kodi.wiki/view/File:Logo-transparent_bare_256px.png); see `app/assets/KodiLogo-source.txt`. PS5 Pad is an independent project.
