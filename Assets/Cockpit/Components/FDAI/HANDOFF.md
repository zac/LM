# FDAI component handoff

## Delivery and scope

Standalone Apollo 11-targeted FDAI exterior, authored on `cockpit/fdai` in LMKit. Baseline: `d8e35fa3ec8dc400cbb2762c24953022b07e8ebb`, initially detached and clean. Origin: `https://github.com/zac/LMKit`. Only `Assets/Cockpit/Components/FDAI/` is changed. Coordinator accepts the returned commit before packaging, assembly or app integration.

- Editable source: `FDAI.blend`, including packed ball texture and review-only camera/lights.
- Neutral integration asset: `FDAI.usdz`; equivalent unpackaged `FDAI.usdc` plus `textures/fdai_8ball_albedo.png`.
- Reproducible authoring: `build.py`; validation: `validate.py`, `validate_native.swift`.
- Small reviews: `review/front.png`, `oblique.png`, `geometry.png`, `static-motion-demo.png`, `pitch-30.png`, `yaw-plus-90.png`, `yaw-minus-90.png`, `roll-30.png`.
- Static demonstration poses exist only in review renders. Neutral Blender and USD assets contain identity local rotations, no animation, drivers, physics, AGC state or inferred live bindings.

The prior FDAI task on ewsbuild was inspected read-only at `/Users/runner/Projects/lm/LM-fdai`: clean `cockpit/fdai`, HEAD `97f877b52bf569656c6798cff5790b7207c42af0`, only `.gitkeep` in its component directory; path history ended at `e191706`. Nothing was overwritten, discarded, cherry-picked or rewritten there. Its interrupted task was `01a0824c-08d2-7af0-8872-4bc107233169`. LMKit had no existing local/remote FDAI branch, so the requested branch name was available.

## Local interface

Both Blender and USD are deliberately authored **X right, Y top, Z toward crew**, in meters. Blender's usual Z-up authoring convention is not used: export uses `convert_orientation=False`, then explicitly marks the USD stage Y-up. Root `/FDAI_Mount` has identity transform. No cabin placement is baked in. These instrument-local axes are not NASA vehicle-axis names: the LM handbook describes vehicle roll Z, pitch Y, yaw X.

Origin is the **proposed panel seating plane**, at the center of the instrument. It is an authoring datum, not a verified historical mounting plane. Rear housing extends toward -Z. Do not cut a panel, derive clearance, or register a cockpit from this unqualified exterior envelope.

`interface.json` records all moving groups, local origins, axes and provisional sweep limits. All are direct children of `FDAI_Mount`; fixed geometry is beneath `FDAI_Fixed`.

| Group | Neutral origin (m) | Proposed visual control |
| --- | --- | --- |
| FDAI_Ball_Pivot | 0, 0, -0.008 | externally supplied quaternion |
| FDAI_RollBug_Pivot | 0, 0, 0.0448 | rotation about local +Z; separate roll readout |
| FDAI_Rate_Roll_Pivot | 0, 0.100, 0.020 | local +Z rotation, provisional ±27° |
| FDAI_Rate_Pitch_Pivot | 0.100, 0, 0.020 | local +Z rotation, provisional ±27° |
| FDAI_Rate_Yaw_Pivot | 0, -0.100, 0.020 | local +Z rotation, provisional ±27° |
| FDAI_Error_Roll_Pivot | 0, 0.046, 0.045 | local +Z rotation, provisional ±25° |
| FDAI_Error_Pitch_Pivot | 0.046, 0, 0.0455 | local +Z rotation, provisional ±25° |
| FDAI_Error_Yaw_Pivot | 0, -0.046, 0.046 | local +Z rotation, provisional ±25° |

The six pointers are modeled as pivoted galvanometer indications. Their hidden origins and sweeps are visual approximations, **not measured mechanism pivots**. Positive local rotations move the top pointer right, the right pointer down, and bottom pointer left. Application code must map calibrated fly-to indications and signs explicitly. The optional independent roll bug is geometrically available; its exact LM linkage has not been established. Do not infer its angle from a combined quaternion without checking the display convention.

Ball mesh: radius 0.050 m, origin at its center. UV zero pitch meridian faces +Z; positive texture latitude points +X, giving red caps at ±X. The neutral forward view is white above and black below. The imported texture is unchanged, but the sphere is retessellated and mapped explicitly. The old LM `FDAI.usda` used a radius of 0.0889 m; that was app geometry, not a verified flight-instrument measurement, and is not adopted here.

## Historical evidence and dimensions

See `evidence/research.md`, `evidence/sources.json`, `evidence/provenance.json` and `dimensions.json`.

- Apollo 11 AS11-36-5389 is the mission-specific appearance reference. Its perspective, glare and occlusion limit measurements.
- NASA LM-5 through LM-9 Systems Handbook drawing 10.4.3, PDF page 5 / printed 10-7, confirms the error-pointer arrangement and sphere-drive roles. It is a schematic, not an outline or installation drawing.
- The clearer Apollo 14 LM-8 photograph supplies octagonal trim, meter typography/layout and color detail. This is an explicit later-mission substitution, not proof of identical LM-5 detail.
- User-supplied CSM spacecraft 012 handbook and Apollo 8/16 links support comparisons and display interpretation. CSM Honeywell geometry and its inverted-wing reticle were not used as LM geometry. The LM crosshair and red side bands are retained.
- Nominal face width/height 146.05 mm (5.75 in) is **provisional**, based on an auction measurement of an early unflown Lear Siegler instrument. Full modeled bounds are 148.05 × 148.05 × 279.50 mm including seal and front pointers. The approximately 11-inch depth in that listing is also provisional and does not qualify this model's rear connector or panel cutout.
- All other physical dimensions, fasteners, chamfers, typography, optical depth, radii, materials and rear connector envelope are provisional. There are **no verified LM-5 mechanical dimensions** in this delivery. Metric units and measured file bounds are verified computationally, which is a different claim.

Historical gaps: exact lettering, roll-bug linkage, meter scale microgeometry, original optical stack, rear enclosure/connector/fastener geometry, power-off flag and electroluminescent behavior remain unqualified or unmodeled. No internal servo mechanism is modeled. This is a detailed exterior visual component, not a certified hardware replica.

## Reproduce

Run from the LMKit repository root with Blender 5.2.1 LTS (9e2066aef7ef):

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/FDAI/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/FDAI/validate.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/FDAI/review_orientations.py
mkdir -p Assets/Cockpit/Components/FDAI/scratch
xcrun swiftc -parse-as-library Assets/Cockpit/Components/FDAI/validate_native.swift -o Assets/Cockpit/Components/FDAI/scratch/validate-native
Assets/Cockpit/Components/FDAI/scratch/validate-native "$PWD/Assets/Cockpit/Components/FDAI/FDAI.usdz"
```

Blender requires host execution here; sandboxed startup crashed before running the script. Git LFS also required access to the shared repository's LFS temporary directory. LFS integrity passed before editing. The existing DSKY was inspected but not changed. `Tools/sync_dsky.py` was not run: no DSKY or shipping resource refresh belongs to this assignment.

## Validation and performance

`validation.json`: **1,012 passing checks**, including clean source reopen, packed dependencies, identity root, metric scale, nonzero faces, complete UVs, material bindings, independent motion at both sweep endpoints, 15 ball rotations across three axes, USD units/hierarchy/material bindings, no animation/cameras/lights, package texture, OpenUSD compliance and clean USDZ reimport. Exact SHA-256 values are in that report.

`native-validation.json`: macOS RealityKit loading passed, all eight moving groups were found as direct children with geometry, and changing their transforms left the fixed group unchanged. Native load plus checks took about 0.40 s. This is not rendered appearance or application integration testing.

Measured complexity: **39,118 triangles, 223 mesh objects, 9 used materials**, one 4096×2048 PNG. USDZ is approximately 2 MB. This is not a draw-call or frame-time budget qualification; the coordinator may batch static geometry after preserving required paths.

Final builder timings: source reopen ~0.013 s, USDZ Blender reimport ~0.043 s; export ~0.42 s. Small 800px review renders took ~0.17–0.55 s each; additional 600px orientation times are in `review/orientation-cost.json`. No peak memory or device GPU/frame timing measured. Process check found only Blender's thumbnailer, no active render. **Zero heavy renders and zero bakes** were used.

The original thin identification-plate bevel created degenerate faces and was corrected. USD glass opacity is explicitly 0.055; Blender's importer maps unconnected Preview Surface opacity to **transmission 0.945 / alpha 1**, as confirmed in importer source and round-trip checks. Source preview uses alpha-blended thin glass. Thus transparency is preserved semantically, but optical appearance can differ by renderer. No calibrated refraction or photometric equivalence is claimed.

## Coordinator integration

1. Accept the exact published component commit and retrieve its LFS objects. Load only `FDAI.usdz`, or keep `FDAI.usdc` beside its `textures/` directory. `evidence/LM-FDAI.usda` is the unchanged reference asset and is not a runtime entry point.
2. Keep `FDAI_Mount` as the placement transform; align the provisional datum only after measuring the intended cockpit. Shared resource APIs, packaging and assembly are coordinator-owned.
3. Bind the ball and each rate/error group explicitly from the existing application/AGC/LMCore state. The current LM `FDAIOrientation` has GASTA/CDU mapping and a texture alignment for its previous sphere. This new mesh has its own UV basis: **do not blindly reuse that +90° alignment or apply it twice**. Compare known zero/pitch/yaw/roll states, including near-yaw-cap views, before accepting an adapter.
4. Supply separate calibrated rates/errors, source selection, scales, power and ORDEAL reference behavior. The six gauge rotations are geometric degrees, not spacecraft degrees or degrees/second. The source documents contain differing rate ranges; no calibration table is embedded in geometry.
5. Test in Reality Composer Pro and the visionOS app: Y-up/1-meter scale, glass and texture appearance, hierarchy lookup, selected data source, signs, reference frame and all independent motions. Verify Vision Pro legibility, aliasing, real-world size, frame time and optical appearance. These gates remain **not tested**. The FDAI is a display; no input/hover/collision components are supplied.
