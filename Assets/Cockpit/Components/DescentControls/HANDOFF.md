# Descent controls

Two neutral, loadable control assets with editable `DescentControls.blend`, reproducible `build.py`, source evidence and machine-readable `interface.json`. Worker branch `cockpit/descent-controls`, base `ee3a19f21e31d77645e7b6451db800d2b3d60f5e`. Only this directory is changed. No simulation, shared inventory, runtime API, resource synchronization or simulator changes.

## Installation contract

Meters; +X right, +Y up, panel-local +Z toward crew. Export roots are identity and unit scale. Place each root **once, identity under its named inventory slot**. The complete panel and slot transforms are already in `PanelInventory/inventory.json`; do not also apply a Cabin transform to a slot child.

| Asset / root | Destination | Moving child directly under root | Input contract |
|---|---|---|---|
| `AttitudeMode.usdz` / `AttitudeMode_Mount` | `Panel3__Stability` | `AttitudeMode__Actuator`, position `(-.072,-.037,.009)` m | Replace local orientation with Rx(-17°) AUTO / Rx(0°) ATT HOLD. OFF Rx(+17°) is historical geometry only, unsupported and must be rejected. Exported neutral is AUTO. |
| `DescentRate.usdz` / `DescentRate_Mount` | `Panel5__Engine` | `DescentRate__Actuator`, position `(-.034,.018,.027)` m | Orientation = Ry(-90°) × Rx(delta). Plus delta=-17°, center=0°, minus=+17°. Exported neutral is center. Never discard the side-mount Ry baseline. |

The interface distinguishes rotation-reference quaternion from **actual exported neutral quaternion**. Both controls preserve pivot position and scale while changing orientation. Names do not by themselves establish runtime bindings. Coordinator maps supported attitude modes to existing `automatic` / `attitudeHold` and ROD to existing input paths; no OFF/AGS/engine behavior is created here.

DES RATE upper movement is +1 FPS, documented as increasing thrust/reducing descent rate; lower is -1 FPS. Use the existing ROD pulse semantics, not an invented continuous analog throttle or autorepeat. Host must spring-return to center and clear its input generation on release, cancellation, pause, scene exit and teardown. Resetting visual pose is not sufficient to stop any host-held input.

`AttitudeMode__NeutralBacking` and `DescentRate__NeutralBacking` are separately addressable. If the host preserves its original slot placeholder, disable only this redundant backing. Never disable whole panel, frame, unrelated slot, or the side-switch support. These assets populate only a small part of their regions. Do not generate collision/input recursively on the entire partial root: target the actuator sweep and keep backing/support noninteractive. The existing timer reservation blocked by ACA remains untouched.

## Source corrections

The provisional request named Panel1 guidance and Panel5 translation. The actual PGNS MODE CONTROL belongs to **Panel3**, distinct from Panel1 GUID CONT PGNS/AGS. The inspected NASA diagram shows DES RATE as an **unplacarded side-mounted switch at the engine-button guard**, with a detached explanatory callout. Coordinator approved Panel3 Stability / Panel5 Engine partial installation. The Panel1 Guidance and Panel5 Translation blanks remain unchanged.

DES RATE therefore has no counterfeit DES RATE/+1FPS/CENTER/-1FPS ink. Use an optional external training overlay for explanation. Its `DescentRate__ProvisionalUpright` and `DescentRate__ProvisionalFoot` are minimal supporting geometry, explicitly **not a reconstructed engine-button enclosure or guard**; they contain no engine buttons or engine input. Future engine-package authoring can remove these support nodes while keeping the separate control root and contract.

The side attachment surface is Engine-slot local `(-.025,.018,.027)`, normal -X. Thus its Panel5-local attachment is `(-.105,.088,.027)`; actuator pivot is Panel5-local `(-.114,.088,.027)`. Slot transform is the authoritative place to combine with the pinned Panel5 pose. A source-proven side orientation is retained while all metric location and bracket dimensions remain provisional.

Source files and SHA-256 are in `evidence/source-manifest.json`. `evidence/mode-and-des-rate-aoh.pdf` contains full pages 3-65 and 3-81 from the later LM handbook, original PDF 661/675. The source diagrams support panel assignment, mode order, side mounting and lack of DES RATE placards; they do not establish flight-unit dimensions. Source crops are nearest-source raster enlargements for reading, not newly measured drawings.

Control meshes are reused from the pinned ControlLibrary Blender family geometry (`MaintainedToggle`, `MomentaryToggle`); the builder checks its SHA-256 before reading. Its shape and nominal ±17° toggle travel remain generic/provisional hardware, not a verified LM-5 part. Labels are converted to mesh, with no font or texture dependencies at runtime. No lighting is baked into USDZ.

## Verification

`validation.json`: 36 checks pass for identity roots, meter/Y-up USD, exact pivot positions, independent backing, sampled input direction, unchanged fixed siblings, slot width/height and ARKit package compliance. It compares the actual DES RATE mesh at neutral against the actual existing ACA over 27 sampled roll/yaw/pitch states (-11°,0°,11°): zero triangle surface crossings. It does not certify containment, continuous swept clearance, hand reach or future engine-package fit.

`native-validation.json`: macOS RealityKit loads both real USDZs; direct moving nodes, pivot positions, independent backing, both motion directions and neutral restoration pass. Host gesture routing and simulation semantics are coordinator integration work. Physical Vision Pro is untested.

`review/AttitudeMode-neutral.png` and `review/DescentRate-neutral.png` are fast Workbench previews. They show component geometry, not assembled commander-eye fit or historical illumination. No heavy renderer or simulator was used.

Reproduce from repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/DescentControls/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/DescentControls/validate.py
xcrun swiftc -module-cache-path /tmp/descent-controls-swift-cache -parse-as-library Assets/Cockpit/Components/DescentControls/validate_native.swift -o /tmp/descent-controls-native
/tmp/descent-controls-native "$PWD/Assets/Cockpit/Components/DescentControls"
```
