# LMKit

Reusable lunar-module models and independently addressable cockpit components for RealityKit. LMKit owns model authoring and packaged geometry; the LM application owns presentation/input bindings, AGC owns computer behavior, and LMCore owns flight dynamics. This package has no AGC or LMCore dependency.

## Commander instruments and interior detail

New components keep authored geometry separate from LM-owned state and input bindings:

| Component | Resource APIs | Placement / meaning |
|---|---|---|
| Altitude / altitude-rate tapes | `altitudeRateURL`, `altitudeRateInterfaceURL` | Panel1__RangeThrust partial region; explicit moving rows and unavailable-data shutters. Landing-focused scale pitch and metric fit remain provisional. |
| PGNS mode and DES RATE | `attitudeModeURL`, `descentRateURL`, `descentControlsInterfaceURL` | Source-correct Panel3__Stability and Panel5__Engine partial regions. AUTO/ATT HOLD and momentary DES RATE; OFF unsupported, no engine behavior. |
| Commander cross-pointer | `crossPointerURL`, `crossPointerInterfaceURL` | Panel1__CrossPointer; independent needles, explicit later-inspired LO landing reconstruction, not verified Apollo 11 signal wiring. |
| Interior fittings | `interiorDetailsURL`, `interiorDetailsInterfaceURL` | Optional Cabin-relative cable/clamp/trim overlay; independent groups, no slot suppression or simulation. |
| Breaker banks | `breakerBanksURL`, `breakerBanksInterfaceURL` | Optional source-guided Panel11/16 terraces; per-slot occupants, static hardware without electrical behavior. |

Read each component's `HANDOFF.md` and `interface.json` before placement. A resource name never establishes an input binding. Partial-region instruments retain surrounding blanks; optional overlays must fail independently from the working station. Refresh accepted assets with `python3 Tools/sync_landing_station.py AltitudeRate DescentControls CrossPointer InteriorDetails BreakerBanks`, then `python3 Tools/sync_dsky.py` and `swift test`. Every new packaged resource is byte-identical to its authoring export; each directory includes a hash receipt.

The current scope and worker ownership are in [the phase plan](Docs/TwoHourCockpitPriorities.md). The historical filename is retained; user timing guidance supersedes its original two-hour proposal. Priority and safe parallelism determine work order, with no estimated-time cutoffs.

## Initial components

- **Commander panel surrounds**: provisional Panel 1/FDAI and Panel 4/DSKY backing/openings from `6c8c271`, via `LMKitAssets.commanderPanelsURL` and `commanderPanelMountsURL`. Install once at Cabin identity while keeping original Panel 1/4 reservations disabled. The 3 mm visual-envelope allowance and narrowed Panel 1 outline do not qualify instrument seating, structural attachment or runtime control clearance. Refresh with `Tools/sync_commander_panels.py`; rebuild only against pinned source references.

- **Hand controllers**: ACA and TTCA prototypes from `750caea`, via `LMKitAssets.handControllerURL(_:)` and `handControllerInterfacesURL`. Separate nested pivots support future input adapters; no runtime bindings or cabin placements are included. Neutral origins are parent-local. ACA has a program-level maximum-envelope reference; TTCA dimensions, mechanism coupling and motion limits remain provisional. Refresh accepted exports with `Tools/sync_hand_controllers.py`.


- **Control library**: six reusable neutral control specimens from `3963737`: maintained/momentary toggles, guarded switch, rotary selector, circuit breaker and talkback. Load with `LMKitAssets.controlURL(_:)`; metadata is at `controlInterfacesURL`. Every mounting dimension is provisional and the generic hinged guard is not verified flown hardware. Detents, returns and indication semantics require per-panel application bindings. Refresh accepted exports with `Tools/sync_control_library.py`.
- **Enclosed cabin foundation**: closed provisional shell and hatch surfaces from `b240f05`, via `LMKitAssets.cabinURL` (`cabinSkeletonURL` remains a compatibility alias), `cabinMountsURL`, `cabinInterfaceURL` and `cabinMigrationURL`. Replaces the prior open skeleton. Original mount/optical metadata remains; old visible panes, frames, marks and panel reservations have been removed. Load glazing and panels independently at the same datum. **Mount positions and rotations are Cabin-root-relative, including nested DSKY/FDAI nodes; they are not parent-local.** Six named cutaway groups allow inspection. Refresh with `Tools/sync_cabin.py`.

- **Windows and LPD**: independently addressable panes, hardware and approximate physical marks from `b794640`, via `windowsURL`, `windowInterfacesURL` and `windowManifestURL`. Install once at shared Cabin identity. Only commander panes carry marks. Neither the new artwork nor the old app geometry is angular-targeting qualified. Consumer must suppress old panes/frames/grids and synthetic projected indicators. Refresh with `Tools/sync_windows.py`.

- **Panel inventory**: 28 groups and 66 separately replaceable blank regions from `0c58843`, via `panelInventoryURL` and `panelInventoryManifestURL`. Resolve full paths; preserve panel frames and independently switchable planning labels. Check `replacement_allowed` before replacing a blank: the Panel 5 timer remains an empty, blocked reservation because of ACA clearance. DSKY/FDAI/ACA are external occupants, not embedded copies. **Explicitly set the planning-label root disabled on RealityKit load.** The shipping USDZ derives from the accepted authoring export with only `/PanelInventory/PlanningLabels.visibility` changed to `inherited`: RealityKit retains the text meshes but the authoring `invisible` opinion prevents text from rendering even after `isEnabled=true`. `packaging.json` records source/output hashes; the manifest still requests labels hidden by default. Refresh with `Tools/sync_panel_inventory.py` (requires Apple `usdcat`).


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

## Current acceptance evidence

Thirteen package test functions cover the accepted resource set, including two parameterized functions with six new-resource cases each. The new component checks load actual USDZs without interaction/physics ownership and verify packaged bytes against accepted source exports and hash receipts. Native RealityKit checks load controls, hand controllers, surrounds, enclosed cabin, windows and panel inventory; verify independent moving/removable nodes, full cabin/panel/slot transforms, optical pane bases, crew eye, separate LPD layers, removed legacy visuals and blocked reservations. App-level replacement/fallback behavior and final combined appearance require separate LM validation. Shipping asset bytes match accepted authoring exports except the documented PanelInventory planning-visibility derivation; its canonical layer changes exactly one property. This establishes packaged resource compatibility, not historical fit, final panel placement, live simulation behavior or Vision Pro acceptance. Per-delivery acceptance records are under `Provenance/`.
