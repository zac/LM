# Cockpit coordination

**2026-09-08 update:** Model ownership now lives in the separate LMKit package. See [LMKit integration](LMKitIntegration.md). This LM worktree remains the application integration coordinator; the original in-repository component layout below records the initial worker assignments. New model workers should target LMKit.

This worktree is the coordination and integration checkout for the interactive lunar module interior. Its persistent branch is `cockpit/integration`. Initial app baseline: `89ecb0fe641292640a56e37ddf72587c342a4066`. The research was prepared on that baseline; this is not a claim that the in-progress LunarMap extraction or AGC merge is integrated here.

## Architecture and scope

- The existing AGC runs the guidance computer and owns DSKY semantics and computer output.
- LMCore supplies flight dynamics and vehicle simulation.
- LunarMap will supply the extracted Moon rendering when its accepted revision is available.
- Blender supplies geometry, materials, independently moving parts and calibration datums.
- The native RealityKit application binds controls to the existing runtime and presents its state.

Start with [the research dossier](Research/LunarModuleInterior/README.md), [the asset contract](../Assets/Cockpit/CONTRACT.md), and [the coordination ledger](CockpitCoordinationLedger.md). This checkout owns the master assembly, shared contracts, final USDZ and application integration. Component workers use separate worktrees or clones.

## Branch and file ownership

These component branches are planned, not created or dispatched by this setup. Each starts from an explicitly recorded coordination commit after the assigned contract is reviewed.

| Branch | Exclusive asset directory | Scope |
|---|---|---|
| `cockpit/dsky` | `Assets/Cockpit/Components/DSKY/` | Housing, 19 keys, face, display and indicator regions |
| `cockpit/fdai` | `Assets/Cockpit/Components/FDAI/` | Reuse existing ball where suitable; housing, fixed indices and independent needles |
| `cockpit/control-library` | `Assets/Cockpit/Components/ControlLibrary/` | Toggles, guards, rotary controls, breakers, buttons and talkbacks |
| `cockpit/panels` | `Assets/Cockpit/Components/Panels/` | Plates, cutouts, legends and placement of accepted components |
| `cockpit/cabin` | `Assets/Cockpit/Components/Cabin/` | Shell, deck, hatch, windows, glareshields, armrests and mounting locations |
| `cockpit/hand-controllers` | `Assets/Cockpit/Components/HandControllers/` | ACA and TTCA assemblies and mechanisms |
| `cockpit/integration` | `Assets/Cockpit/Assembly/`, shared contract, app bindings | Master cabin, reconciliation, acceptance and final export |

Each worker owns its modeling scripts, source textures, source `.blend`, review images and evidence within its directory. No two workers edit the same `.blend`. Existing production assets are inputs to inspect and copy into the assigned component workspace; changing shared production assets requires an integration decision. Workers propose contract changes in their handoff rather than changing other components to compensate.

The controls library can start immediately. Panel research and transcription can proceed concurrently; placement should use a recorded accepted controls-library revision. Do not copy unpublished files from another worker's live directory.

## Dispatch and merge protocol

1. The coordinator records worker task, machine, branch, exact starting commit, owned paths, contract revision, dependency revisions and acceptance criteria in the ledger.
2. The worker uses an isolated checkout. Research and model work stay within the assigned directory. Workers may inspect shared sources.
3. The worker produces a handoff using [the template](CockpitComponentHandoff.md). It records the exact delivered commit, files, unresolved dimensions, validation and remaining behavior gaps.
4. The coordinator reviews the diff and evidence, checks the asset contract, and merges the selected revision locally into `cockpit/integration`.
5. Dependent workers update from the accepted integration revision at an agreed checkpoint. Avoid rebasing or replacing another active worker's branch.
6. Only the integration owner updates the master Blender file, final USDZ, shared contracts and application bindings.

The setup does not authorize pushes, PR creation, remote-machine changes or task dispatch. Those can be authorized as the worker plan is put into operation. Local coordination commits are part of maintaining this checkout.

## Multiple computers

Each computer uses its own clone with Git LFS installed and required objects fetched. Worktrees isolate multiple workers on one computer; they do not share files across computers. When remote publication is authorized, exchange commits and LFS objects through the repository remote. Record delivered commit SHAs instead of relying on branch names alone.

Use the same recorded Blender version and required add-ons on all modeling machines. Store linked component and texture paths relative to the repository. Avoid home-directory paths inside Blender assets. Large generated renders and scratch files stay in the ignored `renders/` and `scratch/` directories. Keep small selected review images in `review/`, where they can be committed with the handoff.

The separate AGC repository needs an explicit accepted revision for integration builds. The current app uses a sibling package path; isolated worktrees may not resolve that path automatically. Resolve the local dependency arrangement before building and record it. Do not modify the shared AGC checkout or its branch from an asset task.

## Rendering policy

Initial policy: at most one heavy render or bake per machine. Several workers can research and write scripts, but a worker must obtain that machine's render slot before starting a heavy Blender process. This is a scheduling policy, not an implemented queue or a measured hardware limit.

The coordinator records slot ownership in the ledger for local work. Separate computers require a common scheduling channel or centrally managed queue before unattended rendering. Use small preview jobs first; record peak memory, render time, scene complexity and machine identity before raising concurrency. RAM capacity alone does not establish how many concurrent scenes are practical.

## Integration gates

Asset authoring can proceed now. Defer changes to the Xcode project, package wiring and cockpit/terrain integration until the LunarMap extraction and AGC/LMCore baseline have validated, accepted commits. Read current APIs at that point; older research code pointers are not a frozen API guarantee.

First combined milestone: commander station with a connected DSKY, live FDAI, representative controls and calibrated window. Verify separate input, AGC execution, LMCore state, rendered output and on-device interaction. A Blender render or successful USDZ preview alone does not satisfy this milestone.
