# Ceiling lighting investigation

The user correctly rejected the bright white ceiling in the initial systems screenshots. That appearance was not accepted as final visual quality.

## Cause and evidence

The broad overhead surfaces are the existing Cabin `Forward_Roof_Bridge_00/01` and adjoining crown, bound to `WarmGrayLiner`, authored RGB (0.58, 0.59, 0.55), roughness 0.70, opaque and nonemissive. Their inward/downward normals are correct. Native inspection finds the same gray tint, zero emission, and the runtime painted-structure roughness 0.90/specular 0.08. Packaged model bytes match authoring source. See `REPORT.md` and `result.json` for exact paths and values.

The imported assembly applied `noShadows` to its entire hierarchy, including the pressure shell, while hiding the old procedural shell. The procedural path explicitly restores shell casting; the imported path omitted that step. In the pitched vehicle frame the external sun can face the inner roof, and without shell occlusion it illuminates the entire surface through the structure.

Native diagnostics at unchanged 25,000-lux sun intensity established:

- Restoring only imported shell casting removes the broad washout, but the original automatic shadow map produces coarse bands.
- Disabling the actual post-terrain-swap sun removes both washout and bands. No ambient-light or paint change is justified by this comparison.
- Tightening automatic shadow distance improves spatial sampling; lowering depth bias creates acne. Increasing bias at the original distance does not remove coarse boundaries. Front-face culling does not resolve the artifact and was rejected.
- Fixed light-space projection sharpens the boundaries. A four-meter diagnostic footprint clips the right side; an eight-meter footprint produces a clean overhead comparison. These fixed diagnostic sizes are evidence, not the final fitted policy.

The first comparison used close but not identical vehicle states. Later diagnostics use an identical checkpoint, altitude and light quaternion. Reports record actual light enabled state, intensity, transform and material values after terrain replacement; a disabled initial light alone would not establish the sun-off case.

## Implementation and acceptance status

Accepted runtime source `bdbf70f8b47f744c78dac7352477a6cd699754c5` fits actual cabin/lander caster bounds, with bounded downstream receiver depth and near-ground projection. All 98 native visionOS tests across 18 suites pass. The [corrected overhead](../Captures/overhead-paused.png) uses a 7.712 m footprint; [final approach](../Captures/exterior-final-approach.png) preserves continuous lander/gear shadows at 6.887 m altitude with a 54.018 m far plane. Both crew stations, planning and fallback views were reviewed. Exact sources, launch arguments and screenshot hashes are in the [capture manifest](../Captures/manifest.json). The simulator is shut down and released. The model package, sun intensity and sun direction remain unchanged.

Coverage is local to the cabin/lander footprint; distant terrain and rock shadows outside that footprint are not represented. Physical Vision Pro appearance, stereo and input acceptance remain outstanding.

The installed visionOS SDK exposes automatic and fixed shadow projections, depth bias and culling, but no public cascade/resolution control. [Apple shadow-projection documentation](https://developer.apple.com/documentation/realitykit/directionallightcomponent/shadow/shadowprojectiontype) describes the available projection API. Local SDK declarations, rather than newer beta documentation, govern this build.
