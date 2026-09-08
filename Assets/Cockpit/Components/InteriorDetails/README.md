# Optional interior details

`InteriorDetails.usdz` is a visual-only additive overlay. Install its identity root `/InteriorDetails` as a sibling under the Cabin coordinate frame. The coordinates are meters, +X right, +Y up, -Z forward. Do not apply a panel mount transform. Omission or load failure must leave the foundation and all live instruments unchanged.

`interface.json` records exact group bounds, triangle budget and asset hash. `PROVENANCE.md` distinguishes source observations from provisional choices. `HANDOFF.md` summarizes checked behavior and remaining limits.

Reproduce on a machine with Blender's Python USD modules:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python Assets/Cockpit/Components/InteriorDetails/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python Assets/Cockpit/Components/InteriorDetails/validate.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python Assets/Cockpit/Components/InteriorDetails/review.py
xcrun swiftc -module-cache-path /tmp/interior-details-swift-cache -parse-as-library Assets/Cockpit/Components/InteriorDetails/validate_native.swift -o /tmp/interior-details-native
/tmp/interior-details-native "$PWD/Assets/Cockpit/Components/InteriorDetails"
```

`build.py` writes only this component directory. `validate.py` and `review.py` read hydrated peer assets but never save them. Review images are small Workbench geometry previews: windows omit glazing, planning labels stay hidden, CommanderPanels backing strips are omitted to avoid the coordinator-known duplicate backing, and instruments remain as inventory fallback blanks. These are not the current application appearance.
