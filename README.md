# LMKit

Reusable lunar-module models and independently addressable cockpit components for RealityKit. LMKit owns model authoring and packaged geometry; the LM application owns presentation/input bindings, AGC owns computer behavior, and LMCore owns flight dynamics. This package has no AGC or LMCore dependency.

## Initial components

- **FDAI**: standalone component from `c4c565f`, available through `LMKitAssets.fdaiURL`. Eight independent moving groups; all physical dimensions and pivots remain provisional. New ball UV mapping needs an explicit runtime adapter; do not blindly reuse the legacy texture-alignment quaternion. Live state/calibration and Vision Pro appearance remain open. Use `Tools/sync_fdai.py` after accepted source export changes. See `Provenance/fdai-acceptance.json` and the component handoff.

- **DSKY**: imported from `zac/LM` commit `c655fe5` (full SHA in `Provenance/imports.json`). Source Blender file, reproducible scripts, evidence, preview exports, validation and handoff are under `Assets/Cockpit/Components/DSKY/`. Only the neutral `DSKY.usdz` ships as a runtime resource. The original worker reported 276 checks and native loading; this package separately tests its bundled asset. Live AGC, hover/pinch bindings and Vision Pro verification remain unimplemented. Rear housing and mounting aperture remain provisional; do not derive a panel cutout from that box.
- **Legacy exterior**: exact `lm.usda` wrapper and `lunar_module.usdz` bytes imported from LM commit `97f877b`. Retains Physics, lunarlander, DPS and RCS hierarchy. Existing scale, coordinate registration, center-of-mass calculations and simulation behavior stay with LM. This is the starting model to improve incrementally, not a claim of historical fidelity.

The import is an explicit baseline from pre-existing work, not a claim that all assets were created during a hackathon. Original commits and file hashes are preserved in the provenance manifest; original Git history remains in `zac/LM`. Third-party/source-image rights and original legacy-model authorship have not been newly established by this extraction; no blanket license is assigned to those references.

## Use

Clone LMKit next to LM (and AGC) and install Git LFS, then run `git lfs pull`. LM currently references `../LMKit`. Use `LMKitAssets.legacySceneURL` with `Entity.load(contentsOf:)` to preserve wrapper composition; use `LMKitAssets.lunarModuleURL` for a static exterior preview and `LMKitAssets.dskyURL` for the neutral component. Assets retain subdirectories and relative USD references through SwiftPM `.copy` resources.

Run `swift test` on macOS. Tests load the actual packaged assets in RealityKit and check the simulation and key hierarchy. After regenerating the DSKY, run `python3 Tools/sync_dsky.py` to refresh its shipping copy, then test. Do not ship static look-development previews as live instrument state.

## Component workflow

Workers own one component directory and a separate branch/worktree. Commit source assets through LFS, scripts, small review images, evidence and HANDOFF.md. Deliver an exact SHA to the coordinator; only the coordinator accepts component changes, refreshes shipping resources, edits shared contracts or builds the master assembly. One heavy render per machine initially. Keep disposable renders and scratch files ignored.

Keep imports and new work distinguishable. Record source revision, dimensions, axes, pivots, moving parts, materials, bounds, packaging hashes, validation actually performed and unresolved issues. Preserve names consumed by LM until a coordinated replacement updates and verifies its bindings.
