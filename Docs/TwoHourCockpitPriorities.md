# Two-hour cockpit priorities

Authorized and started 2026-09-08 at 21:33 UTC (14:33 PDT). Target cutoff 23:33 UTC; freeze additions by 23:03 UTC. Baselines: LMKit main 4ac9e3e; LM cockpit/integration d495ca7. Priority is a readable, functioning commander landing station. Time boxes are planning limits, not completion guarantees.

## Ranked scope

| Rank | Inventory slot | Bounded delivery | Reason / dependency |
|---|---|---|---|
| 1 | Panel1__RangeThrust | Altitude and altitude-rate instrument only, with separately addressable moving scales, fixed pointers, bezel and source-backed legends | Fills the primary descent readout. LM already exposes altitudeMeters and verticalSpeedMetersPerSecond. Verify display units, scale motion, sign, range and source validity; simulation truth is not automatically a modeled radar signal. Defer thrust/chamber-pressure and T/W behavior. |
| 2 | Panel1__Guidance + Panel5__Translation | Correctly placed attitude-mode and DES RATE controls, reusing ControlLibrary where hardware matches | PoweredDescentSession already has attitudeMode and setROD; CrewControlPanel uses both. Verify actual subcontrol location against source drawings, since inventory regions are approximate. Preserve existing AGC routing, supported modes, spring return and release on cancellation/pause/scene exit. No abort, +X translation or manual-throttle implementation. |
| 3 | Panel1__CrossPointer | One commander cross-pointer with independently addressable needles and a documented supported landing display mode | Makes lateral/forward motion visible alongside altitude/rate and FDAI. Vehicle velocity exists, but aircraft/display coordinate conversion, scale and selected source require explicit mapping. No rendezvous/AGS modes without supported data. Drop from this sprint if that mapping cannot be verified quickly. |
| 4, stretch | Panel11__Region1 through Region5; Panel16 later | Repeated breaker rows, labels and shallow mounting detail from the existing library | Strong visual density with reused geometry. Static hardware only; no invented electrical simulation. Begin with one commander strip. Avoid changing Cabin or the shared inventory datum. |

## Parallel work and finish window

- Three functional component workers: altitude/rate instrument, mode/DES RATE controls, cross-pointer. Each gets a separate new component directory and branch from the accepted LMKit baseline; nobody edits another component's Blender/USD binaries or PanelInventory.
- Coordinator owns LMKit packaging/resource APIs, LM adapters, master assembly and legibility/lighting. Agree neutral roots, moving-node identifiers, slot transforms and value contracts before detailed authoring; integrate rough loadable assets early.
- Minutes 0–15: contracts and source/fit checks. Minutes 15–70: component work and incremental packaging/binding. Minutes 70–90: finish and freeze selected deliverables. Minutes 90–120: combined simulator acceptance, regression fixes and publication. Only one simulator run at a time; serialize expensive renders.
- If behind at minute 70, cut cross-pointer first, then cosmetic detail. A delivered altitude/rate instrument plus working mode/DES RATE controls is the minimum target. Breaker rows do not displace integration time.
- Address dark faces and instrument seating enough to make the accepted station readable. This is a presentation pass, not a new historically calibrated lighting system or a cabin redesign.

## Additive interior detail lane

User authorized a fourth, noncritical worker. Own only `Assets/Cockpit/Components/InteriorDetails/`: separate Cabin-relative root, modest triangle budget, source-guided cable runs/clamps, fasteners, seam/edge trim and shallow stepped breaker banks. Read the Smithsonian panorama observations and user images; no invented subsystem functionality. Preserve all Cabin/Windows/PanelInventory assets and datums. Avoid windows, hatch openings, replaceable slot volumes, instrument faces and ACA sweep. Keep detail groups independently removable; no input/collision components, lights or baked lighting. Return a neutral, optional overlay with explicit bounds and provenance. Coordinator can omit the overlay without breaking functional delivery.

## Acceptance

Each asset needs editable Blender source, reproducible export, source evidence, marked provisional dimensions, neutral USDZ and a mounting/binding contract. Missing/failed assets retain their blanks. A partially populated region must retain a neutral backing for unbuilt subcontrols. Existing DSKY, FDAI and ACA bindings remain intact.

Verify altitude/rate at selected known states, sign and unit conversions, zero/boundary/invalid data; mode and ROD interaction/release; cross-pointer axes and scale if included. Review a combined native commander-eye image for visible scales, seating, overlap and unchanged windows. Physical Vision Pro interaction remains untested.

## Deferred

- Engine START/STOP and LUNAR CONTACT: source/mechanical state and runtime semantics need work. LM currently resolves engine thrust as stopped at footpad/terminal contact; that is not a complete historical probe-light/crew-stop circuit. Do not present existing automatic behavior as a new working hardware control.
- Propulsion quantities, chamber-pressure and T/W meters: available command thrust and total vehicle mass do not establish every measured instrument signal.
- Full caution/warning system, DEDA/AGS, TTCA, ECS, radar controls, AOT/COAS, aft equipment, detailed ceiling and window shades.
- Panel5__Timer remains explicitly blocked by ACA clearance. Panel1 timers are separate slots but lower landing-demo priority and require a correct mission-time origin.
- LPD numerical/optical calibration remains outside this sprint.

## Evidence checked

- `Assets/Cockpit/Components/PanelInventory/inventory.json`: exact region IDs, occupants, replacement restrictions and provisional poses.
- `Assets/Cockpit/Components/PanelInventory/evidence/controls-and-panels.md`: source-qualified control functions, instrument dependencies and unresolved engine-switch mechanics.
- LM `LM/PoweredDescentSession.swift`, `LM/CrewControlPanel.swift`, `LM/TerminalDescentCockpitView.swift`: currently exposed input paths and altitude/velocity presentation.
- [NASA Apollo Experience Report: Crew Station Displays and Controls](https://www.nasa.gov/wp-content/uploads/static/history/alsj/tnD7919DsplysCntrls.pdf), printed pp. 14–15 and 23: instrument/readability context, landing cross-pointer and engine-stop development. This supports hardware selection; the ranking and two-hour scope are project judgments.
