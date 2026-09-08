# Panel inventory handoff

Owned task: `01a082c8-0171-7a93-a11d-d49ee8136592`, isolated `/Users/zac/.codex/worktrees/fc70/LMKit`, branch `codex/panel-inventory-enclosed`, clean start `09364460e8be570338f3d39a07067fe2bee0b044`. Only this component directory is changed. No runtime APIs, simulation, shared packaging, master assembly, peer assets, merge or push.

## Deliverables and scope

`PanelInventory.blend`, neutral `PanelInventory.usdz` plus USD intermediates, `inventory.json`, reproducible `build.py`, `validate.py`, native `validate_native.swift`, reports and twelve labeled/clean small review images. There are 28 panel/equipment groups and 66 stable region slots. These are blank development reservations, not detailed instruments or flight placards. Dimensions and subdivision boundaries remain provisional. Each physical panel has open perimeter returns and independent thin region blanks; no mandatory full backing bridges replaceable slots.

Numbered panels are 1–6, 8, 11, 12, 14, 16. ORDEAL is named independently. Other IDs describe AOT/COAS/camera/utility lights, ECS oxygen/water/LiOH/recirculation, LGC/DSEA/CDU, PLSS/waste/stowage and hatch valve equipment. No missing numeric panel IDs were invented. Structural hatches/engine cover and optical windows/shades remain registered external ownership. `evidence/ASSESSMENT.md` distinguishes generic/later source applicability from Eagle observations.

## Coordinate and replacement contract

- Root `/PanelInventory` is identity under Cabin. Units meters, +X right, +Y up, -Z forward. **Do not apply a panel transform again to this root.** Blender authoring is deliberately Y-up too; review cameras use explicit Y-up.
- Each panel `pose` is Cabin-relative. Slot `pose` is parent-local to its panel. Quaternion order xyzw; all scales one. Face plane is local XY with +Z toward crew. `envelope_center_local_m` locates volume bounds, rather than assuming symmetric depth about face origins.
- Paths are authoritative; repeated leaf names such as `Placeholder` must be resolved along the complete parent path, not by a global first-name search. IDs are unique even though leaf names are repeated under different parents.
- Composite panels have no whole-panel placeholder. Never delete a panel, frame or peer instrument when filling a child slot.
- Default missing/failed-load behavior leaves the individual blank enabled. Only after successful occupant loading and validation may the coordinator hide that slot's `default_placeholder_node`. Preserve its mount and independent label. Coordinator owns that runtime implementation.
- **Check `replacement_allowed` first.** `Panel5__Timer` is blocked by ACA clearance, with an intentionally empty placeholder Xform. It must not be filled automatically even if an asset loads successfully. Resolve its equipment layout and revalidate before installation.
- DSKY/FDAI are external occupant registrations; their blank geometry is fallback only. Existing runtime identities and exact transforms survive. CommanderPanels supplies Panel 1/4 shells and apertures; none are duplicated here. Existing ACA, pilot ACA and TTCAs are external records; only the existing commander ACA pose is specified. No binding is inferred from any name.
- Entire `/PanelInventory/PlanningLabels` layer is hidden by default in USD. Enable it for inspection only. Blender has a separate `PlanningLabels_INSPECTION_ONLY` collection, also hidden by default. Each slot label has its own path. There are no label textures baked into blanks or shells.

`modeled`, `bound`, `validated` describe the intended instrument's implementation/qualification, not the fact that a gray rectangle exists. Native resource validation is reported separately. `external-owner` delegates confirmation to the existing runtime owner; it is not a newly established live binding.

## Pinned interfaces

Cabin `2fafa5bda020b83cb7e6dff7af1a45cf6f9b35fe` interface-v1, exact retained P1–6 face poses; CommanderPanels mounting snapshot from baseline; Windows corrected `80c9b2d` interface-v1, final geometry `5699e64`. Copied contracts and SHA-256 hashes are recorded in the inventory. Windows interface hash is `28bb74258353bbc8365b7a54011782332ff69927c0683154a46b80b8ad24f22f`.

Side panels use Ry(±90°) × Rx(inclination) so long breaker strips follow Cabin depth. Breaker centers are provisional P11 (-.94,1.50,-.10), P16 (.94,1.52,-.10), with -20° inclination. Side lower trays retain 15° above horizontal and P14 36.5°. These are spatial reservations, not surveyed body stations. Aft faces at Z .86–.95 fit inside the peer's proposed closure Z1.15; positive-X oxygen/water is **left when looking aft**. The overhead valve reservation remains beside/below the transfer hatch, not a hatch-sized plate.

## Panel 5 / ACA resolution

Pinned LM `11f7335` `LMCommanderStationGeometry.swift` gives panel center (-.5588,.88,-.30), Rx -75°, depth .038. Converting center to face agrees with Cabin within 1 µm. The suggested earlier runtime/reservation discrepancy was not found at this pinned revision.

ACA root remains (-.49,.9075,-.37), identity rotation/scale. Before correction, the top tray rail and timer blank intersected the **fixed** housing mesh at neutral: 38 and 40 triangle pairs respectively, also present in all 27 sampled poses. `evidence/panel5-before-opening-clearance.json` preserves this evidence. It was an actual surface crossing, not merely an AABB warning.

The only correction is top-rail omission over panel-local X [.013,.125] and omission of the timer blank surface. Fixed housing projects to X [.018,.1196]; the notch adds a provisional 5 mm each side, with right endpoint rounded outward by .4 mm. No support, seating flange or hand-space qualification is claimed. The logical timer slot and planning label remain, machine-readably blocked. Other Panel 5 blanks, its pose and the controller are unchanged. Cabin peer confirmed the continuous exterior liner remains behind/below this equipment opening; it does not create an exterior hole.

## Validation and review limits

`validation.json` checks USD units, paths/IDs, disjoint slot UV envelopes, aligned separate label transforms, Blender-to-USD physical transforms and ARKit USDZ compliance. `native-validation.json` records actual macOS RealityKit loading, all 66 slot paths, panel translations/scales, independent placeholder and label toggles. No simulator was used.

`clearance.json` checks actual ACA triangle surfaces at 27 combinations of roll/yaw/pitch -11°,0°,11°. This is sampled surface intersection testing; containment, continuous sweep, housing support, hand reach and pinch space remain distinct. `windows-clearance.json` checks exact pinned Windows mesh surfaces, excluding planning labels; it is not an optical calibration or a service-clearance certificate.

Review front/commander/pilot images hide aft equipment for cutaway visibility; rear images hide forward equipment; side and overhead show all equipment. Those images deliberately omit peer enclosure/surround/instrument assets and therefore do **not** demonstrate combined historical cockpit appearance. Clean images hide the entire planning layer. The coordinator must review the assembled cabin, working DSKY/FDAI/ACA, actual replacement/fallback and headset sightlines.

Reproduce from repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python Assets/Cockpit/Components/PanelInventory/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python Assets/Cockpit/Components/PanelInventory/validate.py
xcrun swiftc -module-cache-path /tmp/panel-inventory-swift-cache -parse-as-library Assets/Cockpit/Components/PanelInventory/validate_native.swift -o /tmp/panel-inventory-native
/tmp/panel-inventory-native "$PWD/Assets/Cockpit/Components/PanelInventory"
```

Validator requires the pinned ACA and Windows LFS objects locally and reads them without changing peer files; temporary hydrated copies go to a new temporary directory. In this desktop sandbox Blender and RealityKit required approved native execution. Coordinator owns `Tools/sync_dsky.py` resource refresh and package tests after cherry-picking; they have not been run from this worker.

## Panel 2 window correction

Exact final Windows `5699e64d29ee0ec77c60d2324f64e51fe68156e3` mesh comparison initially found 10 crossing mesh pairs, only Panel 2 top/outboard frame and caution blank. `evidence/panel2-before-window-clearance.json` preserves these. The new P2 outline is now .395 m wide, centered panel-local X=-.0425, retaining the unchanged Cabin mount. This mirrors the existing P1 surround's provisional 85 mm outboard reduction. Its child blank regions were rearranged inside that outline; no installed instrument was moved. The manifest preserves the original mount envelope and separately records the actual reduced frame envelope. This is a clearance-driven visual choice, not a historical dimension claim.

Final worker result: **1,315 manifest/USD/physical-transform checks, zero failures; native RealityKit 66 slots pass; corrected P5 zero ACA surface-crossing mesh pairs over 27 sampled poses; zero surface-crossing mesh pairs against final Windows geometry.** These statements refer to the artifact hashes in `artifact-hashes.json`, not an assembled or deployed application.
