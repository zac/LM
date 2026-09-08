# InteriorDetails handoff

Branch `cockpit/interior-details`, isolated worktree `/private/tmp/lmkit-interior-details`, baseline `ee3a19f21e31d77645e7b6451db800d2b3d60f5e`. Only `Assets/Cockpit/Components/InteriorDetails/` is owned/changed. No merge, push, package refresh, shared-source edit or peer asset save performed.

## Delivery

Optional additive `InteriorDetails.usdz`, editable `InteriorDetails.blend`, reproducible `build.py`, USD intermediates, `interface.json`, `PROVENANCE.md`, geometry/native validators and small combined review images. Seven independently removable groups: two lower cable harnesses, two lower liner trims, two upper crown cable/seam groups and one forward header trim.

Root `/InteriorDetails` is identity under Cabin: meters, +X right, +Y up, -Z forward. No panel transform, slot replacement or blank hiding. The optional resource may fail or be omitted without changing the existing foundation or instruments. No lights, input, collision, physics, animations or simulation. No breaker details; separate BreakerBanks component owns that scope. Material appearance is neutral and uncalibrated.

**USDZ SHA-256:** `1d6fef1c8815d902235bdb0df32d201dbc25ac95fb7bb6ff90852781ed918231`

**Budget:** 7,024 triangles, 278 meshes, 7 materials; no textures or text geometry. Native hierarchy contains 286 entities including root/groups. Under the proposed 15,000-triangle budget. Blender 5.2.1 LTS build `9e2066aef7ef`.

## Geometry/source decisions

All dimensions and paths are provisional source-guided reconstruction. Three supplied photos and the coordinator's LM-2 panorama notes were inspected; no exact Apollo 11 cable routes or hardware dimensions can be inferred. Existing twelve-facet Cabin crown geometry supplies the upper mounting surface. Forward header trim is on the existing `Forward_Above_Hatch` plane. Slots and existing structural supports constrain trim locations; no underlying asset is changed. Cables are capped visual segments with unknown destinations rather than invented subsystem connector identities. Mirrored station treatment is explicitly provisional.

Actual bounds for every group are in `interface.json`. Lower routes remain around |X|1.14–1.17, Y.21–.31; upper details around |X|.73–.90, Y1.84–2.01; forward header Y1.87–2.11 at Z-1.01. Header returns were moved inward to clear center-stack supports. The forward lower seam straps stop below side tray slot envelopes.

## Validation performed

- USD ARKit compliance: no errors, failed checks or warnings; meters/Y-up, identity root, no camera/light/physics/input schema.
- All 278 component meshes are closed manifold solids with positive signed volume after outward-normal normalization.
- Exact triangle surface comparison: **zero crossing pairs** against the pinned Cabin, WindowsLPD, PanelInventory, CommanderPanels and neutral mounted ACA assets. Exact paths and SHA-256 input hashes are in `validation.json`.
- Conservative oriented slot-envelope comparison for all 66 existing slot reservations: **zero candidate overlaps**. This is independent of the fact that slot blanks are thinner than future instruments.
- Native macOS RealityKit loads the actual USDZ, verifies identity root, independently toggles all seven groups, and inspects all 286 entities for absence of collision/physics/input/light components. `native-validation.json` records actual native bounds.
- Small Workbench reviews were visually inspected: lower CDR/LMP context, CDR closeup, upper CDR crown and default CDR forward. No new gross window occlusion or standing-space obstruction appears. Header strips are deliberately subtle; upper runs become clearer when looking toward the side crown. Material/illumination/headset appearance is not qualified by Workbench.

## Review semantics and limitations

Review images include the cabin/windows/inventory/commander surround context but leave DSKY/FDAI as fallback blanks; this worker does not replicate live runtime instrument installation. Glazing is omitted for Workbench and the coordinator-known duplicate CommanderPanels backing is hidden. Planning labels stay hidden. No authoring source is saved from these review assemblies.

Not tested: Vision Pro, simulator/app integration, future detailed instrument/breaker combinations, continuous human/hand sweep, optical eye-box, exact support/fastener seating or fabrication fit. Native load and geometry checks do not establish runtime frame cost or historic mission accuracy. All surfaces are visual; absence of physics means they cannot obstruct a simulated body through collision, while physical human clearance still needs review.

## Coordinator actions

Cherry-pick the component commit, refresh package resources through the coordinator-owned tooling, expose the optional URL/interface, and add identity under Cabin after load validation. Do not hide any fallback slot. Include it in the next combined runtime visual acceptance, retaining the existing live instruments. If any future equipment needs this volume, hide the affected named detail group or revise its provisional route; functional equipment has priority.
