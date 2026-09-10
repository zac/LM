# AltitudeRate handoff

Delivery branch `cockpit/altitude-rate`, base LMKit `ee3a19f21e31d77645e7b6451db800d2b3d60f5e`. Changes confined to `Assets/Cockpit/Components/AltitudeRate/`. No shared packaging/API changes, simulator use, push or merge.

## Asset and installation

- `AltitudeRate.blend`: editable neutral source; `build.py` reproducibly emits neutral USDZ/USDC/USDA.
- `AltitudeRate.usdz`: `/AltitudeRate` identity, meters, Xright/Yup/Zcrew. It has no animation, lights, cameras, external references or baked emission.
- `interface.json`: complete root/row/shutter names, numeric q transfer tables, fixed origins, valid domains, neutral row poses and active/parked shutter positions.
- `mounting.json`: fit against exact pinned inventory and current neighboring sources. Slot remains `Panel1__RangeThrust`; instantiate at slot-local(-.020,0,.008), identity orientation and unit scale.
- Approved provisional82x145mm face exceeds the original90mm-high blank. Current bounds leave3mm to Guidance,7.5mm to Propulsion and65mm to FDAI reservation. Geometry stays clear in the inspected Panel1 front/commander views. These gaps are not fabrication clearances.
- Keep the neutral RangeThrust backing for deferred T/W/thrust and other unbuilt contents. It remains behind the visible tape and pointers. Housing intersects the backing slab at its hidden rear registration; no cutout/fastener engagement or mechanical seating is qualified.

## Runtime contract

`AltitudeTape` at(-.018,0,.005) and `AltitudeRateTape` at(.016,0,.005) are independently addressable groups. Their146/241 row children include fixed printed numerals and ticks. These are **per-row transforms**, not one full-length translating tape mesh. For a finite in-range sample, position each row locally at `(0,q(row.value)-q(sample),0)` and enable it only when `abs(y)<=.043`. All others must be disabled. Actual maximum row half-height2.05mm fits the declared3.5mm margin within a47mm half-aperture. Do this before exposing the assembled asset.

All USD visibility is inherited. Default inactive rows are parked inside the opaque housing at localz-.010, avoiding the imported-invisible re-enabling trap. Do not merely enable rows without setting their local position. Never shift Fixed, pointers, tape origins or whole asset to display a reading.

`InvalidAltitude` and `InvalidRate` are direct root children. They start parked at(rootx,0,-.005). On invalid/out-of-range data, disable all rows and set the corresponding shutter position to(rootx,0,+.007), as specified in the contract. On valid data return it to parked position (or disable after parking). Shutters are an explicitly approximate availability treatment, not a flight lamp circuit.

Input feet = meters/0.3048. Altitude valid0..60000feet. Rate valid-700..+700ft/s, **positive up, descent negative**. Bind sphere-relative geometric `vehicle.altitudeMeters` and signed `vehicle.verticalSpeedMetersPerSecond` only under an explicit simulation-truth presentation. Do not use the slant-beam value just because its API says radarAltitude. Do not claim radar/PGNS/AGS source fidelity. Never clamp NaN, missing or out-of-domain data into a plausible valid reading. Piecewise scale pitch is documented visual approximation; no guidance algorithms or servo circuitry are implemented here.

`ProtectiveLens` is independently removable if final RealityKit reflections hurt readability. White/black rate-tape distinction follows source photo tone; explicit sign labels are provisional. RANGE headers are subdued historical face legends, not supported rendezvous functionality.

## Validation

- `validate.py`:13,143 structural/vertex/transform assertions pass;633 meshes,11,171 triangles; proper unit transforms, inherited visibility, self-contained USD; USDZ ARKit compliance has no errors, failures or warnings. These counts describe asset checks, not simulator tests.
- `validate_native.swift`: native macOS RealityKit loads exact asset;1,151 assertions across21 state cases pass. Parent identities, row poses/margins, fixed pointer isolation, zero/interior/transition/endpoints, positive/negative rate, out-of-range and NaN are checked. Native app/render simulation is not covered.
- `validate_fit.py`: adjacent Panel1 reservation face envelopes do not overlap; hidden backing intersection is documented. Reviewer independently verified the row manifest and bounds.
- Eleven reviewed images: seven small Workbench isolated states/views, two Panel1 context views, two native SceneKit lens comparisons. Corrected mixed authoring coordinate conventions in the review-only append script; source assets and montage sources unchanged.
- Native SceneKit images show legible labels through the exported lens; this is not RealityKit rendered/headset acceptance.

Reproduce from this component directory using installed Blender5.2.1:

```
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python validate.py
python3 validate_fit.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python review.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python review_fit.py
xcrun swiftc -module-cache-path /private/tmp/lm-altitude-swiftcache -parse-as-library validate_native.swift -o /private/tmp/lm-altitude-native
/private/tmp/lm-altitude-native AltitudeRate.usdz
```

Native GPU initialization required approved escalation on this machine, even for Blender background operation; sandboxed native RealityKit process initially terminated without producing a report. The recorded successful report comes from the subsequent native run, not the failed attempt. Initial Swift build syntax was corrected before the passing run.

## Remaining limits

No original-unit surveyed housing, scale-pitch transcription, reversible physical reel mechanism, live electrical monitor, radar/AGS selection, thrust/TW or rendezvous. No full-cabin ray/continuous clearance, final app illumination or physical Vision Pro read/interaction test. Coordinator owns resource synchronization, package tests, LM adapter and combined simulator acceptance. Sources, source hashes and later-mission/simulator applicability are retained in EVIDENCE.md and evidence/sources.json.
