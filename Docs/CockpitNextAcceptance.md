# Commander cockpit next acceptance

Prepared 2026-09-08 from LM `9016960683efabb491dfed16f10ea3ef90196d01` and LMKit `3ad1a999ff17aea859eaea5750f1c65e66fad673`. ACA integration and CommanderPanels are in progress; neither is accepted by this document. Refresh exact revisions and app hashes after reviewing/merging both deliveries. Keep AGC/LMCore pinned to `b3f15533db335ee882dc07401790c93010809e8f` unless a separately reviewed change requires otherwise.

## Merge sequence

1. Review ACA delivery for actual imported pivot mapping, fixed-housing isolation, targeting identity and neutral-on-release/cancellation. Reconcile its provisional mount against existing calibrated optics and forward instrument positions.
2. Review CommanderPanels source evidence, authored openings, measured clearance report and separate confidence labels. Package resources in LMKit using coordinator-owned APIs/tools/tests, preserving original history and source files. The worker owns only its asset component directory.
3. Install accepted panels in LM optional assembly, replacing the corresponding omitted backing without duplicate instruments or controls. Verify native resources and combined assembly/input tests serially using the exact merged source and pinned dependencies. Capture neutral and full-travel ACA, front, side and calibrated-eye views.
4. Only after those checks, build the same accepted code for the physical Vision Pro and record the actual device result separately.

## Physical session

Use a real P64 session with scripted validation inputs disabled. Record exact LM/LMKit/AGC revisions, executable hashes, device/OS, entry/recenter pose, input method and observations. Use the optional assembly flag and the accepted worker's actual ACA activation behavior.

- Confirm one active DSKY, one FDAI and one ACA, with no leftover procedural targets. Check panel boundaries and instrument faces from the calibrated eye and normal small head movements. Record clipping, glare, unreadable legends and uncomfortable reach.
- Execute the existing `Docs/Validation/InstrumentInteraction/HeadsetChecklist.md` against these new exact revisions: V16 N36, adjacent keys, PRO completion/release and cancellation, live lamp test and FDAI motion. Count actual completed events; hover must not dispatch.
- Operate each mapped ACA axis in both directions. Verify signs against the accepted mapper contract and live session input, with independent moving pivots and stationary housing. Check combined-axis motion and declared limits. Record actual input values and resulting simulation response; model deflection alone is insufficient.
- Release a drag, cancel a gesture, exit the cockpit during actuation and stop/restart the session. Verify every axis returns to neutral and no late event reapplies it. Check DSKY selection near the ACA does not actuate the controller.
- Observe full travel against panel/shell geometry; distinguish visible clearance from an engineering-qualified fit. Test readability/reach at native scale rather than enlarging instrument geometry to pass.
- Record stereo comfort and actual frame-time/memory measurements if available; do not derive performance or comfort acceptance from screenshots or simulator tests.

TTCA is an API audit in this assignment; unsupported translation/throttle/PTT/friction functions are not part of live acceptance.

## Device readiness

Read-only `xcrun devicectl list devices --timeout 20` on 2026-09-08 lists the physical Apple Vision Pro as **unavailable**. Existing visionOS simulators are available but cannot close physical gaze/pinch/stereo/reach acceptance. Hardware execution remains pending the device becoming connected and a wearer performing the gestures. This does not block the two implementation tasks.
