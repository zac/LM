# ControlLibrary handoff

Status: six authored families; local Blender/USD and macOS RealityKit validation passed. Component branch: `codex/control-library`. Base: `d8e35fa3ec8dc400cbb2762c24953022b07e8ebb`. Exact asset commit is recorded below after publication.

## Proposed interface for coordinator acceptance

Each `<Family>.usdz` has default prim `/<Family>_Mount`, at identity and unit scale. Place that root at the front surface of the host panel. USD uses meters, +X right, +Y overhead, -Z forward. The panel lies in local XY; controls protrude toward the crew in **+Z**, and equipment bodies extend behind the panel in **-Z**. Authoring uses Blender X right/Z overhead/+Y forward. Export converts every local transform by conjugation and every vertex/normal using `(x,y,z) -> (x,z,-y)`; validation checks actual coordinates, not only axis metadata.

Children are prefixed `<Family>__`, e.g. `MomentaryToggle__Actuator`. `components.json` lists independently addressable nodes. Housing, actuator and guard have separate transforms; individual moving geometry is parented beneath its moving node. Clone a family with a unique panel-instance root; preserve its internal names beneath that root. Proposed instance names are `PanelNN_Control_<referenceDesignator>`. Neither panel numbers nor real reference designators are assigned here.

| Family | Moving node(s), relative to mount | Neutral pose / limits | Provisional mounting proposal |
|---|---|---|---|
| MaintainedToggle | Actuator pivot `(0,0,0.009)` m | X rotation 0°; maintained detents −17°,0°,+17° | 9 mm round aperture; 27 mm rear clearance |
| MomentaryToggle | Actuator pivot `(0,0,0.009)` m | X rotation 0°; −17°,0°,+17°; release returns center, timing unknown | 9 mm aperture; 27 mm rear clearance |
| GuardedSwitch | Actuator `(0,0,0.009)`; Guard `(0,0.021,0.006)` m | Actuator −17° neutral / ±17° detents. Guard X 0° closed, −100° open; proposed actuation threshold ≤−90° | 9 mm aperture; 27 mm rear clearance; separate bracket attachments unresolved |
| RotarySelector | Actuator `(0,0,0.003)` m | Z rotation −15° neutral; −45°,−15°,+15°,+45° | 10 mm aperture; 34 mm rear clearance; 36 mm skirt diameter |
| CircuitBreaker | Actuator `(0,0,0.0065)` m | Add +Z displacement 0…0.005 m; black knob retained, aluminum band exposed when pulled | 10 mm aperture; 32 mm rear clearance; 12 mm knob diameter |
| Talkback | Indication at identity; child BarberPole | Gray neutral: BarberPole Z −0.002 m. Striped: set Z +0.002 m | 21×13 mm viewing window; 18 mm rear clearance; nominal 26×19 mm housing; rear mounting required |

The talkback window is a viewing aperture, not a through-hole for inserting its larger housing. Install from behind the panel; rear fasteners and clamping hardware are unresolved.

Rotation values are absolute relative to each pivot's parent; translation offsets for the breaker are relative to its neutral position. Positive X toggle rotation moves the tip downward in target Y. Standard 30° rotary detent spacing and approximately 5 mm breaker travel have program-level primary support; exact stops/placement and every mounting dimension remain provisional. The JSON bounds in `validation.json` are measured **model extents**, not measurements of flight hardware.

Guard dependencies are a host-interface proposal, not implemented logic. Its generic hinged cage is **not verified flown LM hardware**. Do not infer an automatic toggle reset on guard closure. Reserve and review the entire swept volume before panel placement; no guard collision/contact/ergonomic qualification is claimed. Talkback geometry supports independent visual state; its presentation translation does not claim a historical internal mechanism. Host code owns return, detent snapping, guard gating, breaker trip behavior and all simulation bindings.

## Evidence and deliverables

Editable source: `ControlLibrary.blend`; reproducible builder: `build.py`; reusable metadata: `parameters.json` and `components.json`; neutral exports: six `.usdc` / `.usdz` pairs. All Blender and USD files are Git LFS assets. No external textures, linked libraries, fonts or filesystem material dependencies. The inspection board, specimen labels and camera are source/review-only and absent from family USDZ files.

`evidence/source-manifest.json` records source bytes/hashes, research checkout and source URL. `evidence/ASSESSMENT.md` distinguishes documented mechanisms, later-mission substitutions and provisional geometry. No existing model commits have been squashed or rewritten. `review/inspection.png` shows the neutral specimens; `review/motion-examples.png` shows illustrative alternate poses. All rendering was lightweight Blender Workbench, no heavy render/bake.

## Validation and integration limits

- Blender 5.2.1: saved file reopened; no external file dependencies; meters; closed manifold meshes with outward winding and normalized USD normals; stable hierarchy; every local pivot and mesh point basis-converted and compared; identity mounting roots; housing behind/control front of panel; moving-node independence and restoration. 431 checks passed.
- All six neutral USDZs reopened, dependency-resolved and reimported with Blender's USD importer, with mounting roots and mesh counts preserved.
- macOS RealityKit loaded all six USDZs and verified unit scale, independent moving children, stationary housings and front/back geometry bounds. `native-validation.json` records the result.
- No Vision Pro runtime, hand input, historically accurate fit, material photometry, collision qualification or live binding test performed.
- Shared Sources/Tests/Tools, runtime resources and assembly were not edited. Coordinator must accept the mounting/name proposal, refresh its chosen runtime resources and run package validation. `Tools/sync_dsky.py` is coordinator-owned and is not a ControlLibrary exporter.

Acceptance gaps: flight-specific guard design; dimensioned hardware drawings; per-panel labels/reference designators; flight-specific lever-lock variants and breaker band chronology; physical talkback mechanism; guard sweep clearances. These are documented accuracy gaps, not hidden completion claims.
