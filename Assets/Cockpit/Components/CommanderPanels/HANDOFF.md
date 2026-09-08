# Commander surrounds delivery

Branch `cockpit/commander-panel-surrounds`, isolated worktree `/Users/zac/.codex/worktrees/8891/LMKit`. Clean starting revision `3ad1a999ff17aea859eaea5750f1c65e66fad673`; only `Assets/Cockpit/Components/CommanderPanels/` is changed. No merge, push, simulator use, package refresh, runtime binding or edits to other component binaries. Coordinator receives exact final commit separately.

Editable `CommanderPanels.blend`, neutral `CommanderPanels.usdz` and equivalent USDA/USDC contain 40 meshes / 864 triangles, no instruments, cameras, lights, textures, animation or state. Source and USD are metric with identity root; see `DATUM.md` for the physical axis conversion. `mounting.json` records exact parent-local versus Cabin-relative interfaces. Backing, shell, collar and captive head proxies are independently addressable. No scene or assembly installation is performed.

The production model supplies thin panel backing with genuine through apertures, perimeter channel returns, rear flanges and split collars. It is a provisional visual receiving surround, not a flight-qualified mating adapter. Both instrument poses and sizes are preserved from accepted optional LM assembly `9016960683efabb491dfed16f10ea3ef90196d01`. Read-only accepted source and handoff snapshots are under `evidence/assembly/`.

## Fit decisions

| Item | Result |
|---|---|
| FDAI aperture | 154.05 x 154.05 mm, centered on accepted instrument XY |
| DSKY aperture | 212.3496 x 209.2 mm, centered on accepted instrument XY |
| Conservative clearance | 3 mm per side against full visual front envelope; minimum all-support AABB distance ~2.99984 mm FDAI / ~2.99998 mm DSKY due to float precision |
| Panel 1 outline | 395 x 500 mm, local center (+42.5,0) mm; outboard edge reduced 85 mm from reservation |
| Panel 4 outline | 400 x 340 mm, unchanged envelope |
| Backing / support rear | Backing -4 to 0 mm, collar 0 to +1 mm, open support rear at -34 mm in panel coordinates |
| Cabin surface intersections | Zero after the Panel 1 outline revision; initial 23 pairs retained as evidence |
| Instrument attachment | Unresolved: interface empties, no contact flange or instrument fasteners |

The full Panel 1 reservation intersects fixed CDR window geometry. The new narrowed outline resolves the measured intersections without changing optics, panel datums or instruments. Its join to surrounding Cabin structure is an open registration boundary, not an engineered bracket or sealed hull joint. Keep the Cabin reservation disabled. `clearance.json` reports exact bounds and findings; `evidence/full-reservation-collision.json` preserves the rejected outline evidence.

DSKY's current rear-box half-width equals drawing mounting-thread half-pitch (97.79 mm), leaving zero radial room at the thread centerline. Do not add threaded attachment through that proxy. Qualify the actual rear enclosure and seating datum before narrowing the aperture or adding hardware. FDAI has no verified LM-5 outline/seating dimensions. All new thicknesses, fastener heads and clearances are deliberate provisional choices. Open rear space does not qualify connector/cable service clearance. No bracket strength, insertion trajectory, ACA sweep, control collision, egress, head-box optical occlusion or hand reach is validated.

## Source and dependencies

All component references resolve at baseline `3ad1a999ff17aea859eaea5750f1c65e66fad673`; original histories remain intact. Last component commits: FDAI `c4c565f1b8d1c1a21c2b73e609d9c327aa816618`; DSKY `d8e35fa3ec8dc400cbb2762c24953022b07e8ebb` (retains upstream asset provenance in its handoff); Cabin handoff `8956702ee676e155670be2e2110a09196e0b1183`, asset `eb4efc12614ad45bd7df1d82e848f5f41b776c1e`.

Reference USDZ SHA-256: Cabin `777ce88968820a6e46995d436e807abf9f4b4a5cb7115d0eb03eafb4c89c995e`; DSKY `e20a69864d4c7e0ff068172e0e672d9fbcc510c1dc4e97e4db0246fde08fbdfd`; FDAI `4082ef22b4e8615e78a1e62182ed8d150585dcce1755492e6abb0784076c785d`. LFS hydrated locally for read-only checks. Helpers in `geometry.py` are adapted from baseline Cabin builder with provenance retained; regeneration does not execute another component's script.

Apollo 11 AS11-36-5389 and preflight 69-H-134 guide layered edge/face appearance only. DSKY drawing 2003956 Rev B page 73 establishes front envelope and thread pitch. Original URLs, full image/page rasters, later-mission FDAI caveats and file hashes are retained in `evidence/`. `evidence/DECISIONS.md` separates documented, inferred and deliberate provisional dimensions.

## Reproduce and validate

From the LMKit root, with hydrated baseline reference USDZ files and Blender 5.2.1 LTS (9e2066aef7ef):

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/CommanderPanels/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/CommanderPanels/validate.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/CommanderPanels/review.py
xcrun swiftc -parse-as-library -module-cache-path /tmp/commander-panels-swift-cache Assets/Cockpit/Components/CommanderPanels/validate_native.swift -o /tmp/validate-commander-panels
/tmp/validate-commander-panels "$PWD/Assets/Cockpit/Components/CommanderPanels/CommanderPanels.usdz" > Assets/Cockpit/Components/CommanderPanels/native-validation.json
```

`validation.json` records closed outward solids, nondegenerate faces, physical coordinate export, preserved instrument positions, conservative clearance against complete reference bounds, Cabin surface intersection check, no production reference duplication, USDZ compliance and roundtrip import. All 286 checks pass; USDZ compliance has zero errors/failures/warnings. `native-validation.json` records macOS RealityKit load, identity root, interface position/orientation and independently removable backing. These checks do not establish app integration or flight mechanical acceptance. Early validation-script issues (generated Blender image, parent traversal, unhydrated LFS references) were corrected before final reports.

Nine small labeled Workbench review images and exact camera metadata are under `reviews/`. The fixed-eye composition preserves the calibrated eye but uses Blender projection. Blue instruments are transient review references only; no display-state or material acceptance is implied. Section views clip reference exterior geometry only during review. No heavy renders or bakes; no visionOS runtime slot used.

## Coordinator steps

1. Review/cherry-pick the scoped commit and its local LFS objects. No publication is necessary for local integration.
2. Keep Panel_1_Reservation, Panel_4_Reservation and both glare shields disabled as accepted. Install `/CommanderPanels` at identity directly under Cabin, or extract each Panel child using the recorded transforms exactly once.
3. Preserve the existing live instruments and their bindings. Empty `FDAI_Interface` / `DSKY_Interface` nodes express the accepted poses; they do not request replacement instruments or bindings. Do not parent to a nested Cabin mount and reapply Cabin-relative values.
4. Resolve instrument contact hardware and Cabin structural joins before calling this a mounting-fit solution. Review the 85 mm narrowed Panel 1 outline and remaining frame gap; never move CDR optics to fill it.
5. Coordinator alone updates shared resource APIs, package resources and master assembly. After approved resource refresh using `Tools/sync_dsky.py`, run LMKit packaging tests and native app integration/visual tests. This worker did not refresh resources, run package tests against unchanged shipping resources, or claim simulator/headset acceptance.
