# PS5 Pad

A native iPhone remote for a jailbroken PS5, currently focused on Kodi. It sends controller input directly over the local network: no Remote Play, audio/video stream, or Windows relay.

[Download the unsigned 0.4.0 IPA](releases/0.4.0/PS5-Pad-0.4.0-unsigned.ipa) Â· [Build notes](docs/PS5-Pad-0.4.0-notes.txt) Â· [Controller ELF](service/prebuilt/padd-controller-2.1.elf)

<img src="docs/PS5-Pad-icon.png" width="130" alt="White PS5 Pad icon">

## Current build

The large swipe surface handles navigation and Cross/Select. Triangle, Square and Circle sit along its edges. The top row has L1, touchpad click, PS, Options and R1. The bottom row provides Kodi previous chapter, rewind, Play/Pause, fast-forward and next chapter.

During Kodi video playback, chapter buttons send D-pad Down/Up, rewind and fast-forward use Left/Right step seeking, and Play/Pause sends Options. These are Kodi's controller mappings, not a universal Sony media-remote hook. Files without chapters may use Kodi's large-seek fallback. VLC support is deferred.

Version 0.4.0 corrects the Objective-C UIKit touch callback names that prevented the custom face and top-row controls from responding. It retains the input queue that preserves quick presses through delayed acknowledgements. Build and local regression checks pass; **physical input behavior on the iPhone/PS5 still needs verification for this release**.

A fresh installation opens Find your PS5. Scan Wi-Fi, select a detected console and tap Add PS5. Scanning recognizes the running PS5 Pad service; it does not pair with PSN, use Remote Play, or start a controller. Start the service first and allow the iOS Local Network prompt. If the first scan finishes while the prompt is open, scan again. Discovery checks the attached IPv4 subnet (the nearest /24 on larger networks); manual entry is available. The address is saved only after Add PS5. No settings or device data are packaged.

Turning on the virtual controller is explicit. Full account synchronization, authenticated pairing and foreground-app detection are not implemented. The service is for a trusted LAN and currently accepts unauthenticated connections.

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
.\Transfer-IPA.ps1 -Ipa .\releases\0.4.0\PS5-Pad-0.4.0-unsigned.ipa
# Or build and transfer:
.\Build.ps1 -IosSdk 'C:\path\to\iPhoneOS16.5.sdk' -Transfer
```

The default Python path matches the original Windows tool setup; pass `-Python` to `Transfer-IPA.ps1` for a different environment. Automatic discovery selects a single LiveContainer installation. The Python tool accepts `--bundle-id` if the device has multiple hosts. Existing files with different bytes are preserved.

Use SideStore separately to sign and update the app. The display name is PS5 Pad and the bundle identifier is `com.uhnmeyker.ps5pad`. This is a fresh app identity, separate from old QuietPad. Signing tools may append the development team identifier. A new Apple provisioning profile is required. No old settings are migrated.

## Console service

Upload `service/prebuilt/padd-controller-2.1.elf` to Payload Manager and load it if it is not already running. It listens on TCP 9305, starts in standby and creates its controller only after an explicit Initialize request. It assumes the console is already jailbroken; neither the iPhone app nor the service performs a jailbreak.

The source and its original license are under `service/`. Build with [PS5 Payload SDK v0.43](https://github.com/ps5-payload-dev/sdk/releases/tag/v0.43):

```sh
make -C service PS5_PAYLOAD_SDK=/path/to/ps5-payload-sdk
make -C service check
```

The service derives from [leolobato/ps5-mcp](https://github.com/leolobato/ps5-mcp) at commit `3b3269fc6689aedb9b5cd438d52a486bbc395cac`; see its retained [AGPL-3.0 license](service/LICENSE). Native app sources, icon generation and local tests are under `app/`. The source archive contains no Apple credentials, certificates, pairing records or device backups.

Kodi mapping references: [PS5 input](https://github.com/VivaLaVent/PS5MC/blob/ps5mc-piers/xbmc/platform/ps5/input/PS5PadInput.cpp), [keyboard actions](https://github.com/VivaLaVent/PS5MC/blob/ps5mc-piers/system/keymaps/keyboard.xml).

The top Kodi shortcut uses the unmodified [official Kodi logo](https://kodi.wiki/view/File:Logo-transparent_bare_256px.png); see `app/assets/KodiLogo-source.txt`. PS5 Pad is an independent project.
