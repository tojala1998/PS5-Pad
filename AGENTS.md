# Working boundaries

- Use uhnmeyker for app identifiers; tojala1998 is the GitHub account only.
- Do not automate the iPhone interface with screenshots or taps. Hand UI-only steps to the user and wait for confirmation, then verify through USB/command-line tools.

- Focus on PS5 Pad, its unsigned IPA pipeline and Kodi. VLC is deferred.
- Never modify the user's phone settings, security settings, Home Screen, folders or icon positions.
- Publish updates through the GitHub-backed SideStore source. Do not automatically transfer IPAs to LiveContainer Documents; the user stopped using that update route. USB transfer is opt-in only when explicitly requested.
- Transfer does not authorize signing or installation; those are separate steps.
- Do not exit Kodi or switch PS5 apps during tests without explicit authorization for that test.
- Keep Apple credentials, certificates, provisioning/pairing files and device data out of the repository.
- A standalone fresh install has been requested, with bundle ID com.uhnmeyker.ps5pad. Do not migrate or pre-create settings; first run must offer console scanning and selection.
- Test results distinguish local protocol/build checks from user-confirmed physical inputs. The 0.4.0 UIKit selector correction still requires an on-device touch test.

- Every published app update must include the refreshed source.json and matching versioned IPA/report in the same commit. tools/build.sh stages these after verification. Preserve source identifier com.uhnmeyker.ps5pad.source and app identifier com.uhnmeyker.ps5pad; never publish a newer feed pointing to an unpublished IPA.
