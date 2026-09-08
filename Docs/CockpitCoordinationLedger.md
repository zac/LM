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
- Publish the accepted assembly merge with its verification record, then scope hand-controller runtime installation in LM against accepted mounting and existing simulation input APIs. That runtime task has not been created.
- Do not infer switch/controller semantics from geometry names or invent unavailable dynamics. Component workers keep assigned asset-directory ownership; coordinator handles shared APIs and master assembly.

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
