# LowerConsole handoff

This optional Cabin-coordinate overlay encloses the fixed DSKY and commander controller area. The DSKY now has a solid sloping surround, shallow metal reveal, enclosed 172 mm-deep case and rear closure. The commander controller console has a substantial enclosed body, sloping face and an intentional opening for the accepted ACA housing. A small equipment cheek and lower apron add source-inspired mass without changing live instruments.

`LowerConsole.blend` is editable. `build.py` reproduces the neutral `LowerConsole.usda`, `.usdc` and `.usdz` from geometry and the preserved inventory. No other component assets are embedded in the production model. `review.py` imports existing peer assets solely for the three assembly inspection images.

## Integration contract

- `interface.json` uses `lmkit.console-enclosure.v1`: identity root `/LowerConsole`, meters, +Y overhead, Cabin coordinates. Do not apply panel transforms again.
- Validate every group and every full component-relative suppression/protected pose before attachment. Install only when the accepted DSKY and ACA are available; failure retains the existing surfaces.
- Hide only `/CommanderPanels/Panel_4/Panel_4_Shell`, `Panel_4_RemovableBacking`, `Panel_4_Trim`, and `Panel_4_Fasteners`. Their exact full paths and poses are in the interface. Keep `DSKY_Interface`, all Cabin mounts, all Inventory frames and all slot nodes.
- No Inventory placeholder suppression or occupancy claim is requested. The new face sits behind existing blanks. In particular, **do not fill `Panel5__Timer`**: its physical blank is intentionally absent for ACA clearance. The new face and upper return are also cut away there.
- Four disjoint groups cover every mesh and declare opaque shadow casting. No collision, input, state, lamps, animation or behavior is authored.
- True transformed-vertex bounds and conservative transformed local-box bounds are separately recorded. RealityKit uses the conservative bounds; the small difference is expected at beveled rotated corners.

Coordinator owns resource API, packaging with `Tools/sync_dsky.py`, aggregate tests and app bindings. This commit changes only `Assets/Cockpit/Components/LowerConsole`.

## Evidence and limits

`evidence/SI-99-15229h.jpg` preserves the supplied cockpit photograph. It supports substantial sheet surfaces, boxlike equipment enclosures and a central instrument recess. It shows a vacant DSKY position; it does not establish a flight DSKY installation, Apollo 11 configuration, dimensions, joins, fasteners or survey coordinates. See `evidence/provenance.json` for source hashes and exact runtime revision.

Fixed DSKY/Panel4/Panel5 poses come from accepted LMKit inventory and LM runtime sources. The face outline is inherited from CommanderPanels, not newly surveyed. The aperture is 212.3496 × 209.2 mm centered at Panel4 local `(0, .015)`, with a 3 mm allowance around the documented front envelope. Face front is panel Z −4 mm; reveal front is +2 mm; accepted DSKY bezel starts +3 mm. Rear closure inside Z is −168 mm, leaving 16.786 mm beyond the existing provisional rear box at −151.214 mm. These are computational visual clearances, **not a fabrication cutout or physical mounting qualification**.

The top of the new Panel4 case ends at local Y .203 m. InstrumentConsole owns Panel3 down to its local Y −.09 m, equivalent to Panel4 Y .204156 m; the nominal gap is about 1.16 mm. Separate parallel overlays require the coordinator's combined acceptance pass.

The commander box preserves ACA root `(-.49, .9075, -.37)` and its existing ±11° presentation travel. Its Timer well is open by design. No TTCA is placed: the checked runtime has no accepted TTCA placement in this region. The Cabin hatch and its mounts are unchanged; the center below Y .835 m and |X| < .20 m receives no new geometry. A moving hatch/egress path is **not** qualified; existing Cabin hatch is a closed static surface.

## Validation

`validation.json` records independent USD geometry tests: closed individual solids, flat normals per exported triangle, disjoint shadow coverage, exact referenced transforms, ARKit compliance, real triangle intersections against eleven current peers, 25 DSKY aperture rays, a rear enclosure ray, all three DES RATE states and 125 ACA poses spanning ±11°. Tests use the packaged PanelInventory; its sole packaging change is planning-label visibility, which is suppressed during the runtime comparison.

`validation-native.json` records macOS RealityKit loading, 30 meshes, four complete disjoint groups, nine full pose comparisons and bounds. `review/*.png` shows the actual peer DSKY/ACA and slots at fixed poses. Workbench material lighting is inspection lighting; it is not a visionOS lighting, transparency or display-state acceptance test. Some source peer faces remain visually sparse; new peer overlays were not silently substituted into these evidence images.

No simulator, Vision Pro, fabricated hardware, electrical behavior, package publication or app installation is claimed. The final combined native app images remain the coordinator's acceptance gate.

## Reproduce

From the LMKit root with Blender 5.2.1:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/LowerConsole/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/LowerConsole/validate.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/LowerConsole/review.py
xcrun swiftc -module-cache-path /tmp/lowerconsole-swift-cache -parse-as-library Assets/Cockpit/Components/LowerConsole/validate_native.swift -o /tmp/lowerconsole-native
/tmp/lowerconsole-native Assets/Cockpit/Components/LowerConsole
python3 Assets/Cockpit/Components/LowerConsole/hash_artifacts.py
```
