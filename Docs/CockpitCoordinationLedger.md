# Cockpit coordination ledger

Updated: 2026-09-08. This current section supersedes the historical setup below.

## Current integration

- Coordinator: LM `cockpit/integration`, isolated worktree; canonical LM terrain/LunarMap work is independent and untouched.
- LMKit `main`: `3ad1a999ff17aea859eaea5750f1c65e66fad673`, published. Owns assets, authoring sources and resource APIs. Eight native package tests pass.
- AGC/LMCore validation baseline: `b3f15533db335ee882dc07401790c93010809e8f`, hydrated isolated snapshot. Simulation behavior remains outside LMKit.
- Live DSKY/FDAI and FIFO accepted at merge `73079d2`; visual evidence at `acff0ae`.
- Readability/completion-adapter delivery `d2668baa1c7d59bbfb3003e095814da2b3ed71a9` merged and published at `db0234f001225496bc5c1ad34fa475b550849160`. Twelve targeted simulator tests pass. Native pointer attempts did not establish physical gesture completion.
- Optional commander assembly delivery `ec6a05c6015eb38410697d69b3772453227939f5` merged at `08b4f980462c9c73a6a72d81de04b7d25efcfed4`; merged tree `01a3d6779056cf68017a12ecae2c025b68966d63`. Its exact captured source `7a4247c` passed fourteen tests. Combined regression passed all sixteen discovered tests, zero failures/skips, against current LMKit main; see `Docs/Validation/CommanderStationCombined/`.

## Accepted model components

| Component | Original delivery | LMKit package acceptance | Remaining limits |
|---|---|---|---|
| DSKY | LM `c655fe5` | `d8e35fa` | Rear housing and receiving cutout unverified |
| FDAI | `c4c565f` | `c75d379` | Provisional dimensions/pivots; unsupported runtime needles hidden |
| ControlLibrary | `3963737` | `75bdea7` | Generic family geometry, provisional mounting; guard not verified flight hardware |
| Cabin | `8956702` | `75bdea7` | Open skeleton, provisional panel envelopes/clearances and pane separation |
| HandControllers | `750caea` | `3ad1a99` | ACA maximum envelope only; TTCA dimensions and installation provisional; no runtime bindings yet |

Original history and source evidence remain in LMKit. Cabin manifest positions/rotations are Cabin-root-relative, including nested instrument reservations.

## Assembly and runtime gates

`--commander-station-assembly` opts into the skeleton. Normal startup retains existing registration. Optional installation preserves actual live instrument entities, key dictionaries, internal transforms, functional controls and independent LPD grids. It relocates instrument parents to the forward reservations after the initial crew-eye capture exposed occlusion. Panels 1/4 backing and glare shields remain omitted pending fit. Two generic control specimens are explicitly visual-only with no input components.

Final front/side/calibrated-eye captures show both complete faces, but DSKY viewing/reach remains oblique and cockpit materials dark. Photometry, mechanical fit, pressure closure, headset stereo, gaze/pinch and performance remain unqualified. Synthetic adapter/FIFO tests and real Luminary responses do not establish OS gesture recognition.

Evidence: `Docs/CommanderStationAssemblyHandoff.md`, `Docs/Validation/CommanderStationAssembly/`, `Docs/InstrumentInteractionReadabilityHandoff.md`, `Docs/Validation/InstrumentInteraction/`.

## Active coordination and next work

- All workers run locally; ewsbuild is no longer used.
- Assembly task `01a08296-4048-7503-b057-03345be7d15b` completed the combined regression and released the simulator slot. Serialize simulator test/capture jobs; concurrent clones previously interfered with both workers.
- Interaction task `01a08296-4c42-7dd0-b073-dfd4b3712bbf` delivered and released its simulator.
- No heavy render/bake is active. Continue limiting heavy jobs to one per machine; independent light headless authoring can run concurrently.
- Publish the accepted assembly merge with its verification record, then scope hand-controller runtime installation in LM against accepted mounting and existing simulation input APIs. ACA runtime integration has now been dispatched below; TTCA remains an audit.
- Do not infer switch/controller semantics from geometry names or invent unavailable dynamics. Component workers keep assigned asset-directory ownership; coordinator handles shared APIs and master assembly.

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

Panel schema separates Cabin-relative panel poses from parent-local equipment slots, placeholder meshes and optional PlanningLabels. External working instruments/surrounds are occupants, never duplicated in the blank model. Descent-ready closed-cabin state is the phase baseline, with optional inspection cutaways. Coordinator owns shared packaging, normal-interior promotion, placeholder fallback and combined verification; none of these new deliveries is complete yet.

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
