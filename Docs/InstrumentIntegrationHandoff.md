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
