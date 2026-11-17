Read-only running-title experiment

probe.c queries sceSystemServiceGetAppIdOfRunningBigApp and the initialized
sceLncUtilGetAppIdOfRunningBigApp / sceLncUtilGetAppTitleId pair. It takes three
samples and exits. It creates only its own diagnostic file with O_EXCL, never
replacing one, and does not launch, close or suspend apps or touch controllers.
Build with the PS5 Payload SDK and link libSceSystemService. The fixed output
path is /data/ps5pad-app-detection-20261116.jsonl; change to a fresh path before
an explicitly requested repeat so prior results remain intact.

Live results on firmware 13.60:
- Initial sample: LncUtil initialization succeeded; both running-app calls
  returned -1 three times. The owner selected "PS5 Home or another app", so
  that initial screen context is not precise enough to validate Home behavior.
- Repeat with the owner confirming Kodi open: both APIs returned app id 40984
  in all three samples; GetAppTitleId succeeded and returned PPSA99420 each time.
  No app launch, switch, controller or input operations were sent.

Kodi running-title detection is now verified on this console. VLC and transitions
between the app, Home and system overlays remain unverified. A running title is
not yet proven to be the truly focused input target in every overlay state.
The test result does not yet enable automatic control profiles in the iOS app.

Plan for production, after verifying actual title IDs and focus transitions:
- Report app id/title id plus explicit known/unknown status through the helper.
- Map Kodi PPSA99420 and VLC PPSA85300 to separate control profiles.
- Keep a generic/manual profile for unknown apps and failed queries.
- Verify each media mapping against the app, not just its title id.
- Poll read-only; never launch/switch apps or take controller ownership to detect.

Public implementation reference (query calls only):
https://github.com/itsPLK/ps5-payload-manager/blob/main/src/ps5_launcher.c
SDK exported function names:
https://github.com/john-tornblom/ps5-payload-sdk/blob/master/sce_stubs/libSceSystemService.c
