# Commander station assembly

Worker: `codex/commander-station-assembly`; source baseline `acff0aeac62fc3c009831f0234d56205d36011e4`. LMKit `75bdea77b57e0ae4971bb4ffbee21c4643e3b4cf`; AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`. Both dependencies are hydrated isolated archives from the canonical repositories, reached by untracked sibling links; shared checkouts were not edited. Baseline working tree was clean; Git LFS inspection required sandbox access to the shared Git cache. No machine-specific dependency paths are committed.

## Installation

Launch with `--commander-station-assembly` to opt into the skeleton. The existing cabin-loading call prepares and validates the entire detached assembly before disabling the procedural cabin. Missing/invalid resources or either missing imported instrument leave the procedural fallback active. A second installation is a no-op. Normal startup remains unchanged pending review. Optional legacy exterior registration remains separate and unchanged.

The app retains the original live DSKY/FDAI entities and identity dictionaries at unit scale, all functional controls, and the independent LPD meshes/labels. Their supports are moved out of the disabled fallback without changing cabin-relative transforms. AGC/LMCore simulation and the imported adapters remain unchanged. No substitute state, new actuation semantics or decorative copy of a functional control is installed.

## Registration

Cabin root is identity, meters, +X right/LMP, +Y overhead, -Z forward. It is attached beneath the existing cabin frame at `(-.025, 1.981, -.298)` in app root coordinates. This is compatibility registration, not a surveyed body station. The external model uses its separate existing registration and scale.

The packaged manifest's every mount position/rotation is validated in Cabin coordinates BEFORE reconciliation, including nested instrument nodes. Paths are resolved by exact parent/child components; values are never assigned as nested local transforms. Reconciled panel transforms are assigned relative to Cabin, preserving authored child hierarchy. Instrument roots themselves remain siblings in the app frame; skeleton reservation nodes identify matching poses and contain no active instrument geometry.

| Node path below `/Cabin/Mounts` | Installed registration | Reason |
|---|---|---|
| `Mount_Panel_1`…`Mount_Panel_6` | Existing app surface center + rotated half depth; existing pitch | Preserve reviewed instrument/control reach and registration; do not accept proposed forward shifts silently |
| `Mount_Panel_1/Mount_FDAI` | App FDAI pose; local `(-.055,-.015,.016)`, identity rotation relative to reconciled panel face | Visual registration only; live FDAI stays in app frame |
| `Mount_Panel_4/Mount_DSKY` | App DSKY pose; local `(0,.015,.009)`, identity rotation relative to reconciled panel face | Visual registration only; live DSKY stays in app frame |
| `Mount_CDR_MiddleTier` | Authored `(-.91,1.17,-.19)`, Rx −53.5° | Unnumbered proposed reservation, no flight control assignment |
| `Mount_CDR_MiddleTier/VisualOnly_MaintainedToggle` | Local `(-.05,0,.006)`, identity rotation/scale | Generic static specimen |
| `Mount_CDR_MiddleTier/VisualOnly_RotarySelector` | Local `(.05,0,.006)`, identity rotation/scale | Generic static specimen |

Panel centers before face offset are inherited from `LMCommanderStationGeometry`: 1/2 `(±.245,1.55,-.535)`, Rx −10°, half depth .0254; 3 `(0,1.245,-.540)`, Rx −45°, half depth .020; 4 `(0,1.015,-.435)`, Rx −45°, half depth .020; 5/6 `(±.5588,.88,-.30)`, Rx −75°, half depth .019. These panel envelopes are digitized/provisional, not certified LM-5 outlines. The delivery's forward panel proposal is not adopted: panels 1/2 were approximately .375 m farther forward, panel 3 .280 m, panel 4 .177 m, with additional vertical deltas. Reconciliation preserves the current app baseline, not historical fit acceptance.

Panel 1 and 4 entire blank backing meshes are disabled: neither instrument has a qualified seating/cutout contract. Reservation outlines are disabled as well. This is an open support reservation, **not** a modeled aperture obtained from subtracting the housing. The tall proposed glare shields are disabled pending reconciliation with the retained panel stack. Other imported shell, deck, window-frame and panel pieces stay independent. The procedural walls/panels/bezel/rails are disabled together; functional-control supports and optical marks alone are retained.

CDR eye is `(-.5588,1.78,-.38)`; the two authored pane corner/basis transforms are checked against the app reconstruction. App LPD geometry and the provisional .020 m normal plane separation remain unchanged. The mirrored LMP window remains explicitly uncalibrated. No pressure-tight hull, mechanical fit or egress acceptance is claimed.

## Control and dimension provenance

The two generic specimens preserve their neutral authored hierarchy, separate actuator and housing, unit scale and original names beneath unique instance roots. They have no collision/input/hover components. A visible `GENERIC SPECIMENS / VISUAL ONLY` label prevents flight-specific interpretation. The maintained-toggle nominal ±17° family basis and rotary 30° spacing come from the delivered NASA TN D-7919 assessment; no movement is bound. Their exact dimensions, hole proposals and rear clearances are provisional. No guard or talkback is installed.

Cabin diameter 92 in and nominal barrel depth 42 in derive from the delivery's Apollo 11 press-kit evidence; station spacing 44 in and approximate 55×36 in deck derive from the Grumman early design evidence. Shell thickness, closure, deck registration, shield profiles and panel envelopes remain proposed. DSKY drawing front envelope is .2063496 × .2032 m, but its .160214 m rear extent is an unqualified visual box. FDAI dimensions and seating plane remain provisional. Consult pinned LMKit DATUM/HANDOFF, packaged mounts/components and acceptance records for these distinctions.

## Review and remaining gates

All skeleton meshes opt out of dynamic shadow casting to avoid close layered-cabin shadow artifacts, following existing interior policy. No scene lights or instrument materials were changed. Materials, shadow reception, headset photometry and frame time remain unqualified. Front/side/crew-eye capture findings and exact camera poses are recorded in the validation directory.

Rear instrument clearance, blank panel boundaries, panel-to-shell continuity, omitted shields, specimen backing penetration, ACA sweep, hand reach, hatch swing/egress and collision/occlusion need review. The skeleton intentionally remains open with incomplete forward/aft closure. Actual pinch/key completion remains unverified; existing successful input evidence is programmatic. No certified fitting, pressure-tight hull or headset acceptance is claimed.

## Validation ledger

Initial simulator compilation found a missing `@MainActor` annotation on the injectable loader closure; corrected before validation. The formatter omitted that diagnostic, so the xcresult issue record was inspected directly. A subsequent test build produced the executable. The first runtime attempt was cancelled after concurrent visionOS test actions spawned multiple clones and repeatedly shut down the dedicated capture device; no pass is inferred from that attempt. The temporary skill-runner copy corrects `-only-testing:<selector>` syntax and disables parallel testing for the serial rerun. No shared skill file was edited.
