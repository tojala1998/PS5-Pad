Read-only running-title experiment

probe.c queries sceSystemServiceGetAppIdOfRunningBigApp and the initialized
sceLncUtilGetAppIdOfRunningBigApp / sceLncUtilGetAppTitleId pair. It takes three
samples and exits. It creates only its own diagnostic file with O_EXCL, never
replacing one, and does not launch, close or suspend apps or touch controllers.
Build with the PS5 Payload SDK and link libSceSystemService. The fixed output
path is /data/ps5pad-app-detection-20261116.jsonl; change to a fresh path before
an explicitly requested repeat so prior results remain intact.

Live result on firmware 13.60: LncUtil initialization succeeded, but both running
app calls returned -1 in all three samples. No title lookup was attempted without
a valid app id. The visible TV app at sampling is awaiting owner confirmation.
This is not proof that detection cannot work, nor proof that these functions
identify the truly focused app while Home/system UI overlays are visible.

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
