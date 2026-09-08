# CautionWarning handoff

Built on `035c5b3ad1a522cf6d25fb222d46c2fb4a4a8de8` in isolated branch `cockpit/caution-warning`; owns only this directory. No package Sources/Tests/Tools, peer assets, simulation, application, shared slots or installed controls changed. No simulator, heavy render or bake.

## Deliverables and mounting

`CautionWarning.blend`, reproducible `build.py`, neutral `CautionWarning.usdz` and intermediates. Main root `/CautionWarning` is identity Cabin-relative, +X right/+Y up/-Z forward in meters. Blender authoring is deliberately Y-up and export does not reinterpret axes. `interface.json` retains complete original panel/slot poses and exact source inventory hash.

Two occupants match `Panel1__Warning` and `Panel2__Caution`. Coordinator should load once at identity, validate both mapped slot matrices, then hide only those two exact `default_placeholder_node` paths. Preserve frames, parent mounts and inspection labels; failure/absence retains blanks. Never apply panel transforms a second time. Proposed accessors: `cautionWarningURL` and `cautionWarningInterfaceURL`.

40 physical cells preserve the supplied drawing's two banks × five rows × two columns per panel. 31 cells have source-transcribed legends; nine blank cells stay blank. Every lamp group, Lens and optional Legend is independently addressable; interface records exact paths. Neutral lenses/legends are opaque and dim, with no emission, timing, state machine, collision or input targets. A material change in future is coordinator-owned and must not be mistaken for modeled electrical behavior.

`MasterAlarmReference.usdz` is a separate, **unmounted specimen** with independently addressable `MasterAlarm_Button`, Lens and Legend. It is never inside the production CautionWarning root. The inventory has no dedicated master-alarm slot, and the narrowed commander surround cannot justify silently inventing a fit. Controls lane confirmed no ownership conflict; EngineControls owns engine buttons and LUNAR CONTACT. Do not place the specimen at Cabin origin. A future accepted mounting contract is required. No travel, reset or electrical latch is modeled.

## Source and dimensional limits

The user-supplied one-page controls PDF provides visible labels and 2×5 bank topology; retained crops preserve source pixels. Revision/mission provenance of that raster is unresolved, so no claim of mission-exact Apollo11 warning schedule. `ASC He REG` normalizes the helium chemical typography; that source raster can resemble HI. Blank cells and abbreviations are retained, and no sensors/thresholds are invented. Names are not live bindings.

Module pair is approximately117×41mm, chosen to preserve the drawing's proportions while fitting the current45mm-tall warning slot. Both sides reuse this provisional module envelope. Existing slot footprints are much wider, so neutral adapter plates fill their replaceable blanks; these plates and overall physical scale are authoring choices, not historical hardware drawings. Body thickness, rounded bevels, fasteners, paint/lens colors and mounting are provisional. No illuminated color/photometry acceptance.

Read `SIGNALS.md` before integration. Existing DSKY snapshot and raw channel163 bit0 computer warning are observable, but no complete source-qualified binding to the Panel1 LGC light or master alarm is established. AOH printed2.1-77 additionally specifies LGC power-failure indication. DSKY V35 lamp test and training hard-landing cues cannot substitute for the physical CWEA/test-tone circuit. No supported data is fabricated for the other warnings.

## Validation

1,146 authored/export checks plus final peer-surface gate pass. Metric units, separate roots, source counts, finite slot geometry, unit/physical slot transforms, all40 cell/lens and31 legend paths, opaque unpowered materials/no emission or physics, USDZ compliance, reimport physical axes and static peer checks.

Zero triangle surface crossings against pinned Cabin, WindowsLPD, CommanderPanels and remaining PanelInventory (only these two blanks and planning labels excluded). Exact hashes and conservative candidate counts are retained. This is static surface testing, not mesh-containment, manufacturing fit, eye/reach, continuous motion or optical qualification. Newly developed overlays still require coordinator combined assembly checks.

Native macOS RealityKit validation loads both independent USDZs, verifies both full slot matrices and all40 lens entities, separate master specimen, independent cells, and absent collision/input components. No Vision Pro or simulator acceptance. Final reports and hashes identify the tested asset bytes.

Main budget:85meshes,13,189triangles,6materials,zero textures. Main bounds: X[-.283,.378], Y[1.765954,1.835799], Z[-.925509,-.906815]m. A separate source specimen is intentionally excluded from production bounds and budget; its budget is in interface.json.

Three small Workbench images under review/ show the unpowered warning, caution and master specimen. These are geometry/readability inspections, not actual flight lighting or headset captures. The font is bundled Bfont converted to mesh; exact historical engraving remains unverified. First validation caught a thin-gasket bevel collapse; clamping bevel width to one-quarter of the thinnest dimension corrected it before final passing artifacts.

## Reproduce and integrate

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/CautionWarning/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/CautionWarning/validate.py
xcrun swiftc -module-cache-path /tmp/caution-native-swift-cache -parse-as-library Assets/Cockpit/Components/CautionWarning/validate_native.swift -o /tmp/caution-native
/tmp/caution-native "$PWD/Assets/Cockpit/Components/CautionWarning"
```

Native tools required normal macOS graphics process access outside the sandbox. No shared resource refresh was performed. Coordinator owns package resources/API and Tools/sync_dsky.py packaging validation, then LM optional static installation and any separately reviewed live adapter.
