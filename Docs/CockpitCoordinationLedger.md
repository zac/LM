# Cockpit coordination ledger

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
