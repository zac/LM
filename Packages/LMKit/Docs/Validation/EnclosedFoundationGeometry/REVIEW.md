# Independent combined geometry review

Seven authored USDZ components imported into Blender 5.2.1 LTS. Eight 1000x800 Workbench views took approximately 2.5 seconds total rendering on the final successful pass. No source asset, authoring binary, or repository file was changed. Exact paths, SHA-256 hashes, mount matrices, camera poses and hidden objects are in manifest.json; the disposable scripts reproduce this review.

## Findings

- CDR and LMP views reveal visible stippling/striping on Panel 1 and Panel 4 non-instrument blank surfaces when CommanderPanels backing is retained. This is consistent with overlapping backing and region blank faces and warrants correction before visual assembly acceptance. It is not a claim of exact triangle collision. Instrument faces remain exposed; only the DSKY/FDAI fallback placeholders were disabled.
- Forward triangular apertures remain open at their centers. Grey fields in Workbench match the exterior background. Three geometry probes from crew/review eye to CDR, LMP and docking glazing centers found only the deliberately hidden glazing surfaces, no opaque geometry before escape (5 m ray extent). This does not establish full-aperture clearance, optics, distortion, edge sightlines or eye-box acceptance.
- Closed rear and overhead views show continuous gross enclosure. Side/front cutaways show no obvious floor-spanning obstruction in the central standing area. Aft engine cover and side trays occupy intended broad regions. No human body, hand sweep or reach qualification is inferred.
- Timer slot remains intentionally empty; ACA remains in its provided pose. The imported visuals alone cannot establish support/flange fit or swept hand clearance.
- Smooth gray shell, sparse aft equipment, flat blank banks and simplified overhead remain clearly a foundation. They do not yet match the dense stepped equipment, shaped liners and routed cables described in the supplied LM-2 panorama observations. This is expected unfinished scope rather than a newly measured historical mismatch.

## View semantics

front-closed and overhead-closed look at the exterior of the closed enclosure. cdr-closed, lmp-closed and rear-interior-closed are inside the uncut enclosure. All omit the six transparent window glazing meshes and FDAI glass because Workbench is opaque. Overhead, side and front-interior cutaways remove whole objects by explicit centroid thresholds, listed per view in manifest.json. These cuts are review aids and create openings that are not defects in the authored shell. Planning labels are invisible in USD and explicitly suppressed if imported; no label geometry appears in these views.

## Limits

Geometry-only review of authored USDZ inputs. No runtime, simulator, headset, AGC/display state, gesture, dynamic animation, material fidelity or native RealityKit acceptance. DSKY/FDAI mounted from PanelInventory poses documented against LM11f7335; ACA pose explicit. Neutral state only. No full intersection survey, physical fabrication fit or source dimensions qualification. Packaged-resource byte equality is coordinator validation.

## Exact inputs

- Cabin: `/Users/zac/Projects/personal/lm/LMKit/Assets/Cockpit/Components/Cabin/Cabin.usdz`
  SHA-256 `9b30f113235bea7832dd0d9f245d3f6ad98bd8a64af2d217943a5489e498c21b`

- WindowsLPD: `/Users/zac/Projects/personal/lm/LMKit/Assets/Cockpit/Components/WindowsLPD/WindowsLPD.usdz`
  SHA-256 `91c03cc4b6826473cfdccdce195fece5f591b778b8afdb3a71505df8f528cc32`

- PanelInventory: `/Users/zac/Projects/personal/lm/LMKit/Assets/Cockpit/Components/PanelInventory/PanelInventory.usdz`
  SHA-256 `4b95b051b27831c97a47e9ccfb36b2f62e23469d3be50a09225e57685dc56b24`

- CommanderPanels: `/Users/zac/Projects/personal/lm/LMKit/Assets/Cockpit/Components/CommanderPanels/CommanderPanels.usdz`
  SHA-256 `52e4c13cf302e080edbd163fb3f6d26ce53785c28bc49dcefd3a75c876f9d604`

- DSKY: `/Users/zac/Projects/personal/lm/LMKit/Assets/Cockpit/Components/DSKY/DSKY.usdz`
  SHA-256 `e20a69864d4c7e0ff068172e0e672d9fbcc510c1dc4e97e4db0246fde08fbdfd`

- FDAI: `/Users/zac/Projects/personal/lm/LMKit/Assets/Cockpit/Components/FDAI/FDAI.usdz`
  SHA-256 `4082ef22b4e8615e78a1e62182ed8d150585dcce1755492e6abb0784076c785d`

- ACA: `/Users/zac/Projects/personal/lm/LMKit/Assets/Cockpit/Components/HandControllers/ACA.usdz`
  SHA-256 `df2b00baa607543deedc89ba3a2e87fb5862e5243e02dd104981bd34aef254c5`

## Coordinator-requested backing correction comparison

`corrected-cdr-closed.png` and `corrected-front-interior-cutaway.png` retain the original camera, seven inputs, instrument mounts and glazing/label/slot handling. Only these additional CommanderPanels meshes are hidden:

- Panel_1_Backing_Bottom
- Panel_1_Backing_Left
- Panel_1_Backing_Right
- Panel_1_Backing_Top
- Panel_4_Backing_Bottom
- Panel_4_Backing_Left
- Panel_4_Backing_Right
- Panel_4_Backing_Top

The original comparison images remain intact. The visible stippling/striping on both panels disappears in the corrected comparison, with perimeter and instrument aperture surrounds retained and FDAI/DSKY faces exposed. No additional gross enclosure hole or standing-area obstruction becomes visible in these two views. Spaces between individual blanks remain visibly provisional, exposing the structure behind the panel; they should eventually receive detailed equipment/support finishes, but this small review does not identify a new blocking overlap after the requested correction. This is a geometry-only visual observation, not proof of all-angle fit or native rendering parity.
