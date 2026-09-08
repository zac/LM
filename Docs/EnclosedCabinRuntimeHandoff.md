# Enclosed cabin runtime handoff

Integration branch: `cockpit/integration`. Baseline `6421d46779bdca51a31aaa8d5dfa6b2b8e7c3936`. Reviewed historical presentation `3a8b9b6a2ed4cc0c1dcc72675cfdff6dba65d013` was merged preserving history before implementation. Runtime resources are pinned for combined validation to LMKit `d1b0bb54a16adf69dd7b709420a91f639027dfc7`.

Normal cockpit startup now attempts the enclosed foundation. Cabin, WindowsLPD, CommanderPanels, and PanelInventory are separate sibling roots at the shared identity datum. The loader validates mount poses, component roots, window bases, interface agreement, removed Cabin visual paths, and all 66 inventory slots before changing the active station. Failed loading or validation retains the procedural cockpit. Existing DSKY/FDAI instances and key identities survive installation; existing ACA/ROD/attitude controls continue to own their state. No AGC or LMCore changes.

WindowsLPD becomes marking owner only after successful installation. Old procedural panes, frames, grids, and labels remain under the disabled fallback; the training digital marker stays hidden while imported windows own the markings. The old generic shape specimens are no longer installed. Cabin optical metadata remains intact and is scoped separately from Windows nodes.

The two outer pane reference origins intentionally differ. The procedural/Cabin metadata point is ray-projected; Windows starts at the inner origin offset 20 mm along the normal. Native inspection confirmed they lie in the same plane. Runtime compares plane coincidence and normals across those datums while separately validating exact Windows origins and full bases against its manifest. This does not qualify angular targeting.

Only successful validated external DSKY and FDAI bindings hide their own inventory placeholders. The reusable per-slot installer validates detached occupants before changing the chosen blank and rejects blocked, duplicate, empty, or non-neutral occupants. `Panel5__Timer` remains blocked and physically empty. Planning labels never change placeholder visibility. Combined review identified coplanar backing overlap; only `/CommanderPanels/Panel_1/Panel_1_RemovableBacking` and `/CommanderPanels/Panel_4/Panel_4_RemovableBacking` are disabled after inventory validation. Shell returns, fasteners, and aperture collars remain visible.

Inspection options:

- `--cockpit-planning-labels` enables the separate planning layer; the cockpit also has an independent planning-label button. Explicit runtime `isEnabled = false` is necessary because RealityKit did not honor the asset's authored invisible label layer as an entity enabled state.
- `--procedural-cockpit` forces the retained fallback at startup.
- Debug `--assembly-validation-view=front|side|crew-eye|cdr|lmp|rear|overhead` selects an observer. `cdr` aliases `crew-eye`. Views are inside the cabin and do not hide shell geometry; overhead looks toward the ceiling. Instrument-validation view retains precedence.
- Existing training flags remain separate. Every Cabin cutaway group and Hatches starts enabled in normal assembly.

Validation performed in this subtask: Swift parser checks for edited app/tests; detached macOS RealityKit compilation in Swift 6 mode and loading against packaged LMKit resources, checking four identity components, 66 slots, hidden planning labels, external placeholders, blocked timer, per-slot failed/successful replacement, and targeted backing visibility. This standalone check used a copied assembly source with resource-URL shims and the actual LPD implementation with its station X constant substituted. It does not establish an app build, simulator tests, or headset behavior. Scratch: `/private/tmp/lm-enclosed-validation/Validation.swift` and `validate`.

Updated app tests cover atomic fallback, live identities, imported marking ownership after recenter, scoped slot replacement, blocked timer, backing/shell ownership, preserved datums and enclosure, rejected window/panel misregistration, distinct outer reference origins, and observer selectors. Coordinator owns serial combined app tests and captures at the committed source head. No simulator or heavy render was started by this implementation task.

## Planning label visibility follow-up

Actual simulator captures at source `315124e` showed no planning text even when the app flag and enabled-state tests passed. Native inspection found all 66 text ModelComponents retained under 161 enabled subtree entities, with nonzero visual bounds. The authored USD parent still had `visibility = "invisible"`; toggling `Entity.isEnabled` did not establish visible rendering. The coordinator is deriving the runtime package with only that parent changed to `visibility = "inherited"`, retaining the authoring asset and manifest's default-hidden intent. LM continues to disable the layer explicitly at load. A regression test now checks every label retains mesh/material data and verifies toggling leaves every blank's state unchanged. Actual visibility still requires the coordinator's simulator comparison of the corrected package.
