# Commander instruments and interior detail phase

Authorized 2026-09-08. Baselines: LMKit main 4ac9e3e; LM cockpit/integration d495ca7. User correction: prioritize tasks and run as much useful work in parallel as possible; the user manages time. There are no estimated-time cutoffs, deadline-based omissions or time-boxed acceptance. The original filename is retained for existing references.

## Ranked scope

| Rank | Inventory slot | Bounded delivery | Reason / dependency |
|---|---|---|---|
| 1 | Panel1__RangeThrust | Altitude and altitude-rate instrument only, with separately addressable moving scales, fixed pointers, bezel and source-backed legends | Fills the primary descent readout. LM already exposes altitudeMeters and verticalSpeedMetersPerSecond. Verify display units, scale motion, sign, range and source validity; simulation truth is not automatically a modeled radar signal. Defer thrust/chamber-pressure and T/W behavior. |
| 2 | Panel3__Stability + Panel5__Engine | Correctly placed attitude-mode and DES RATE controls, reusing ControlLibrary where hardware matches | PoweredDescentSession already has attitudeMode and setROD; CrewControlPanel uses both. Verify actual subcontrol location against source drawings, since inventory regions are approximate. Preserve existing AGC routing, supported modes, spring return and release on cancellation/pause/scene exit. No abort, +X translation or manual-throttle implementation. |
| 3 | Panel1__CrossPointer | One commander cross-pointer with independently addressable needles and a documented supported landing display mode | Makes lateral/forward motion visible alongside altitude/rate and FDAI. Vehicle velocity exists, but aircraft/display coordinate conversion, scale and selected source require explicit mapping. No rendezvous/AGS modes without supported data. Resolve mapping with source review before binding; do not substitute unqualified axes. |
| 4, parallel | Panel11__Region1 through Region5; Panel16 later | Repeated breaker rows, labels and shallow mounting detail from the existing library | Strong visual density with reused geometry. Static hardware only; no invented electrical simulation. Begin with one commander strip. Avoid changing Cabin or the shared inventory datum. |

## Parallel work and integration

- Three functional component workers: altitude/rate instrument, mode/DES RATE controls, cross-pointer. Each has a separate component directory and branch from the accepted LMKit baseline; nobody edits another component's Blender/USD binaries or PanelInventory.
- Separate optional detail workers own InteriorDetails (cables/clamps, trims, seams, fasteners) and BreakerBanks (stepped breaker rows). These can land independently from the functional components.
- Coordinator owns LMKit packaging/resource APIs and assembly review; delegated runtime worker owns LM adapters and native verification. Agree neutral roots, moving-node identifiers, slot transforms and value contracts before detailed authoring; integrate rough loadable assets early.
- Independent source/data review runs alongside implementation. One simulator owner at a time; serialize expensive renders when required by actual resource use.
- Fix dark faces and seating enough to make the accepted station readable; source-qualified material/lighting detail remains distinct from physical photometric calibration.
- Priority determines review/integration order, not whether authorized work is completed. Do not invent temporal estimates or omit scope based on them.

## Additive interior detail lane

User authorized parallel, noncritical detail workers. InteriorDetails owns only `Assets/Cockpit/Components/InteriorDetails/`: separate Cabin-relative root, modest triangle budget, source-guided cable runs/clamps, fasteners, seam/edge trim and supports. Read the Smithsonian panorama observations and user images; no invented subsystem functionality. Preserve all Cabin/Windows/PanelInventory assets and datums. Avoid windows, hatch openings, replaceable slot volumes, instrument faces and ACA sweep. Keep detail groups independently removable; no input/collision components, lights or baked lighting. Return a neutral, optional overlay with explicit bounds and provenance. Coordinator can omit the overlay without breaking functional delivery.

## Acceptance

Each asset needs editable Blender source, reproducible export, source evidence, marked provisional dimensions, neutral USDZ and a mounting/binding contract. Missing/failed assets retain their blanks. A partially populated region must retain a neutral backing for unbuilt subcontrols. Existing DSKY, FDAI and ACA bindings remain intact.

Verify altitude/rate at selected known states, sign and unit conversions, zero/boundary/invalid data; mode and ROD interaction/release; cross-pointer axes and scale if included. Review a combined native commander-eye image for visible scales, seating, overlap and unchanged windows. Physical Vision Pro interaction remains untested.

## Outside this phase

- Engine START/STOP and LUNAR CONTACT: source/mechanical state and runtime semantics need work. LM currently resolves engine thrust as stopped at footpad/terminal contact; that is not a complete historical probe-light/crew-stop circuit. Do not present existing automatic behavior as a new working hardware control.
- Propulsion quantities, chamber-pressure and T/W meters: available command thrust and total vehicle mass do not establish every measured instrument signal.
- Full caution/warning system, DEDA/AGS, TTCA, ECS, radar controls, AOT/COAS, aft equipment, detailed ceiling and window shades.
- Panel5__Timer remains explicitly blocked by ACA clearance. Panel1 timers are separate slots but lower landing-demo priority and require a correct mission-time origin.
- LPD numerical/optical calibration remains outside this phase.

## Evidence checked

- `Assets/Cockpit/Components/PanelInventory/inventory.json`: exact region IDs, occupants, replacement restrictions and provisional poses.
- `Assets/Cockpit/Components/PanelInventory/evidence/controls-and-panels.md`: source-qualified control functions, instrument dependencies and unresolved engine-switch mechanics.
- LM `LM/PoweredDescentSession.swift`, `LM/CrewControlPanel.swift`, `LM/TerminalDescentCockpitView.swift`: currently exposed input paths and altitude/velocity presentation.
- [NASA Apollo Experience Report: Crew Station Displays and Controls](https://www.nasa.gov/wp-content/uploads/static/history/alsj/tnD7919DsplysCntrls.pdf), printed pp. 14–15 and 23: instrument/readability context, landing cross-pointer and engine-stop development. This supports hardware selection; the ranking and implementation scope are project judgments.

## Source correction

PGNS MODE CONTROL is on Panel 3 (AOH printed 3-65 / PDF 661), so use Panel3__Stability for its partial replacement. Panel1 guidance-selection hardware is a different function. Preserve AUTO/ATT HOLD semantics; unsupported OFF remains explicitly unbound.

## Worker ownership

| Lane | Branch | Owned component |
|---|---|---|
| Altitude/rate | cockpit/altitude-rate | AltitudeRate |
| Physical mode / DES RATE | cockpit/descent-controls | DescentControls |
| Cross-pointer | cockpit/cross-pointer | CrossPointer |
| Cable/clamp/trim details | cockpit/interior-details | InteriorDetails |
| Commander/pilot breakers | cockpit/breaker-banks | BreakerBanks |

All five worktrees started at ee3a19f. Later user correction removes all cutoffs from that historical plan commit. Worker commits are reviewed and merged preserving history; coordinator alone publishes main. LM runtime integration proceeds in cockpit/integration with a separate read-only signal-source review.

DES RATE source refinement: ad013 depicts an unplacarded switch on the engine-button guard/housing. The worker is evaluating Panel5__Engine partial mounting and ACA clearance rather than inventing a Translation-panel placard; no engine-button behavior is included.
