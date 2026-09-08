# Pilot FDAI runtime integration

Branch `cockpit/pilot-fdai`, isolated worktree `/private/tmp/lm-pilot-fdai`, baseline `f9d77ea3a0b1c83dfafedd4768e579a5c24e8e08`. Resource checks use accepted LMKit `035c5b3ad1a522cf6d25fb222d46c2fb4a4a8de8`; simulation remains the existing AGC/LMCore interface with no changes. No push, simulator, heavy render, or LMKit asset edit.

Normal enclosed-cabin startup now attempts a second independent `LMImportedFDAI` at `Panel2__FDAI`. The existing commander instance and its mount remain unchanged. Both balls consume the same existing `LMVehicleStateSnapshot.attitude` through the accepted CDU/GASTA adapter. This is a presentation of the currently supported attitude source, not reconstructed pilot AGS/PGNS selection. Rate/error needles and the roll bug remain hidden in both instances.

The second asset is loaded separately; semantic lookup stays inside each loaded root. `FDAI_Mount` and child names intentionally repeat across the two instruments. No whole-station unique-name lookup is used to bind the pilot. The instance retains its fixed housing, unit scale, and independent ball. Installation immediately applies the last available snapshot, so a paused session does not leave the newly installed pilot at an unrelated neutral pose.

Before changing the chosen blank, installation validates the loaded hierarchy through the existing adapter, neutral root, geometry presence, and the 150 mm square face reservation. Failed IO or validation leaves the pilot blank and all peer equipment intact; a later retry may succeed. Successful installation is idempotent and introduces no collision, hover or input target. The explicit procedural-cockpit fallback does not add a pilot display.

## Source and fit

The accepted PanelInventory contract places `Panel2__FDAI` at panel-local `(0.060, -0.115, 0)` m, identity rotation and scale, under Panel 2's unchanged Cabin-relative pose. The retained NASA `ad013.gif` drawing in LMKit `Assets/Cockpit/Components/PanelInventory/evidence/` shows the pilot FDAI below the pilot cross-pointer in the right part of Panel 2. The inventory also records LM10+ AOH printed 1-8 / PDF21 and explicit later-mission applicability; it is not a surveyed LM5 installation.

The FDAI's source origin is its **proposed**, unverified panel seating plane. At identity under the accepted slot, its active native face bounds are 148.05 × 148.05 mm, leaving 0.975 mm per side inside the 150 mm visual reservation. It is not resized or offset to manufacture a fit. `Docs/Validation/PilotFDAI/fit.json` records actual USD bounds, exact asset hashes and slot matrix.

**Mechanical fit fails at the rear:** the housing and two case seams intersect `/Cabin/Shell/Cutaway_Forward/Forward_Above_Hatch` (80 reported mesh-face pairs). No other foundation/window/peer-panel surface crossing was detected. Rear geometry extends approximately 233 mm behind the provisional slot. The coordinator accepted this as a provisional visual installation with the rear conflict explicitly retained. No shell cutout, hidden trim, mounting hardware or fabricated clearance is introduced. This surface-intersection check excludes containment, continuous motion and optical visibility; it is not manufacturing acceptance.

## Validation and coordinator integration

Performed here:

- Swift parser checks for the edited scene and new app test suite.
- Read-only USD mesh inspection at the exact panel slot, including the rear conflict above.
- Actual macOS RealityKit double load: separate roots/balls, pilot-only rotation leaves commander and fixed housing unchanged, and native bounds fit the face reservation. See `native-resource.json` and reproducible `check_native.swift`.
- Scoped diff/whitespace review. No simulator or app test execution in this worker.

Coordinator test selector: `LMTests/LMPilotFDAIIntegrationTests` (three tests). It covers immediate last-snapshot application, subsequent shared attitude updates, independent entities and fixed geometry, scoped names, unavailable needles, no input components, exact slot placement, idempotence, missing/malformed/scaled assets, local rollback/retry, and normal-versus-procedural startup. Run with the existing commander assembly/instrument suites on the merged source.

Shared-file coordination: this branch changes only the scene property, normal-startup call, installer and attitude fan-out; it does not change `LMImportedFDAI` or assembly label code. The parallel readability worker owns shared FDAI material policy and planning occupancy labels. After merging that worker's new optional `installOccupant` argument, identify this occupant with `componentID: "Pilot FDAI"` so its planning label reads installed rather than pending. Both instances automatically benefit from the same accepted adapter material treatment.

Native camera acceptance still required: inspect the complete face and surround from both `--assembly-validation-view=cdr` and `--assembly-validation-view=lmp`, under identical mission lighting. Confirm commander identity/pose, pilot scale, no front-face occlusion by nearby equipment, visible ball markings through the lens, and planning label status without covering the display. These views and real Vision Pro stereo readability remain coordinator/device checks; the rear conflict remains open even if those views pass.
