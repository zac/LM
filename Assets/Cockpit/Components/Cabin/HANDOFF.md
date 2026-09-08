# Cabin structural blockout handoff

## Scope and provenance

Owned directory: `Assets/Cockpit/Components/Cabin/` only. Branch `codex/cabin-structure` created because the provisioned worktree was detached; verified clean baseline `d8e35fa3ec8dc400cbb2762c24953022b07e8ebb`. Main was not checked out or modified. Git LFS 3.8.0; Blender 5.2.1 LTS build 9e2066aef7ef. No heavy render/bake was started.

Exact asset commit: recorded after the asset commit in the final handoff-only commit.

New authored geometry, not an import of the legacy exterior. Consulted LM revision `ed230a6ee4286bc2385f44bc8f1889bdcc39a8ab`. Exact local evidence snapshots, byte counts and SHA-256 hashes are in `evidence/sources.json`; source manifests preserve original URLs and photograph scan provenance. `capture_evidence.py` documents the source paths used. No app calibration, AGC, LMCore, DSKY, FDAI, package Sources/Tests/Tools or master assembly was edited.

## Files and regeneration

- `DATUM.md`: written measurement/coordinate freeze established before modeling, with historical qualifiers and legacy deltas.
- `build.py`: reproducible Blender builder, direct USD exporter and small Workbench previews. Run from the repository root: `blender -b --factory-startup --python Assets/Cockpit/Components/Cabin/build.py`.
- `Cabin.blend`: editable metric source, separate mesh/empty hierarchy, three review cameras, no external textures, linked libraries or add-ons.
- `Cabin.usda`, `Cabin.usdc`, `Cabin.usdz`: equivalent neutral geometry, Preview Surface materials, 74 meshes / 872 triangles. No lights/cameras, state bindings or baked illumination exported.
- `mounts.json`: exact proposed scene positions, pitch and stable USD paths. DSKY/FDAI mating surfaces and cutouts are explicitly null.
- `reviews/REVIEW.md` and front/side/crew-eye PNGs: dimensions, photo comparisons, camera states and remaining gates.
- `validate.py`, `validation.json`: 1,028 successful checks, artifact hashes and physical bounds.
- `validate_native.swift`, `validation-native.json`: macOS RealityKit load, ten proposed mount transforms, CDR eye and pane normal checks, separate LPD nodes.

Validation commands: `blender -b --factory-startup --python Assets/Cockpit/Components/Cabin/validate.py`; compile native checker with `xcrun swiftc -module-cache-path /tmp/cabin-swift-module-cache -parse-as-library Assets/Cockpit/Components/Cabin/validate_native.swift -o /tmp/cabin-validate-native`, then run that executable with the absolute Cabin.usdz path. Blender may print an exit code of zero on Python exceptions: require the PASS line and refreshed validation report. On this host Blender and RealityKit required execution outside the sandbox; Swift's cache was directed to /tmp.

## Coordinate and mounting interface

USD root `/Cabin` has identity transform/scale, meters, +X LMP/right, +Y overhead, -Z forward. Native Blender authoring is +X right, +Z overhead, +Y forward; exporter physically maps `(x,y,z)` to `(x,z,-y)` for points, normals and every local transform. Validation compares every exported world matrix against the authoring scene, then reimports and checks every transform and physical bounds. Axis metadata alone is not used as proof.

Eye: `/Cabin/Optical/CDR_Eye` at (-.5588,1.78,-.38). `/Cabin/Optical/CDR_Window_Inner` and `CDR_Window_Outer` originate at respective upper-outboard pane corners. Local +X follows the top edge inboard, local +Z points toward eye. Each has its own child `LPD_Inner` / `LPD_Outer` mounting node; no grid or simulation is duplicated. CDR pane corners exactly preserve the existing reconstruction; both sets of corresponding rays collimate. Outer plane offset .020 m is provisional. LMP panes are an explicitly proposed mirrored reconstruction.

`/Cabin/Mounts/Mount_Panel_1` through `Mount_Panel_6` are face-centered mount origins, local +Z toward crew. Their blank backing meshes extend into local -Z. DSKY and FDAI reservations are children of Panel_4 and Panel_1 respectively; their origins are proposed legacy display-origin offsets, NOT surveyed mounting planes. Named middle-tier mounts remain unnumbered pending inventory reconciliation. Every panel and optical layer remains independently addressable. Moving the DSKY reservation group was verified to move its children without moving the deck. No actuation/hinge geometry belongs to this delivery.

Visual bounds in meters: min (-1.18336946, .07750000, -.99266378); max (1.18336946, 2.28336962, .58680000). Barrel diameter nominal 2.3368 m, depth 1.0668 m; outer visual thickness and forward nose projection explain the larger visual envelope. Do not scale the asset to the visual bounding box to recover nominal diameter.

## Evidence limits and acceptance

Apollo 11 press-kit dimensions and 1967 Grumman relationships are distinct from proposed mesh dimensions. The preserved LM code is compatibility evidence, not automatic historical truth. Panel forward placements and tall shields deliberately differ from legacy geometry, as documented in DATUM.md and the installed-photo review. LM-10-derived panel sizes remain provisional, not certified LM-5 outlines. Apollo 16 photo use is limited to qualitative floor/threshold relationship; no later equipment is silently substituted.

This is a forward structural mounting skeleton with open aft termination and incomplete forward skin. It is not a pressure-tight hull, complete aft cabin, exterior replacement, hatch-swing model or certified instrument installation. No switches, hatch leaf, docking window, full side-panel catalog or master assembly is included. The coordinator should resolve forward shell closure/nominal-depth registration, exact panel boundaries, shield profile, mechanical clearances, pane cavity and hatch radii before detailing or accepting the proposed mount positions.

USDZ ARKit compliance: zero errors, failed checks or warnings. All authored solids are closed, nondegenerate and outward wound; the assembled skeleton is intentionally open. Native macOS RealityKit checks passed; Vision Pro optical/interaction, RCP GUI, calibrated materials, collision/egress and mechanical fit were not tested. Shared package packaging/resource refresh is coordinator-owned; `Tools/sync_dsky.py` was not run because DSKY and packaged resources were unchanged.

Publication is limited to this component branch and its required LFS objects on LMKit origin. No merge or main push is authorized or performed. Final branch head and remote verification are reported after publication.
