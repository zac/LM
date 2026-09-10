# BreakerBanks delivery

Optional static Cabin-relative overlay, built from LMKit `ee3a19f21e31d77645e7b6451db800d2b3d60f5e` on `cockpit/breaker-banks`. Only this component directory is owned. No simulation, application, package, peer assets, slot frames, shell, optical datum, reach targets, lights or collisions changed. Original CircuitBreaker mesh geometry is reused unchanged from ControlLibrary, with source bytes pinned under evidence. Authoring copies share mesh data; fixed housing/nut/sleeve and label geometry is batched by row/material for fewer draw calls.

## Deliverables

- `BreakerBanks.blend`: editable neutral source; Blender scene is deliberately Y-up like PanelInventory, in meters. Each bank, slot and breaker root is independent; source plunger/knob geometry stays addressable. No actuation or circuit-state contract is established.
- `BreakerBanks.usdz` and USD intermediates: identity root `/BreakerBanks`, Cabin +X right/+Y up/-Z forward. Load once at identity beside existing components. Do not apply panel transforms again.
- `build.py`: complete regeneration from pinned inventory, copied CircuitBreaker USDZ and labels.json; no network, linked libraries or external fonts/textures. Text meshes use Blender's bundled Bfont. `review.py` refreshes small Workbench previews without modifying production geometry.
- `interface.json`: exact nine region paths, unchanged original panel and slot poses, specific placeholder suppression paths, terrace offsets and budget. Proposed coordinator accessors are `breakerBanksURL` and `breakerBanksInterfaceURL`.
- `labels.json`, source crops and `evidence/provenance.json`: reviewable individual legends, source qualifications, hashes and source locations.
- `validate.py`, `validate_native.swift`, validation reports and `review/`: actual test evidence and four review views.

## Appearance and source limits

160 individually named breaker roots occupy five commander rows (19/19/19/21/11) and four pilot rows (16/18/18/19). Visible legends were transcribed from the supplied raster controls PDF, with station nomenclature and repeated labels retained. No amperage values were invented. Top-level functional group strings abbreviate the source grouping. This is a generic/later drawing transcription, not a qualified LM-5 electrical schedule. Uniform spacing replaces nonuniform source gaps; the commander's bottom row deliberately preserves a mostly blank right half. Read `labels.json` and crops before later mission corrections.

AOH printed 1-8 (retained LM10+ excerpt page1/original PDF21) explicitly identifies five and four angled surfaces and a 15-degree cant to sightline for observing open breaker bands. The Smithsonian LM-2 panorama observations support separate terraces, not a flat painted board. Model uses 35–67mm crewward offsets and -15-degree **relative** row cant from the unchanged provisional inventory plane. This is a source-inspired approximation, not a solved 15-degree eye-ray mount or measured LM-5 terrace profile. All dimensions, physical colors, knob spacing and exact label placement remain provisional. Neutral knob position is merely the original visual state; it does not establish powered/closed circuit semantics.

Panorama applicability and unknown-source-image limits are retained. No Smithsonian panorama imagery was copied. Source PDF crops are evidence, not baked model textures. Fine attachment hardware, exact engraved typeface, side-wall mating/support construction and electrical state are future work.

## Installation

After successful whole-overlay load and interface validation, coordinator may hide only the nine `default_placeholder_node` paths listed in interface.json. Preserve each parent mount, surrounding frame, planning labels and all peer equipment. Do not hide entire Panel11/16. On failed/absent overlay, leave the individual blanks enabled. This worker never modifies or disables peer placeholders. Disable/remove this root and restore its nine blanks to roll back.

The overlay keeps original region UV footprints; visible forward depth is expanded explicitly for control housings and stepped structure. Mount translations/quaternions are unchanged. Exact full slot frames are checked natively. No collision shapes or input targets should be automatically generated for this static delivery. Circuit behavior belongs to AGC/LMCore and a future coordinator-authored electrical adapter, never implied by mesh names.

## Validation

4,521 authored/export checks pass, followed by a final peer-crossing gate. Blender reopen, no external dependencies, declared mesh/triangle budget, finite transforms, unit scale, slot width/height/depth, independent rows, exact full nine slot matrices, all three USD formats, proper materials, no physics properties, ARKit compliance and USDZ Blender reimport/axis conversion. Zero ARKit errors/failures/warnings. Native macOS RealityKit loads 383 model entities and verifies all nine full matrices, independent groups and absent collision/input components. No simulator or headset run.

Static peer comparisons at pinned bytes: zero actual triangle surface crossings against Cabin, WindowsLPD, PanelInventory (only the nine replaceable blanks and inspection labels excluded), and neutral commander ACA at (-.49,.9075,-.37). Conservative broad-phase candidates against shell/window bounding boxes are retained in validation.json and resolve to zero triangle crossings. This does not prove mesh containment, continuous controller sweep, service clearance, optical clearance from displaced eyes or hand reach. The other workers' new overlays still require coordinator combined validation.

Budget: 383 meshes, 144,485 triangles, five materials, zero textures. Individual small plungers account for much of the entity count; a future runtime static-batching/LOD pass is possible after visual acceptance. Mesh vertices for reused controls are unchanged. Geometry is small but performance on Vision Pro is not measured.

Cabin bounds: X[-.995065,.984463], Y[1.348709,1.663261], Z[-.467500,.267500]m. Independent cables/trim worker was notified; their lower-wall assignment does not overlap this height range. Quick Workbench reviews only; zero heavy renders or bakes.

## Commands

From repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/BreakerBanks/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/BreakerBanks/validate.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/BreakerBanks/review.py
xcrun swiftc -module-cache-path /tmp/breaker-native-swift-cache -parse-as-library Assets/Cockpit/Components/BreakerBanks/validate_native.swift -o /tmp/breaker-native
/tmp/breaker-native "$PWD/Assets/Cockpit/Components/BreakerBanks"
```

Native graphics startup required execution outside the desktop sandbox on this host. First batch build encountered a Python stale-object reference that was corrected before successful final generation. Validation's initial exact-zero plane check was corrected to a 1 µm numerical tolerance. No final geometry or clearance check is waived. Coordinator owns resource synchronization including Tools/sync_dsky.py and Swift package tests, then serial LM integration.
