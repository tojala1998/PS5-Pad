# Public helper lifecycle contract

Every public PS5 Pad helper must remain replaceable by a much newer app. This is a small, permanent management interface; it does not require compatibility of every controller, media or keyboard command.

Keep the following PMCP v1 interface on TCP 9305, even if other protocols change:

- Greeting: the existing 28-byte HELLO frame, protocol version 1, the helper version at frame offset 10, and the management/control capability bit 0x10000 at offset 20. Increment the helper version when its behavior changes; never silently reuse a version for a different implementation.
- Stop request: exactly `50 4d 43 50 01 06 00 00`, with no payload, credentials, profile selection or controller initialization needed. This exits only PS5 Pad's helper; it must never shut down the console.
- Acceptance reply: the original ACK envelope (`50 4d 43 50 01 04 08 00`) with little-endian sequence zero and signed status zero. A nonzero status is a failure. The historical zero ACK means accepted, not proof that cleanup has already completed.
- Cleanup: cancel queued input and temporary keyboard activity, release held buttons, remove only the helper's owned virtual devices, close its client and listener, and exit. Preserve the single-instance port lock and do not affect physical controllers or unrelated payloads.

The replacement client waits for the ACK, clean EOF and a refused service connection before sending its bundled replacement. It must not treat a timeout or a successful upload alone as a successful replacement. It verifies the exact bundled helper version afterward. Matching versions reuse their session; different versions, older or newer, are replacement candidates.

Command 132 is an optional additional controller-removal confirmation. It is not a prerequisite for the permanent Stop path: publicly used helper 2.1 predates it, but command 6 already neutralizes and removes its controller at exit. The 2.1 source and live console logs verified this behavior on 2026-11-17. The currently published helper 2.7 also supports the same Stop bytes.

`service/stop_contract_test.py` uses frozen literal bytes rather than constants imported from the new implementation. It checks both an idle helper and a held-button session, successful exit, neutral input, owned-pad removal and listener closure against the host build. Both the IPA build and service CI run it. Do not update its fixtures to accommodate an incompatible management redesign; preserve a compatibility handler instead. This is a release requirement, not a claim that arbitrary future code is automatically correct.

Current recovery evidence: helper 2.1 received Stop, logged `pad_removed` with status 0 and `exit_requested` with code 0. Helper 2.7 was then manually loaded and its greeting verified. Normal future startup/replacement belongs in the iPhone app; this recovery did not alter autoload settings. The source of the older boot-loaded copy has not been established.
