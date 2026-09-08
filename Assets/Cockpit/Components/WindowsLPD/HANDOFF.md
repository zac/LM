# WindowsLPD enclosed-cabin handoff

Branch `work/windows-lpd-enclosed`, based on requested `09364460e8be570338f3d39a07067fe2bee0b044`. Owned changes exclusively in this directory. No app/shared Sources/Tests/Tools/master changes, no simulator, no merge or push. Shared mesh/export helper provenance is recorded in build.py.

## Import contract

Import `WindowsLPD.usdz` once at identity under the same datum as Cabin. Meters, +X right/LMP, +Y overhead, -Z forward. Blender authoring uses (x,-z,y); exporter physically transforms bases/mesh points back to Y-up, not only metadata. Root `/WindowsLPD` has identity transform. `manifest.json` provides all four forward pane positions/bases and per-mesh bounds; `interface-v1.json` provides eye, opening, docking, visual layout and qualifications.

Forward sharp construction triangles/eyes agree with Cabin `2fafa5b`; early window interface `8dc1b6c` was accepted for forward and docking aperture. Corrected interface `80c9b2d` changes docking local up to +Z (aft), retaining right and inward normal, giving determinant+1. Symmetric rectangular hole is unchanged. Interface SHA256: `28bb74258353bbc8365b7a54011782332ff69927c0683154a46b80b8ad24f22f`.

Cabin owns shell holes only. Remove old Cabin and app window panes, frames and marking meshes when importing this component. Forward frame edges extend32mm perpendicular to the sharp triangle edges; miter corner extents extend farther, recorded in bounds. Overall visual bounds approximately X ±1.074765m, Y1.259509–2.184244m, Z−1.014466–−0.009900m. Confirm nearby panel and shield clearance in combined assembly, especially lower miter tips. Forward normal depth stays within agreed −40..+18mm. Docking pose/axis assignment remains approximate, with nominal5x13in view and curved inner pane.

Stable hierarchy:

- `/WindowsLPD/Datums/CDR_Eye`, `LMP_Eye`
- `/WindowsLPD/CDR_FlightWindow/CDR_Hardware` and corresponding LMP hardware: separate structural frame, retainers, black edge, individually named fasteners and slots
- `CDR_Window_Inner` / `CDR_Window_Outer`: independently addressable glazing; `LPD_Inner` / `LPD_Outer` are children of their respective pane nodes
- `LMP_Window_Inner` / `LMP_Window_Outer`: no LPD
- `/WindowsLPD/DockingWindow`: independent retainer, black edge, curved glazing layers and uncalibrated optics datum; no invented docking reticle

Each forward inner pane includes separately addressable visual defog bus bars. No live bindings, switches, controllers or simulation behavior are inferred from names.

## Appearance and migration

`EVIDENCE.md` is the controlling evidence audit, with immutable sources/crop/page locators and hashes in `evidence/sources.json`. Warm thin nonemissive marks approximate the observed NASA-hosted photograph; exact pigment/colorimetry is unknown. Black peripheral paint and coating functions are supported by the structural report. The blue-red coating label does not establish colored ink. The old assertion that the second horizontal bar is only a displaced zero bar conflicts with the later photograph, which visibly has bars near0 and50. Mission applicability of that photograph is uncaptioned.

Both old and new geometry are UNVERIFIED optical reconstructions. Eye and plane datum migration delta is zero, but the physical visual scale layout changes. Old angular projection put the newly restored lower bar into the frame, so the new layout uses a contained photo-inspired mapping documented in `interface-v1.json.marking_layout` and build.py. Outer artwork is projected from inner through the comparison eye for paired alignment; that does not certify the degree numbers. Do not use imported degree labels for numeric targeting, and do not present the old app reconstruction as calibrated either. Preserve explicit, qualified training comparisons separately.

The imported component owns physical marks exactly once. Use presentation worker’s `setLandingPointMarkingOwner(.importedWindows)` seam, suppress all procedural grids/labels and projected digital targeting indicator while imported owner is active. No neon diagnostic materials or digital indicators are present in this USDZ. App diagnostic palette belongs only to optional training UI.

## Validation and review

- Reproduce: `blender -b --factory-startup --python Assets/Cockpit/Components/WindowsLPD/build.py`.
- Structural validation: run `validate.py` with Blender. PASS meter/Y-up stage, identity/proper rotation transforms,194 meshes, finite vertices/indices, bound materials, zero cameras/lights, independent layers, all marking/label vertices inside rounded glass (minimum clearance13.59mm). `validation.json` includes binary/source hashes.
- Native macOS RealityKit load: compile/run `validate_native.swift` with USDZ path. PASS pane positions and complete right/up/normal bases, separate LPD parentage and root scale. See `validation-native.json`. This is not visionOS/headset validation.
- `review.py` produces seven small Workbench views: front/side/commander/pilot/rear/overhead/CDR closeup. Inspected shape, frame depth, separate parallax layers, no LMP marks, outward opening. Glass hidden only for these geometry reviews, and cameras never saved/exported. Wide-angle eye reviews avoid pretending a narrow screenshot covers the full window envelope.
- `review_native.swift` loads delivered USDZ in macOS SceneKit and renders640px checker comparisons with/without glass. Both images inspected: exterior checker remains visible through both panes with modest tint; no opaque pane or gross compositing obstruction. This exercises native USDZ transparency but is not a RealityKit reflection/photometry or headset test.
- Appearance remains an approximation: frames intentionally simplified, no production fastener count or mechanical fit claim; glass opacity/roughness are renderer choices. Photo closeup remains the comparison source rather than an assertion of exact replica.

Coordinator owns `Tools/sync_dsky.py`, package resource refresh/tests, complete combined shell/panel sightline and clearance review, and serial LM integration. Those shared packaging checks are intentionally not executed from this component-owned worktree. Stereo eye position, gaze/pinch, reflection under final cabin lighting, on-device transparency/performance, and physical headset acceptance remain untested.
