# CrossPointer delivery

Owned directory only: `Assets/Cockpit/Components/CrossPointer`. Branch `cockpit/cross-pointer`, base `ee3a19f21e31d77645e7b6451db800d2b3d60f5e`; worktree `/private/tmp/lmkit-cross-pointer`. No peer assets, Sources, Tests, Tools or master assembly changed. Coordinator owns package refresh and runtime integration. No merge/push performed.

## Delivered

- Editable `CrossPointer.blend`, neutral `CrossPointer.usdz` and corresponding USDA/USDC, reproducible `build.py`.
- `interface.json`: authoritative paths, units, neutral transforms, slot registration, travel limits and mode/source qualifications.
- Two separate curved needle meshes under independently movable `LateralNeedle` / `ForwardNeedle`; separate fixed bezel, numerical scale, multiplier legends and inactive power flag.
- Primary handbook/memo evidence, original figure references, source hashes and explicit inference/physical limits in `evidence/RESEARCH.md`.
- `validate.py`, `validate_native.swift`, reports and three small Workbench previews.

Neutral root `/CrossPointer` is identity, meters/Y-up (+X face-right,+Y face-up,+Z crew). Install as an identity child of the existing Panel1__CrossPointer slot. Do not apply the panel/slot pose twice.61mm square façade fits inside the 140 × 65 mm provisional reservation without distorted scaling. Surrounding unused slot area requires neutral backing. The 20 mm rear housing is provisional and currently overlaps the region where CommanderPanels has a solid backing: panel cutout/seating is not qualified. No peer backing has been modified.

## Runtime contract agreed with integration worker

Supported mode is **simulation-fed, later-inspired horizontal landing velocity, LO MULT**, range ±20 ft/s (=±6.096 m/s). Neither measured landing-radar validity nor real AGC error-counter output is implied. Memo 165 supplies the later surface/yaw-frame rationale; Memo 171 explicitly describes a sign change to fly-to, so this is not advertised as Apollo 11 polarity. The numerical screen directions are an operational inference from fly-to pitch/roll, explicitly recorded.

| Moving node | Neutral local translation m | Change at +20ft/s |
|---|---|---|
| `/CrossPointer/Needles/LateralNeedle` |(.003,.003,.0017)|X decreases by.016 for rightward velocity|
| `/CrossPointer/Needles/ForwardNeedle` |(.003,.003,.00215)|Y increases by.016 for forward velocity|

Clamp finite values at endpoints. Hide `/CrossPointer/Needles` on invalid/unsupported input, leaving the fixed scale; never center invalid values. Both multipliers remain inactive in LO velocity. Do not use the inactive power flag as a fabricated sensor-valid indicator. No input/collision components or switch binding are implied. Ascent, abort, AGS, rendezvous, HI mode and internal electrical failure behavior remain unsupported.

## Validation

562 saved Blender/USD physical-transform, path, scale, full-travel aperture, independent fixed-frame and compliance checks passed. Neutral mesh count 127, triangles 4624. ARKit compliance errors/failures/warnings empty. macOS RealityKit loaded the actual neutral USDZ and verified identity root, exact neutral/full-scale positions, independence of the two needles and group-hide behavior preserving the fixed face. Physics/frame/polarity fixtures belong to LM; they were not duplicated here. No visionOS simulator or physical headset testing claimed.

Source/neutral production contain no cameras or lighting rig. Preview cameras and demonstration needle positions are created only after saving/exporting and are not saved back into production. `review/neutral.png` is the neutral 0/0 display; `example-right-forward.png` illustrates +10 ft/s right/+10 ft/s forward; `negative-full-scale.png` illustrates -20/-20. These are isolated Workbench views, not cockpit/headset legibility acceptance or calibrated materials.

## Reproduce

From LMKit root with Blender 5.2.1 LTS (9e2066aef7ef):

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/CrossPointer/build.py -- --preview
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/CrossPointer/validate.py
xcrun swiftc -module-cache-path /tmp/crosspointer-swift-cache -parse-as-library Assets/Cockpit/Components/CrossPointer/validate_native.swift -o /tmp/crosspointer-native
/tmp/crosspointer-native "$PWD/Assets/Cockpit/Components/CrossPointer"
python3 Assets/Cockpit/Components/CrossPointer/hash_artifacts.py
```

`interface.json` is the versioned static contract, intentionally not silently rewritten by the builder. Validators check its physical values against generated files. Blender and RealityKit required approved native execution in the sandbox. The initial sandbox Blender launch failed before script execution; approved native runs completed. All previews were small Workbench jobs; no expensive bake/render or simulator slot was consumed.

Coordinator should preserve commit provenance, refresh resources with its packaging helpers including the required sync_dsky workflow, run package/adapter tests, then review actual assembled seating and scale readability. Missing or failed resources retain the reservation blank.
