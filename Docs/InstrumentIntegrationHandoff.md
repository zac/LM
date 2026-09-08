# Live instrument integration

Worker branch: `cockpit/live-instruments`, isolated LM baseline `ed230a6ee4286bc2385f44bc8f1889bdcc39a8ab`. Dependency baselines: LMKit `c75d37930fe34b7bf96dc5f757625ce5e983a489`; AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`.

AGC's shared checkout had a preexisting modification to LMAGCPadLoad.swift. Build dependency is a clean git archive of the pinned revision under /tmp, reached by an untracked sibling symlink. LMKit is clean at the baseline, reached by another sibling link. No absolute paths enter the project or shared source changes.

## DSKY checkpoint

The neutral LMKit resource replaces the procedural children only after unique-name and direct-key-parent checks succeed. Nineteen imported Entity identities populate the existing ancestor-walking lookup. Each key has a cap-sized 17.78 × 15.748 × 8 mm collision box, input target and hover; no expanded overlapping targets. A completed spatial tap dispatches one existing AGC key pulse. A cancelled tap has no input. PRO pulses release after 120 ms or task cancellation; successor pulses await predecessor release. No held-key semantics are claimed. The key subtree moves 3 mm and springs back from its recorded rest position.

Named A–G segments preserve spaces, signs and AGC channel-163 flash phase/EL-off; twelve lamps and COMP ACTY are independent. Lamp test lights the thirteen named lamps; digits remain actual AGC register output. Spare cells stay unbound. On materials use native unlit colors; imported neutral materials and diffusers are restored/preserved. Brightness and bloom are uncalibrated. No power/brightness selector behavior is invented.

Removed the duplicate DSKY SwiftUI attachment. Failed resource/contract loads log an error and retain the procedural fallback. Artist cabin instrument mounts are disabled to avoid duplicate renderers; app adapters own instrument visuals and identity lookup.

Mount retains the existing app position/orientation and unit scale. The DSKY face midpoint is a visual registration, not a mechanical seating plane. Rear housing and panel cutout remain unqualified; see LMKit fit-interface.json.

Validation in progress: initial generic visionOS simulator build passed; targeted DSKY tests added for mapping, neutral hierarchy, impostor identity rejection and PRO cancellation. Native shader appearance and hardware gaze/pinch/neighbor selection, stereo, materials and frame time remain untested.

FDAI attitude integration follows this checkpoint. Source-model corrections, mechanical fitting and the master cabin remain coordinator-owned.

Test-target baseline reconciliation: two existing LPD assertions named uncommitted AGC constants. They now use the identical CH31 bit masks (positive pitch 0o1, positive roll 0o20) inline, preserving assertions without importing the shared dirty change. This does not establish that the unrelated LPD feature passes. The skill runner also emitted the wrong `-only-testing` argument form; a temporary runner copy uses `-only-testing:<selector>`. No skill files were changed.

## FDAI adapter

DSKY checkpoint is `11572c8`. The neutral `LMKitAssets.fdaiURL` replaces the legacy sphere and fixed procedural markers atomically after hierarchy validation. Removed the cockpit's separate FDAI SwiftUI overlay. The console FDAIPanel remains unchanged outside this cockpit.

The imported UV zero meridian faces +Z, positive latitude is +X, and positive longitude is toward -Y. Transforming the legacy GASTA motion basis by -90° around Z maps old Y to new X and old X to new -Y. Thus the new ball motion is `Rz(-CDUX) * Ry(CDUZ) * Rx(-CDUY)`, with **no legacy +90° texture-alignment rotation**. This keeps the existing `LMIMUGimbalMap.cduRadians` reference convention (identity/site-local stable frame); old research recommending a PDI-relative reset conflicts with current source and is not applied. REFSMMAT/ORDEAL selector behavior is not added.

Only the ball pivot rotates. Fixed housing/reticle are independent. The six rate/error pointer pivots and separate roll bug are explicitly hidden/unbound: current app selection, units, signs and calibration are not established. Their modeled sweep is not a spacecraft measurement. No zero indication or independent roll-reference behavior is invented.

FDAI uses unit scale at the existing app FDAI mount, with the asset's local ball center retained at z=-8 mm. Its smaller ball/face and provisional seating datum are accepted only as visual registration; panel aperture, rear clearance and historical fit are not qualified.

## Validation ledger

- DSKY checkpoint: four instrument tests passed on visionOS 26.5 simulator (native resource binding, all keys, PRO cancellation, display masks/lamps).
- FDAI first pass: seven instrument tests passed, including ±30°/±85° pitch/yaw/roll, explicit authored UV points, composition, reference cancellation, native fixed/pivot independence and hidden unsupported needles.
- Shared LMKit advanced to `75bdea7` during validation. Both dependencies are now isolated git archives of the required exact revisions; final validation uses fresh derived data. The archive operation supplied hydrated resources. No dependency branch was switched.
- Existing asset validation is reused: DSKY 276 authoring checks and FDAI 1,012 checks; no Blender render/bake repeated.
- Final tests additionally inspect live material replacement/restoration and all pairwise key-target spacing. Simulator visual smoke and final fresh build results follow below.

### Final acceptance evidence

Fresh pinned-dependency simulator build and targeted test action passed on visionOS 26.5 (23O470), arm64: **7 passed, 0 failed, 0 skipped**, confirmed by xcresulttool rather than runner exit text. Summary: `Docs/Validation/InstrumentIntegration-tests.json`. Local result bundle: `/tmp/lm-instrument-final/Logs/Test/Test-LM-2026.09.08_12-16-12--0700.xcresult`. Generic simulator app build also passed earlier. Existing unrelated concurrency warnings in lunar test files remain; the entire LM test suite was not run.

Visual smoke: final app installed and launched with `--terminal-descent-cockpit` on isolated simulator `2F598E08-CF7D-43D7-8203-B0AB65897849` (LM Instruments Smoke 25f3). Screenshot `/tmp/lm-instruments-smoke.png` shows the imported FDAI ball, housing and fixed frame, with no old overlay. DSKY is below the initial camera view; its rendered face was not visually qualified. AXe describe-ui failed with “No translation object returned for simulator”, so no simulator pinch/key interaction is claimed. Native tests prove shipping DSKY hierarchy, per-key input components, nonoverlapping boxes, identity resolution and material state changes. This remains partial visual acceptance, not a full cockpit image/interaction qualification.

Remaining gates: Vision Pro gaze/pinch ergonomics, PRO interaction in headset, neighboring-key selection, stereo scale, materials/transparency/brightness, and frame time; DSKY camera/visual smoke; mechanical fitting; independent FDAI rate/error calibration and roll-reference linkage. No shared AGC/LMCore, LMKit source models, cabin assembly, terrain or exterior behavior was edited. No new binary assets are required.

Implementation revisions: DSKY `11572c821016b2317e010ba1828f1af242ba031f`; FDAI plus final tests `2ae2c5fa09e7e68e3072b5b83e77b347f4595df7`. This subsequent documentation-only commit records those immutable source revisions. Smoke logs also confirm live `Physical DSKY display P64 V06 N64` after loading; no imported-instrument fallback errors were emitted. Publication is limited to `cockpit/live-instruments`; no merge into integration/main.
