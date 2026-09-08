# InteriorDetails phase 2 handoff

Branch `cockpit/interior-detail-phase2`, isolated `/private/tmp/lmkit-interior-detail-phase2`, baseline LMKit `035c5b3`. Only `Assets/Cockpit/Components/InteriorDetails/` changed. No shared resources, peer binaries, simulator, merge or push.

## Result and contract

The existing seven accepted groups remain unchanged. Six additional optional groups add forward overhead mesh/cover fields, aft-crown mesh inserts, a forward header cable pair, and provisional static fittings on the two closed hatch leaves. Thirteen independently removable groups total. Original mesh/topology/attribute fingerprints compare identically to accepted component commit `9eca80d651189d7790e662c32a96cca76c7087eb`; source evidence and exact fingerprints are included.

Identity `/InteriorDetails`, meters, +X right, +Y up, -Z forward, parent Cabin coordinate frame. No panel transform, slot fill/hiding, input, collision, physics, lights or simulation. Existing root and group identifiers retained. Hatch fittings assume the current static closed leaves; a future opening/removal must disable or reparent those two groups. All geometry is optional and independently removable.

Final USDZ SHA-256: `069cdfb9923a6953f1ce4ffc5053a948e0c4f76840866553435d778dfd84b201`.

Budget: **12,244 triangles**, 557 meshes, 9 materials, no textures or text mesh. Native hierarchy 571 entities. Below the original 15,000-triangle target. Blender 5.2.1 LTS build `9e2066aef7ef`. Exact groups/bounds in `interface.json`.

## Evidence and design limits

Shared user photos and coordinator Smithsonian LM-2 observations guide liner segmentation, restrained cable routing and simple hatch fittings; see `PROVENANCE.md`. Mesh pitch, plate proportions, routes, handle forms and fastener placement/count are provisional. No vent functionality, latch/pressure-seal/hinge design or mission-accurate hardware identity is implied. Open mesh patches sit ahead of existing liner surfaces; they do not create new holes in the shell. Original functional/instrument/window/breaker assets are untouched.

## Validation performed

- USD ARKit compliance: zero errors, warnings and failed checks. Identity root/meters/Y-up.
- All 557 mesh solids are manifold with positive signed volume.
- Zero actual triangle surface crossings against accepted Cabin, WindowsLPD, PanelInventory, CommanderPanels, neutral ACA, DSKY, FDAI, AltitudeRate, CrossPointer, AttitudeMode, DescentRate and BreakerBanks at contracted transforms. Input paths/hashes are in `validation.json`.
- Zero new-vs-other detail-group surface crossings; designed contacts within a single fitting/group remain intentional.
- Zero conservative overlaps with any of 66 reserved slot envelopes.
- **145 representative window rays** (center and 70%-inset vertex samples from CDR/LMP design eyes, including docking) encounter no InteriorDetails geometry. This is sampled obstruction checking, not full optical acceptance.
- Original seven group fingerprints preserved exactly.
- macOS native RealityKit loads the final USDZ, checks identity root and independent visibility for all 13 groups and inspects all 571 entities for absence of input/physics/collision/light components.
- Small Workbench crew, upper, hatch and crown views visually inspected. Mesh fields, cable clamps and handles read as shallow additions; no new gross window or standing-space obstruction appears. No heavy rendering or source-assembly save.

## Review semantics and remaining work

Review images use original cabin/windows/inventory/surround context with DSKY/FDAI fallback blanks, not current app state. Glazing and coordinator-known duplicate panel backing are hidden; labels remain hidden. Default commander plus dedicated overhead/hatch angles are included. App lighting/material differences and fine mesh aliasing need coordinator native/headset review.

No simulator or Vision Pro, continuous actuator/human sweep, fabrication fit, hatch interaction or full optical calibration qualified. Geometry tests compare exact input snapshots; later peer revisions require appropriate integration checks. Coordinator owns package resource synchronization and optional runtime installation. Omission/load failure must preserve all functional assets. No push or merge performed.
