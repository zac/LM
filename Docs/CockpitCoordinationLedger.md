# Cockpit coordination ledger

## Solid console enclosure and LPD placement phase

User review identified exposed instrument backs, skeletal framing and inadequate enclosure despite successful individual instrument delivery. This phase replaces structural surfaces around fixed live instruments with solid central/lower consoles and thicker window surrounds. A parallel user-requested LPD audit corrected its sideways-drifting spine to the vehicle-forward reference using unchanged provisional pane/eye datums; crossbar spacing and numeric targeting remain unqualified.

LMKit runtime package `c425dcfc8a753c20159fe2226a181faace96b9dc` contains InstrumentConsole `b6d2712`, LowerConsole `d15b4fb`, WindowSurrounds `38eaad3` and WindowsLPD correction `f5824e4`, preserving worker history. Independent combined geometry clears all three enclosure pairings, windows/breakers, sampled sightlines and125 ACA poses. Hidden rear mounting contacts remain documented. Package tests pass13 functions including two parameterized functions with17 cases each.

LM runtime `53b9f17` installs each enclosure transactionally using exact suppression paths, protected mounts and required live-instrument gates, preserving fallback and input identity. Replacement shell casters participate in fitted lighting. Corrected enclosure runtime0b98768 passes 105 tests in 19 suites. Native views show improved solid embedding; a pilot-contact surround notch remains and its later draft fix is excluded. Short P65 demo967f16b defaults to a headlessly verified 49.23-second soft landing; this final configuration was not app-run at user request. Evidence: Docs/Validation/SolidConsole/README.md. Physical Vision Pro remains untested.

Updated 2026-09-08. This section supersedes the historical records below.

## Pilot station and systems phase

LMKit `main` package `d8c24dd5591bc8b874e643df65932ac863713832` is published with all required LFS objects. Component deliveries and source evidence are preserved in its `Provenance/pilot-systems-acceptance.json`. AGC/LMCore remains `b3f15533db335ee882dc07401790c93010809e8f`; canonical LM terrain/LunarMap work is untouched. LM runtime source `bdbf70f8b47f744c78dac7352477a6cd699754c5` passes 98 native visionOS tests across 18 suites, with zero failures or skipped tests. Corrected-lighting views, both crew stations, planning/fallback and near-ground lander shadows are accepted in Docs/Validation/SystemsIntegration/Captures. The simulator is shut down and released.

| Addition | Runtime behavior / qualification |
|---|---|
| Pilot FDAI | Second independent instance at Panel2__FDAI; uses the existing supported attitude source. Independent PGNS/AGS source selection remains unavailable. |
| Readability and planning | Scoped instrument material treatment; occupancy labels reflect actual installed components and partial regions. Mission lighting policy preserved. |
| Event timer | Simulation-time counting, start/stop/reset, direction and held digit adjustment; explicit pause/restart/replay availability and gesture cancellation. Later Apollo 13 countdown-to-count-up behavior is documented. |
| Mission timer | Installed hardware and addressable digits; blank because a supported mission epoch/preset is absent. Mission control bank is uninstalled due to Panel5 clearance. |
| Engine controls/contact | Neutral engine guard and buttons coexist with DES RATE; engine buttons stay inert. Both contact lamps use optional landing-gear probe state; host training status distinguishes missing data from clear. Power/test/stop-reset circuits remain unmodeled. |
| Propulsion instruments | Source-qualified faces and independent needles/digits; quantities, pressures and historical T/W indications remain unavailable. |
| Caution/warning | Two installed dark arrays, 40 cells including nine source blanks. No fabricated CWEA behavior; master-alarm reference remains unmounted. |
| Interior details | Thirteen independently removable groups, including overhead liners, mesh, hatch fittings and cables. Hatch-attached detail requires coordinated removal if the hatch opens later. |

LMKit native package checks pass all 13 test functions, including two parameterized functions with 14 cases each. Combined geometry checks cover 153 installed component pairs and 61 named face/grip sightlines; no new-component intersections or blocked sampled rays remain. Fourteen rear seating/backing mesh-pair intersections are retained and documented; dimensions, fabrication fit, hand reach and headset optics remain unqualified.

Initial native integration found JSON numeric-array decoding failures and stale test assumptions. Typed numeric decoding preserves strict mounting checks; pilot tests now use scoped instance identity, and optional-detail tests distinguish the warning overlay. The affected 15-test native run passes. The initial 90-test combined run passed. The user then correctly rejected the white ceiling in native images: imported-shell shadow casting was disabled. Restored shell casting and a fitted local shadow map correct that cause without repainting or changing sunlight intensity/direction. The corrected source passes 98 tests; final production screenshots and per-launch installation/shadow reports are reviewed and retained with SHA-256 hashes. Local shadow coverage excludes distant terrain outside the cabin/lander footprint.

Remaining priorities: physical Vision Pro appearance/input acceptance; authoritative crew engine and TTCA input semantics; mission clock preset and replayable event history; pressure/quantity/CWEA models; AGS/DEDA, radar and ECS/power equipment; optical LPD calibration and provisional mechanical clearances. Priority governs work order; the user manages time, with no estimated-time omissions.

## Historical commander-instrument acceptance

LM `cockpit/integration` source `5ec10b8404130b1b0cefdbdc28d93aa3d221ec4a` integrates the commander instruments and interior details. LMKit runtime package `1285040dbaa1e4c3c4002975764a58fc49018012` is published; component histories and LFS authoring assets are preserved. AGC/LMCore remains `b3f15533db335ee882dc07401790c93010809e8f`. Canonical LM terrain/LunarMap work is untouched.

The final visionOS simulator run passes 64 tests in 13 suites, zero failures/skips. Native startup capture confirms the 42,000-to-25,000-lux lighting jump is removed: the same mission light settings now apply before and after terrain loading. Eight final views cover normal, inspection, optional details, planning, training and procedural fallback. [Evidence and gallery](Validation/CommanderInstruments/README.md).

| Added component | Accepted source | Runtime state |
|---|---|---|
| AltitudeRate | 7670439 | Geometric altitude and radial rate drive independent tapes/shutters; provisional taller envelope |
| DescentControls | 9e598a7 | AUTO/ATT HOLD and spring-return DES RATE use existing inputs; OFF unsupported |
| CrossPointer | daf7f32 | Independent velocity needles; documented later fly-to inference, fixed LO scale |
| BreakerBanks | 975f1db | 160 static breakers across nine commander/pilot regions; no circuit simulation |
| InteriorDetails | 9eca80d | Seven removable cable/clamp/trim groups; no interactions |

Four partial functional regions and nine breaker regions are occupied at runtime; failed loads preserve blanks. DSKY/FDAI/ACA remain live. Partial regions retain backing for equipment still to build. Planning labels retain generic authoring-region text, including “not modeled” on partially populated regions; normal presentation hides them. This is a planning-label refinement, not simulation state.

All five dispatched modeling lanes and app integration are complete for this phase. Final simulator shutdown is verified and its slot is released. Priority governs work order; the user manages time. There are no deadline-based omissions or time estimates. Remaining work includes physical Vision Pro acceptance; overall interior lighting/material refinement; engine START/STOP and contact indications; propulsion instruments; timers with a defined time origin; warning/AGS/ECS/radar systems; TTCA; overhead/aft equipment and shades. Panel5 timer clearance and LPD optical calibration remain unresolved. Historical dimensions and mechanical seating remain provisional.

## Historical enclosed-foundation acceptance

## Current integration

- Coordinator checkout: LM `cockpit/integration`, `/Users/zac/.codex/worktrees/591e/LM`. Canonical LM terrain/LunarMap work remains independent and untouched.
- LM source `3d34dcfd718ae410f6c5b68d5525c93ef9d01319` implements the enclosed foundation as normal startup, with a procedural fallback if component validation/loading fails. Final combined simulator validation passes 47 tests in 8 suites with zero failures/skips. Eight final captures confirm planning text, normal/training suppression and procedural fallback; see `Docs/Validation/EnclosedFoundation/`. Publication accompanies this evidence commit.
- LMKit final tested runtime package is `b870a9b112797d3ea627c663df2684c97f9cc2a3`; published `main` also includes a documentation-only final acceptance record. Only the packaged PanelInventory visibility differs from the original d1b0bb5 package; its deterministic derivation and exact hashes are recorded in packaging.json. Eleven native package tests and nineteen focused validator-policy checks pass. All original component LFS objects and the derived runtime PanelInventory are uploaded with publication.
- AGC/LMCore validation baseline `b3f15533db335ee882dc07401790c93010809e8f`, isolated hydrated snapshot. Simulation is unchanged.
- Historical presentation `3a8b9b6` and all component worker histories are preserved by merges.

## Component inventory

| Component | Accepted authoring delivery | Current behavior / remaining work |
|---|---|---|
| DSKY | LM `c655fe5` | Imported model and live AGC keys/digits/lamps; rear housing and mechanical seating unverified |
| FDAI | `c4c565f` | Imported ball with live attitude; unsupported needles remain hidden; pivots/dimensions provisional |
| ControlLibrary | `3963737` | Six neutral reusable families; per-panel hardware and simulation bindings remain unbuilt |
| Cabin | `bae0c02` | Enclosed visual foundation, closed static hatches and six inspection cutaways; liners, supports and detailed hatch hardware remain approximate |
| HandControllers | `750caea` | Commander ACA runtime accepted at `862714e`; TTCA remains an unbound prototype pending real input APIs |
| CommanderPanels | `6c8c271` | Independent Panel 1/4 surrounds; backing suppressed only when inventory blanks install to prevent coplanar striping |
| WindowsLPD | `b794640` | Layered glazing/frames and fine physical commander marks; numerical targeting, pane spacing and exact mission applicability unqualified |
| PanelInventory | `0c58843`, validator followup `c98f5e0` | 28 groups and 66 replaceable slots, separate planning labels; most intended equipment is still blank; Panel5__Timer explicitly blocked by ACA clearance |

Panel numbers and descriptive equipment names are source-qualified in LMKit `Assets/Cockpit/Components/PanelInventory/inventory.json`. No new runtime semantics are inferred from names. Later/generic references remain distinguished from LM-5 evidence.

## Assembly and runtime gates

Cabin, WindowsLPD, CommanderPanels and PanelInventory load once as identity siblings. Original mount/optical metadata remains; old visible shell/panes/frames/marks/reservations are removed or disabled. Live DSKY/FDAI/ACA instances and their bindings survive installation. Successful equipment loading hides only its own blank; failures keep it. Timer replacement is rejected before loading until its layout is resolved.

Historical view hides electronic training cues and development labels. `--cockpit-planning-labels` or the independent planning button enables labels. `--procedural-cockpit` selects the fallback. Imported windows suppress the procedural LPD and projected digital marker even when training is enabled. Both old and new LPD geometry remain unqualified for angular targeting. All shell cutaways/hatches are enabled in normal mode.

User photographs and the interactively inspected Smithsonian LM-2 panorama are preserved/referenced in LMKit `References/Interior/User-2026-09-08/`. They guide shaped ceiling covers/mesh, stepped breaker banks, projecting consoles, window edge layers and cable/support detail. They do not establish new measured dimensions or Apollo 11 flight-exact appearance.

Combined Workbench review in LMKit `Docs/Validation/EnclosedFoundationGeometry/` found and verified a correction for backing/blank overlap; corrected views retain instrument faces and surrounds. Three center rays showed no opaque window blockage. This is geometry-only evidence with glazing hidden, not native app photometry or full aperture clearance.

## Active coordination

All work is local. All phase deliveries are merged and reviewed. No heavy render is active; final simulator shutdown is verified and the slot is released. Physical Vision Pro stereo, gaze/pinch, reach, optics and performance remain untested. Final source review and combined simulator acceptance found no remaining foundation behavior blocker. Detailed lighting, equipment shape and mechanical seating remain unfinished.

The phase plan is LMKit `Docs/InteriorFoundationPhase.md`. Candidate later modeling: shaped overhead liners, stepped breaker terraces, window shades, panel instruments and routed supports/cables. These are inventory items, not dispatched new work.

## Enclosed interior phase dispatched — 2026-09-08

Authoritative phase plan: LMKit `Docs/InteriorFoundationPhase.md` at `09364460e8be570338f3d39a07067fe2bee0b044`. LM source baseline `11f7335b73884ce8dd8ebe33583f666e2b329c72`.

User correction supersedes earlier optical freeze: existing LPD assumptions are untrusted/provisional. Approximate appearance closer to hardware is acceptable. Review magenta/green scales; remove synthetic digital LPD indicator/readout and diagnostic eye overlays from normal historical view. Actual DSKY/AGC readouts remain real instrumentation. Historical appearance, numerical reconstruction and physical optical qualification must remain distinct.

| Task | ID | Worktree / owned scope |
|---|---|---|
| Enclosed foundation | `01a082c7-5917-7ff0-b958-2e65d14d8903` | `/Users/zac/.codex/worktrees/6943/LMKit`, `cabin-enclosed-foundation`, Cabin only |
| Windows/LPD | `01a082c7-6520-7c91-a2cd-b7424bd156cb` | `/Users/zac/.codex/worktrees/4155/LMKit`, `work/windows-lpd-enclosed`, WindowsLPD only |
| Panel inventory | `01a082c8-0171-7a93-a11d-d49ee8136592` | `/Users/zac/.codex/worktrees/fc70/LMKit`, `codex/panel-inventory-enclosed`, PanelInventory only |
| Historical presentation | `01a082c8-129a-7e72-bf03-7b482e54be97` | `/Users/zac/.codex/worktrees/556e/LM`, overlay/LPD presentation and focused tests; owns sole simulator slot |

Cabin initial committed proposal `2fafa5bda020b83cb7e6dff7af1a45cf6f9b35fe`, `Cabin/interface-v1.json`, was shared with WindowsLPD and PanelInventory. Its old eye/pane/mount coordinates remain provisional and subject to the source audit. Proposed aft extension/closed hatch are visual layout choices. Final opening/eye/pane contract must be agreed before geometry installation. Metadata nodes should remain stable while old shell/window/reservation visuals are explicitly migrated.

Panel schema separates Cabin-relative panel poses from parent-local equipment slots, placeholder meshes and optional PlanningLabels. External working instruments/surrounds are occupants, never duplicated in the blank model. Descent-ready closed-cabin state is the phase baseline, with optional inspection cutaways. Coordinator owns shared packaging, normal-interior promotion, placeholder fallback and combined verification; these deliveries are now complete at the revisions in the current section above; this dispatch record is historical.

## ACA and CommanderPanels integration — 2026-09-08

- Panel delivery `6c8c271a1027d29edf24b17c6cd86b137e1e0a35` accepted as provisional visual surrounds, merged preserving original history and packaged in published LMKit `86aa71b4b9ed203f11e8b572e23da2b0285a0ad8`. Nine native package tests pass. Original source reports 286 geometry/transform/clearance checks; independent coordinator review confirmed artifacts, transforms and selected views.
- The new Panel 1 outline narrows its outboard edge by 85 mm to avoid reference CDR optics. Both accepted instrument poses and CDR optics remain fixed. Deliberate 3 mm openings clear full visual envelopes; no instrument contact flange/fastener or mechanical fit is implied. Reference intersection checks do not cover relocated live controls or the full runtime assembly.
- ACA delivery `862714e3479947d70c333fff83aa03e6375f492b` passed independent software review and 30 native simulator tests. Merge `ea64408` preserves the delivery. TTCA API audit found no typed translation/manual-throttle controller binding; no new dynamics were added. Rigid grip/boot separation at combined negative travel remains an authored kinematic limitation.
- Combined local source `7c1b4a751570cd8cdec35acac5c6fe976d53dfdf` installs panel resources at Cabin identity only within optional assembly, validates interfaces against reservations before installation, removes input components and preserves original reservation/shield suppression. One new test rejects a mismatched panel interface.
- Combined serial validation completed: 31 discovered tests, 31 passed, zero failures/skips, independently confirmed from xcresult. Exact source `7c1b4a7`, LMKit `86aa71b`, AGC/LMCore `b3f1553`. Six simulator views show no new panel-induced face occlusion or ACA/panel interference. A native 729-pose check found no panel/ACA AABB overlaps (minimum conservative gap 0.222634494 m). Evidence is in `Docs/Validation/ACACommanderPanelsCombined/`. Simulator shut down and slot released. Physical Vision Pro remains unavailable.

## Next assignments dispatched — 2026-09-08

- ACA integration: task `01a082b1-da15-7642-9195-0a71036a38be`, worktree `/Users/zac/.codex/worktrees/313f/LM`, branch `codex/aca-integration`, base LM `9016960`, LMKit `3ad1a99`, AGC/LMCore `b3f1553`. Owns ACA adapter/scene/input lifecycle integration and focused verification. TTCA is API audit only. Sole simulator runtime slot assigned to this worker.
- Commander panel fit: local LMKit worktree `/Users/zac/.codex/worktrees/8891/LMKit`, branch `cockpit/commander-panel-surrounds`, base `3ad1a99`. Owns only `Assets/Cockpit/Components/CommanderPanels/`. Scope is surrounds/backing/openings for existing DSKY/FDAI poses, numeric clearances, provenance and provisional mounting interfaces; no shared resources or master assembly edits.
- Coordinator retains packaging, merge review and combined validation. Workers return scoped commits; no worker publishes integration/main.
- Hardware readiness checked: physical Vision Pro unavailable. `Docs/CockpitNextAcceptance.md` records merge order and subsequent physical session checks. Neither new delivery nor hardware acceptance is complete.

## Historical setup and extraction record

Updated: 2026-09-08.

## LMKit extraction — 2026-09-08

- Model library: `https://github.com/zac/LMKit`, local sibling checkout `../LMKit`.
- Accepted initial package commit: `d8e35fa3ec8dc400cbb2762c24953022b07e8ebb`.
- DSKY source: `c655fe5` from `cockpit/dsky`; imported with per-file hashes and original source commit in LMKit `Provenance/imports.json`. Accepted as a standalone visual asset, not live cockpit bindings or certified mounting fit.
- Legacy wrapper and exterior asset moved byte-for-byte to LMKit; LM model loaders and menu use its resource URLs. Removed duplicate copies from RealityKitContent. Other scene resources remain in RealityKitContent.
- Validation: four LMKit tests pass, including native RealityKit composition and 19-key hierarchy. LM visionOS simulator build passes; repeat after asset removal recorded in `Docs/LMKitIntegration.md`.
- AGC baseline used for build: `b3f15533db335ee882dc07401790c93010809e8f`. No AGC or LMCore changes.
- DSKY task: `01a08239-54ee-77a1-91d1-c90871fa8233`; FDAI task: `01a0824c-08d2-7af0-8872-4bc107233169` on ewsbuild. FDAI continues its existing component branch until accepted import.
- New model work belongs in LMKit. The older setup/assignment tables below are historical and superseded by this extraction.

## Base checkout

- Role: cockpit coordinator and integration owner.
- Branch: `cockpit/integration`.
- App ancestry: `89ecb0fe641292640a56e37ddf72587c342a4066`.
- Coordination setup: research and orchestration files established in the initial local coordination commit. Resolve its exact SHA with `git log -1 --format=%H -- Docs/CockpitCoordination.md` before dispatch.
- Remote publication: not performed.
- Worker tasks: none dispatched.
- Blender version, machine assignments and render capacity: not yet qualified.

## External dependencies

| Dependency | Status | Gate |
|---|---|---|
| LunarMap extraction | In progress in the other LM checkout when inspected; not integrated here | Record accepted LM commit and passing checks before integration changes |
| AGC / LMCore merge | In progress in its existing task when inspected; no revision pinned by this setup | Record accepted AGC commit and dependency arrangement before integration builds |
| Shared asset contract | Draft v0 committed with this setup | Each assignment freezes its subset of dimensions and datums; unknowns remain explicit |

## Component assignments

| Component | Branch | Task / machine | Starting SHA | State |
|---|---|---|---|---|
| DSKY | `cockpit/dsky` | Unassigned | Not dispatched | Ready for scoped assignment |
| FDAI | `cockpit/fdai` | Unassigned | Not dispatched | Inspect existing asset first |
| Control library | `cockpit/control-library` | Unassigned | Not dispatched | Ready for scoped assignment |
| Panels | `cockpit/panels` | Unassigned | Not dispatched | Research ready; placement depends on component contracts |
| Cabin | `cockpit/cabin` | Unassigned | Not dispatched | Freeze geometry/datum subset first |
| Hand controllers | `cockpit/hand-controllers` | Unassigned | Not dispatched | Resolve mechanism references |

## Accepted deliveries

None yet. For each delivery record component commit, integration commit, contract revision, validation evidence and known limitations.

## Render slots

No active jobs or remote workers established by this setup. Initial limit is one heavy render/bake per machine. Record owner, machine, scene/commit, start time and output directory before launching a job; release the slot after completion or failure.

## Next coordination actions

1. Choose the first component workers and computers.
2. Verify their Blender version, Git LFS and repository access.
3. Freeze their specific asset-contract requirements and dispatch from an exact committed baseline.
4. Start independent DSKY, FDAI and control-library work; prepare cabin datums alongside them.
5. Reconcile accepted LunarMap and AGC revisions before application integration.
