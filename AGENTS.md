# Working boundaries

- Focus on PS5 Pad, its unsigned IPA pipeline and Kodi. VLC is deferred.
- Never modify the user's phone settings, security settings, Home Screen, folders or icon positions.
- After a successful requested app update, transfer the verified unsigned IPA to LiveContainer Documents over USB and verify the copied bytes. If the phone is unavailable, report that clearly.
- Transfer does not authorize signing or installation; those are separate steps.
- Do not exit Kodi or switch PS5 apps during tests without explicit authorization for that test.
- Keep Apple credentials, certificates, provisioning/pairing files and device data out of the repository.
- A standalone fresh install has been requested, with bundle ID com.uhnmeyker.ps5pad. Do not migrate or pre-create settings; first run must offer console scanning and selection.
- Test results distinguish local protocol/build checks from user-confirmed physical inputs. The 0.4.0 UIKit selector correction still requires an on-device touch test.
