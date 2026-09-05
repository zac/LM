# Artemis II photographic reference pass

This extends `TerrainRealismPlan.md` B2 under the contracts in
`LandAnywhereMoonPlan.md`. Photographs guide appearance and visual acceptance;
they do not replace the pinned elevation sources or establish local hazards.

## Inspected references

NASA's [Artemis II flyby gallery](https://www.nasa.gov/gallery/lunar-flyby/)
contains observations from April 6, 2026. Three released JPEGs were inspected
on September 5, 2026:

| NASA image | Useful comparison | SHA-256 of inspected large JPEG |
| --- | --- | --- |
| [The Edge of Darkness, art002e010208](https://www.nasa.gov/image-detail/amf-art002e010208/) | Broken terminator, illuminated rims against dark crater interiors, relief at regional scale | `6632a8cdc4a7a378117f97448c16d4d137017c9b258f35f813c9114d08d17237` |
| [Shadows Across Vavilov Crater, art002e009282](https://www.nasa.gov/image-detail/amf-art002e009282/) | Terraced rim structure, sharp cast-shadow boundaries, overlapping crater generations | `8c009c63248ba648611968d278937e9559b81ce9a32ca5ad472b3e5090fd8078` |
| [Overexposed Moon for Analysis, art002e009582](https://www.nasa.gov/image-detail/amf-art002e009582/) | Exposure control, not a default brightness target | `9c50d40b1499133d56c36f1384f68c33a5211029e2c902385a1d26d934204995` |

NASA explicitly describes the last image as part of an exposure bracket.
The downloaded large JPEGs expose no EXIF exposure time, aperture or focal
length through ImageMagick. Do not infer physical albedo, a camera response
curve, or a single correct shadow lift from these display images.
Local analysis copies are in `/tmp/LM-Artemis-Realism`; no new asset is bundled.

## What the comparison supports

The photographs show deep shadows beside textured sunlit slopes, irregular
crater silhouettes, terraces and ejecta at multiple scales. These are useful
targets. They do not support darkening every lunar view uniformly: illumination,
view direction and exposure differ across the gallery. Nor do orbital-scale
features determine how much sub-meter relief belongs beneath a landing footpad.

The current opt-in photographic grade already removes the emissive floor and
changes the direct illumination. It also uses a deliberately exaggerated
earthshine fraction of 0.02. It is an artistic presentation setting, not a
validated camera or dark-adapted-eye model. The old B2 description should not
be read as evidence that its numerical settings match Artemis photographs.

Two unchanged-binary photographic Highland controls were captured with the
global protocol (90 seconds after ready), at 249 m / 700 m width and at
2 m / 8 m width, in `/tmp/LM-Artemis-Highland-Photographic-Before`.
The terminal view still has broad, low-contrast forms. These are diagnostic
controls, not matched Artemis recreations: they use the existing mission date,
different terrain and much smaller viewing scales.

## Next visual experiments

1. Match geographic region, solar elevation/azimuth, view direction and image
   scale before adjusting tone. Use the Vavilov and terminator frames for
   regional/globe comparisons; use NAC/Surveyor references for landing scale.
   Retain photo ID, date, source floor, grade, shadow and normal-map settings
   with each capture. Exact camera pose is currently unavailable.
2. Capture calibrated and photographic pairs, then shadows-off and constant
   reflectance/normal-maps-off controls. `CaptureLunarGlobalTerrain.sh` now
   records `LUNAR_CAPTURE_SUN_OFFSET_HOURS` through the existing ephemeris
   launch flag, so low-Sun experiments are repeatable. Do not compare different
   footprints as a radiance test; retain the existing adjacent-edge method.
3. Attribute distant facets using submitted-triangle ownership rays and
   measured source versus render spacing. If a silhouette is under-sampled,
   refine its render grid within measured frame/memory budgets. Interpolation
   density is not new measured detail. If only shading is at fault, change
   normals/material response without silently reshaping the contact surface.
4. Test long-range shadow coverage and Earth visibility separately. The current
   contact-scale shadow range is capped at 45 m; increasing it may trade local
   shadow resolution for distance. A far-side reference must not be given
   arbitrary Earth fill. Both require controlled captures before defaults move.
5. Promote a revised photographic setting only after human visual review,
   highlight/shadow checks and LOD continuity measurements. Keep the calibrated
   Apollo ladder and pinned bytes unchanged. Physical Vision Pro must validate
   stereo shadows, motion, EDR presentation and sustained GPU/thermal cost.

No exposure multiplier or new crater geometry is accepted solely from these
photographs. The highest-value realism work combines correct shadow coverage
and silhouette sampling with a measured presentation pass.
