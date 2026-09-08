# ACA and TTCA hand-controller components

Worker branch `cockpit/hand-controllers`, starting at verified clean detached `75bdea77b57e0ae4971bb4ffbee21c4643e3b4cf`. Only `Assets/Cockpit/Components/HandControllers/` is owned/changed. New authored assets preserve the original repository history. Exact implementation and validation commit: `5629523166bd03ff35244351fa852dd55a2127e1`. This following documentation-only delivery commit records that immutable asset revision.

## Deliverables and reproduction

- `HandControllers.blend`: editable neutral source containing two overlapping standalone identity roots; isolate one root for inspection. Overlap is an authoring convenience, not cabin placement.
- `ACA.usdz`, `TTCA.usdz`: individual neutral portable assets; `.usdc` equivalents. No external texture, linked library, font or material file is needed. All blend/USD files use existing Git LFS rules.
- `build.py`: Blender 5.2.1, `blender -b -t 2 --python <component>/build.py`. Produces source, exports, metadata and eight 640px Workbench views. No heavy render or bake.
- `validate.py`: run with a fresh Blender process; measures geometry and checks export/reimport. `validate_native.swift`: compile with `xcrun swiftc -parse-as-library ... -o /tmp/hand-native`, then pass absolute component directory.
- `interface.json`: exact parent-local neutral origins, proposed motion axes and illustrative offsets. `validation.json`, `native-validation.json`, `review/render-cost.json`: actual results. `evidence/ASSESSMENT.md` and `source-manifest.json`: source applicability, dimensions, hashes and uncertainties.
- `review/{ACA,TTCA}-{front,side,oblique,motion}.png`. Motion images are static, uncalibrated mechanical illustrations, never runtime states.

## Proposed interfaces

Both `/ACA_Mount` and `/TTCA_Mount` are identity, meter-scale, Y-up roots. +X is right, +Y up, +Z crewward. Origin is housing-bottom center in the authored envelope, **not a verified mounting datum**. No cabin mount or approximately 45-degree TTCA installation rotation is baked in.

| Entity | Parent | Neutral translation m | Motion |
|---|---|---|---|
| ACA_Roll | ACA_Mount | 0, .061, 0 | local Z rotation; negative moves grip right |
| ACA_Yaw | ACA_Roll | 0, .062, 0 | local Y rotation |
| ACA_Pitch | ACA_Yaw | 0, .077, 0 | local X rotation; positive moves top crewward |
| ACA_PTT_Trigger | ACA_Pitch | 0, .020, -.028 | local X rotation; exact travel unverified |
| TTCA_VerticalShared | TTCA_Mount | 0, .072, .021 | local X rotation; negative raises projecting grip; shared jets/throttle motion |
| TTCA_Lateral | TTCA_VerticalShared | 0, 0, 0 | local Y rotation; positive moves grip right |
| TTCA_Axial | TTCA_Lateral | 0, 0, 0 | local Z translation; positive moves outward toward crew |
| TTCA_ModeSelector | TTCA_Mount | .065, .056, -.020 | local Y translation; neutral visual JETS/down, up THROTTLE |
| TTCA_Friction | TTCA_Mount | -.039, .027, .025 | local Z rotation; friction mapping unknown |

Every moving node has identity neutral rotation and unit scale. Apply motion relative to the listed neutral translation; do not replace it with zero. Fixed housings/plates are under `ACA_Fixed` and `TTCA_Fixed`. Child movements inherit upstream axes. Nested order is a proposed visual contract, not verified internal gimbal sequencing. Exact physical pivots and all demo travel values remain provisional. The TTCA does **not** gain a fourth rotational axis for throttle. Host state chooses the meaning of vertical movement while lateral/axial commands remain available. No CM abort/autopilot twist mechanism is included.

ACA maximum model envelope follows NASA TN D-7884 table III, 101.6mm wide × 255.5mm high × 169.9mm deep. This is program-level maximum-envelope evidence, not an LM-5 measurement or neutral-pose drawing. Internal shape division and grip sections remain provisional. All TTCA dimensions are provisional; the nearby NASA table V describes CM THC and was not reused. See measured bounds in validation. Cables/armrests, cabin mount adapters and mating panels are omitted pending coordinator reconciliation.

## Ownership and gates

LM owns presentation/input adapters; AGC/LMCore own simulation. No dynamics, hard stops, return springs, throttle curve, detent logic, switch gating or live binding is implemented. Existing LM single-quaternion ACA input cannot be assumed to bind this separated-pivot hierarchy without review. No shared Sources, Tests, Tools, resources, LM app code, AGC/LMCore or other component assets were changed.

Coordinator must accept interfaces, resolve station variants/placement and clearance, refresh any chosen runtime resources, and run package validation. `Tools/sync_dsky.py` is coordinator-owned and does not package hand controllers; it was not run against this source-only component delivery. Native load validation here does not establish SwiftPM packaging acceptance.

Remaining accuracy gates: LM-5 detail confirmation; TTCA dimensioned drawings; precise grip contours and finish; internal pivot/cross-axis coupling; mechanical stop calibration; flexible bellows deformation (current rings are rigid visual approximations); selector/friction travel; cable route and mounting interface; collision, reach and swept-clearance review; Vision Pro readability/ergonomics and live input tests. No hardware or historical-fit acceptance claimed.

## Recorded validation

Fresh Blender reopen, dependency/neutral checks, closed manifold and positive-volume meshes, nonzero faces, unit scales, independent motion in both directions, actual exported world-space vertices, USD compliance, and fresh USDZ reimport: **315 checks passed**. Native macOS RealityKit loaded both assets and checked hierarchy, unit root scale and fixed-housing isolation.

- ACA: 13 meshes, 2124 triangles, 96068 USDZ bytes; measured bounds [-0.05079999938607216, 0.0, -0.08495000004768372] to [0.05079999938607216, 0.2554999887943268, 0.08495000004768372] m.
- TTCA: 31 meshes, 4292 triangles, 133464 USDZ bytes; measured bounds [-0.05849999934434891, 0.0, -0.10250000655651093] to [0.07249999791383743, 0.1249999925494194, 0.1574999988079071] m.

Eight 640×640 Workbench reviews took 0.350 seconds total measured render calls (including first-render initialization); individual timings in render-cost.json. This is local preview cost, not Vision Pro frame time. Zero heavy renders/bakes.
