# Cockpit asset contract, draft v0

This is the shared authoring contract for component workers. It supplements the existing app contract and research. It does not certify unknown historical measurements. Read [coordination](../../Docs/CockpitCoordination.md) before editing.

## Ownership and files

Each component owns one directory under `Components/`. Keep its `.blend`, modeling scripts, source textures, selected `review/` images, `HANDOFF.md` and evidence record together. Use a `renders/` or `scratch/` directory for disposable outputs. These paths and Blender numbered backups are ignored. `.blend` files use Git LFS.

Only integration owns `Assembly/`. Component workers deliver local component models and agreed attachment transforms. They do not edit the assembled cabin or production application assets. Linked Blender dependencies must use relative paths and accepted component revisions.

## Units, hierarchy and placement

- Real meters. Final USD has an identity-scale root and the app convention +X toward LMP/right, +Y overhead, -Z forward.
- Blender's native working axes may differ. Record the export transform and verify orientation with asymmetric markers. Do not merely relabel metadata.
- Final cabin root is `LM_Cabin`. Preserve the names required by `LM/LMCockpitAssetContract.swift`; the integration owner reconciles new names.
- Each component has a declared local origin and mounting transform. Do not infer the global placement of a standalone instrument from its local modeling origin.
- Each moving part has an independent pivot transform and mesh. Fixed housings, bezels and indices stay separate.
- Freeze interface dimensions for a specific assignment before dependent components rely on them. Unknown travel, pane spacing or mounting geometry stays marked provisional.
- Preserve the existing two-pane LPD and commander eye basis. Software tolerances are not historical survey accuracy.

## Control and display ownership

AGC provides computer semantics and computer output. LMCore provides vehicle simulation. The app translates gestures into existing runtime input and renders snapshots. Do not embed a second DSKY interpreter or flight model in component scripts.

Keep keys, toggles, guards, rotary parts, breakers, needles, FDAI ball and display/lamp regions independently addressable. Record axes, travel, detents, return behavior and indicator dependencies. Do not claim a control is simulation-bound based solely on geometry or an animation.

## Evidence and acceptance

Each assembly records its source URLs, page/photo IDs, vehicle/revision, and measured versus inferred dimensions. Later-mission substitutions are allowed when identified. Historical disagreements remain explicit.

The minimum modeling handoff is a cleanly reopening source file, all dependencies, stable names/pivots, representative reference comparisons and a completed handoff report. Export checks and runtime tests are separate milestones. The final integrated asset must be tested in the native app and on Vision Pro before claiming interactive acceptance.

Sources: [research dossier](../../Docs/Research/LunarModuleInterior/README.md), [pipeline analysis](../../Docs/Research/LunarModuleInterior/blender-usdz-visionos.md), [window calibration](../../Docs/CommanderWindowCalibration.md).
