# Commander station assembly

Worker: `codex/commander-station-assembly`; source baseline `acff0aeac62fc3c009831f0234d56205d36011e4`. LMKit `75bdea77b57e0ae4971bb4ffbee21c4643e3b4cf`; AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`. Both dependencies are hydrated isolated archives from the canonical repositories, reached by untracked sibling links; shared checkouts were not edited. Baseline working tree was clean; Git LFS inspection required sandbox access to the shared Git cache. No machine-specific dependency paths are committed.

## Installation

Launch with `--commander-station-assembly` to opt into the skeleton. The existing cabin-loading call prepares and validates the entire detached assembly before disabling the procedural cabin. Missing/invalid resources or either missing imported instrument leave the procedural fallback active. A second installation is a no-op. Normal startup remains unchanged pending review. Optional legacy exterior registration remains separate and unchanged.

The app retains the original live DSKY/FDAI entities and identity dictionaries at unit scale, all functional controls, and the independent LPD meshes/labels. Only the optional assembly relocates the two instrument parent mounts to the reviewed forward reservations. Internal instrument/key transforms and bindings are unchanged. Functional-control supports and LPD meshes move out of the disabled fallback without changing cabin-relative transforms. AGC/LMCore simulation and the imported adapters remain unchanged. No substitute state, new actuation semantics or decorative copy of a functional control is installed.

## Registration

Cabin root is identity, meters, +X right/LMP, +Y overhead, -Z forward. It is attached beneath the existing cabin frame at `(-.025, 1.981, -.298)` in app root coordinates. This is compatibility registration, not a surveyed body station. The external model uses its separate existing registration and scale.

The packaged manifest's every mount position/rotation is validated in Cabin coordinates BEFORE reconciliation, including nested instrument nodes. Paths are resolved by exact parent/child components; values are never assigned as nested local transforms. Panels 1–4 retain their authored Cabin-relative poses after the baseline/design-eye comparison; 5/6 are reconciled to the existing functional-control basis using Cabin-relative assignment. Instrument roots remain siblings in the app frame and receive the corresponding reservation position/orientation, preserving unit scale; skeleton reservation nodes contain no active instrument geometry.

| Node path below `/Cabin/Mounts` | Installed registration | Reason |
|---|---|---|
| `Mount_Panel_1`…`Mount_Panel_4` | Delivered forward reservations, exact values in packaged mounts.json | Baseline crew-eye comparison exposed near/oblique FDAI and DSKY structural occlusion |
| `Mount_Panel_5` / `Mount_Panel_6` | Existing app surface center + rotated half depth; existing pitch | Preserve functional control basis |
| `Mount_Panel_1/Mount_FDAI` | Cabin `(-.300,1.5924169,-.8666243)`, Rx −10°; local `(-.055,-.015,.016)` below panel face | Optional visual registration; existing live FDAI mount receives this pose |
| `Mount_Panel_4/Mount_DSKY` | Cabin `(0,1.0871127,-.6021005)`, Rx −45°; local `(0,.015,.009)` below panel face | Optional visual registration; existing live DSKY mount receives this pose |
| `Mount_CDR_MiddleTier` | Authored `(-.91,1.17,-.19)`, Rx −53.5° | Unnumbered proposed reservation, no flight control assignment |
| `Mount_CDR_MiddleTier/VisualOnly_MaintainedToggle` | Local `(-.05,0,.006)`, identity rotation/scale | Generic static specimen |
| `Mount_CDR_MiddleTier/VisualOnly_RotarySelector` | Local `(.05,0,.006)`, identity rotation/scale | Generic static specimen |

Panel face centers 1/2 are `(±.245,1.6044106,-.8849859)`, Rx −10°; 3 `(0,1.2781422,-.8058578)`, Rx −45°; 4 `(0,1.0701421,-.5978578)`, Rx −45°. Panel 5/6 retain app centers `(±.5588,.88,-.30)` plus rotated .019 m face offset, Rx −75°. Envelopes remain digitized/provisional, not certified LM-5 outlines.

The initial trial retained old app panel and instrument locations. Its actual calibrated-eye image showed a very near/oblique FDAI housing and partially obscured DSKY. The final optional assembly deliberately moves the FDAI .375 m forward and .050 m upward, DSKY .177 m forward and .041 m upward. Panel 3 moves .280 m forward and .019 m upward. This is visual/ergonomic reconciliation against the delivered skeleton, not mechanical fit acceptance. Normal startup/fallback remains at the old registration. Initial captures and binary hash are preserved under `baseline-registration/` for comparison.

Panel 1 and 4 entire blank backing meshes are disabled: neither instrument has a qualified seating/cutout contract. Reservation outlines are disabled as well. This is an open support reservation, **not** a modeled aperture obtained from subtracting the housing. The tall proposed glare shields remain disabled pending a separate clearance review of the forward panel stack. Other imported shell, deck, window-frame and panel pieces stay independent. The procedural walls/panels/bezel/rails are disabled together; functional-control supports and optical marks alone are retained.

CDR eye is `(-.5588,1.78,-.38)`; the two authored pane corner/basis transforms are checked against the app reconstruction. App LPD geometry and the provisional .020 m normal plane separation remain unchanged. The mirrored LMP window remains explicitly uncalibrated. No pressure-tight hull, mechanical fit or egress acceptance is claimed.

## Control and dimension provenance

The two generic specimens preserve their neutral authored hierarchy, separate actuator and housing, unit scale and original names beneath unique instance roots. They have no collision/input/hover components. A visible `GENERIC SPECIMENS / VISUAL ONLY` label prevents flight-specific interpretation. The maintained-toggle nominal ±17° family basis and rotary 30° spacing come from the delivered NASA TN D-7919 assessment; no movement is bound. Their exact dimensions, hole proposals and rear clearances are provisional. No guard or talkback is installed.

Cabin diameter 92 in and nominal barrel depth 42 in derive from the delivery's Apollo 11 press-kit evidence; station spacing 44 in and approximate 55×36 in deck derive from the Grumman early design evidence. Shell thickness, closure, deck registration, shield profiles and panel envelopes remain proposed. DSKY drawing front envelope is .2063496 × .2032 m, but its .160214 m rear extent is an unqualified visual box. FDAI dimensions and seating plane remain provisional. Consult pinned LMKit DATUM/HANDOFF, packaged mounts/components and acceptance records for these distinctions.

## Review and remaining gates

All skeleton meshes opt out of dynamic shadow casting to avoid close layered-cabin shadow artifacts, following existing interior policy. No scene lights or instrument materials were changed. Materials, shadow reception, headset photometry and frame time remain unqualified. Front/side/crew-eye capture findings and exact camera poses are recorded in the validation directory.

Rear instrument clearance, blank panel boundaries, panel-to-shell continuity, omitted shields, specimen backing penetration, ACA sweep, hand reach, hatch swing/egress and collision/occlusion need review. The skeleton intentionally remains open with incomplete forward/aft closure. Actual pinch/key completion remains unverified; existing successful input evidence is programmatic. No certified fitting, pressure-tight hull or headset acceptance is claimed.

## Validation ledger

Initial simulator compilation found a missing `@MainActor` annotation on the injectable loader closure; corrected before validation. The formatter omitted that diagnostic, so the xcresult issue record was inspected directly. A subsequent test build produced the executable. The first runtime attempt was cancelled after concurrent visionOS test actions spawned multiple clones and repeatedly shut down the dedicated capture device; no pass is inferred from that attempt. The temporary skill-runner copy corrects `-only-testing:<selector>` syntax and disables parallel testing for the serial rerun. No shared skill file was edited.

Final source checkpoint before simulator acceptance: `6c842e8e8f880d096f41d98c01dbd7351bea0440`. The generic visionOS simulator build at that revision passed. Independent macOS RealityKit inspection found unique names and neutral roots in Cabin/MaintainedToggle/RotarySelector and verified all ten packaged Cabin-relative mount transforms (maximum matrix-column error below 2.5e-7); this is not simulator/headset evidence. All seven consumed resource files are hydrated with byte counts and SHA-256 in `dependencies.json`. The initial cancelled test bundle did not finalize, so it has no usable pass summary.

Serial validation completed on visionOS 26.5 (23O470), arm64: **14 passed, 0 failed, 0 skipped** (four assembly tests plus ten original instrument/FIFO tests), confirmed by xcresulttool. Saved summary: `Docs/Validation/CommanderStationAssembly/tests.json`; local result: `/tmp/lm-assembly-final-tests.xcresult`. Final source/test checkpoint is `11a98f0179732de9d46ffc766cf1a099e82f6d58`. The first serial run had 13 passes and one exact-float scale assertion failure (`1.0000001` versus `1` after transform decomposition). The assertion now uses a 1e-5 norm tolerance; no instrument scale or production behavior changed. Initial summary is retained separately. The full unrelated LM suite was not run.

Tests cover detached resource loading, invalid manifest rejection, injected load failure without active-scene mutation, idempotent installation, preserved live key objects and instrument-local transforms, retained independent LPD grids, calibrated pane corner/basis and 20 mm normal separation, absence of duplicate active PRO/FDAI ball nodes, disabled instrument backing reservations, visual-only specimens without input targets, and observer-flag precedence. No shell collision/egress model was introduced; existing functional input colliders remain unchanged.

### Placement reconciliation follow-up

The first passing implementation's crew-eye capture was not accepted as adequate placement: FDAI was too close and oblique, with DSKY partly hidden behind the old Panel 3. With coordinator approval, optional assembly source `44401a5a6d0e756566ee7e12cab39d2e4b27ffeb` adopts delivered forward Panel 1–4 / DSKY / FDAI reservations as described above. The same real instrument objects move by parent registration only; normal startup and functional controls remain unchanged. Updated tests compare instrument-local key transforms and exact identity, while checking the installed DSKY root against the intended reservation. Both suites again passed **14/14, zero failures/skips**, confirmed in `/tmp/lm-assembly-reconciled-tests.xcresult` and final `tests.json`. These are the source and results for final captures; earlier source IDs above describe the retained baseline trial.

Final capture source is `7a4247cfee6d16dd815aebc00c927b034049cccf`: the only change after placement validation is raising the DEBUG crew-eye target from Y=1.29 to Y=1.43 m so both relocated faces fit in the image. The calibrated eye is unchanged. Its generic visionOS Simulator build passed. Exact observer metadata and both executable/dylib hashes accompany final captures.

Exact captured source `7a4247c` was revalidated after the camera-only change: **14 passed, zero failures/skips** in `/tmp/lm-assembly-delivery-tests.xcresult`; final `tests.json` now records that run. Front, side and fixed calibrated-eye images contain both complete instrument faces. Successful installation and live P64 were logged for each capture PID. The original instrument observer is unchanged and crops the relocated FDAI; use the dedicated assembly views for two-face evidence. Final visual findings, PIDs and limitations are in the validation README. Dedicated simulator `94C9CF9E-5495-4431-88AF-F3C211FD04C6` was shut down and the coordinator notified that the exclusive runtime slot is released. No actual pinch/key acceptance is claimed.
