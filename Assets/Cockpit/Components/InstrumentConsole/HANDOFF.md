# InstrumentConsole handoff

Continuous gray upper instrument console around the accepted Panel 1, Panel 2 and sloping Panel 3 installation. The component fills inter-slot voids, provides narrow seams and side/rear enclosure, and seats both existing FDAI mounting plates without changing any instrument transform or moving geometry. This is a broad visual enclosure, not fabrication geometry.

## Install contract

`InstrumentConsole.usdz` root `/InstrumentConsole` is identity in Cabin coordinates, meters, Y-up, -Z forward. `interface.json` uses `lmkit.console-enclosure.v1`: three disjoint groups cover all meshes, 22 explicit structural suppressions carry exact component-root-relative poses, and 24 protected panel/slot/Cabin datums pin the accepted assembly.

Install only after both FDAIs are loaded and validated. Validate the entire contract before attachment or hiding anything. A failed console load retains all existing structural geometry and placeholder states. This overlay does not claim instrument occupancy and must not hide input geometry, slot roots, planning labels, or an instrument subtree.

On success hide exactly the enumerated paths: CommanderPanels Panel 1 Shell, Trim and RemovableBacking groups; PanelInventory Panel 2/3 Frame groups; and the individual Placeholder children for all Panel 1/2/3 slots. The old Panel 1 backing is already disabled in normal LM startup; do not re-enable it. Preserve both FDAI instances, every slot root and the original CommanderPanels/Cabin interface empties. The `Enclosure` group supplies shadow-casting sides and back covers; `Faces` and `Seams` are sheet surfaces and should not cast shadows independently.

## Fitted surfaces and worker boundaries

- Main Panel 1/2 surfaces are at their existing local Z = -0.004 m. Upper outer Cabin X bounds are -0.400 to +0.400 m; local Y is ±0.250 m. Existing panel mounts remain unchanged.
- FDAI housing cutouts are 0.130 m square around the unchanged 0.127 m rear housings. The existing 0.14605 m mounting plate overlaps this opening. Commander mount Z remains +0.016 m, with a shallow seat ending at +0.0118 m behind its mounting-plate back at +0.012 m. Pilot mount Z remains zero, with the main skin at its plate back Z = -0.004 m. No new geometry covers the bezel, rates, ball, roll ring or reticle.
- A 1.2 mm backed center seam separates the upper faces. Narrow authored bevels have explicit face-varying normals; broad surfaces stay planar in native USD import.
- Panel 3 retains its accepted pose and X = ±0.485 m / local Y = ±0.090 m envelope. The top bridge closes the inherited gap to the upper panels. The lower-console worker owns everything beyond Panel 3's bottom edge and agreed a 1 mm seam below it.
- The window worker owns the transition from upper X = ±0.400 m toward the unchanged inner window edge. A concealed 0–3 mm seam overlap is acceptable. Do not widen these upper faces into the optics or move the glazing to fit them.
- Rear cover extends to local Z = -0.244 m, behind existing FDAI connectors. Existing instruments and this visual case overlap the accepted forward Cabin shell volume; this is hidden visual construction, not mechanical clearance or pressure-vessel engineering. Panel 3 rear depth is -0.055 m. Dynamic reach, head movement and full shell mechanics are unqualified.

## Files and reproduction

- `InstrumentConsole.blend`: editable neutral source, only console geometry.
- `InstrumentConsole.usdz`, `.usdc`, `.usda`: self-contained neutral exports with no live instruments or external dependencies.
- `build.py`: reads the retained inventory and accepted component USD datums; writes only this component.
- `review_assembly.py`: reads accepted peer assets, reproduces current LM component mounts and suppressions, writes low-cost crew/pilot/oblique Workbench images plus a disposable `/private/tmp/instrument-console-review.blend` for checks. It never executes peer scripts or writes peer assets.
- `validate.py`: independent USD contract and assembly checks; run after the review script so its temporary scene is fresh.
- `validate_native.swift`: macOS RealityKit load and hierarchy/input-boundary check.
- `EVIDENCE.md`: source interpretation, photographic limitations and accepted data provenance.
- `artifacts.sha256.json`: exact delivered file hashes; regenerate after any changes.

From repository root with Blender 5.2.1 LTS, build hash `9e2066aef7ef`:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/InstrumentConsole/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/InstrumentConsole/review_assembly.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/InstrumentConsole/validate.py
xcrun swiftc -module-cache-path /private/tmp/console-swift-cache -parse-as-library Assets/Cockpit/Components/InstrumentConsole/validate_native.swift -o /private/tmp/console-native
/private/tmp/console-native "$PWD/Assets/Cockpit/Components/InstrumentConsole"
python3 Assets/Cockpit/Components/InstrumentConsole/hash_artifacts.py
```

## Verification and limits

1,702 Blender/USD checks pass: 39 meshes / 2,922 triangles; no ARKit compliance errors, failed checks or warnings. Checks include root/units, exact 22 suppression and 24 protected-datum poses, accepted source hashes, complete shadow-group coverage, explicit flat normals, Blender/export pose parity, regular-grid solid-face coverage, 13 actual instrument-face rays, and 12 FDAI rear-housing occlusion samples. Rear probes use the new console together with unchanged FDAI mounting plates/bezels; far-side housing is also occluded by the instrument itself.

87 native macOS RealityKit assertions pass, including 39 loaded meshes, identity root, all groups present and no input/collision components. Geometry is structurally static. These finite probes are not continuous motion/sightline proof. No simulator or headset was run by this worker; coordinator owns shared resource packaging and combined native/visionOS acceptance.

Review images use neutral peer assets and Workbench material colors. FDAI glass and matching glass/glazing meshes are hidden **in the review render only** because Workbench renders transparent materials as opaque; their geometry remains unchanged and supplies visibility targets. Ball textures and illuminated readout values are not evaluated here. Screenshots establish enclosure and embedding, not photometry, mission accuracy or live behavior.

Worker branch `cockpit/instrument-console`, base `70c091471bbc1af6f82ba277f6c9cccc7caf01b3`. Only this component directory is owned or changed. No push or main merge is performed by this worker.
