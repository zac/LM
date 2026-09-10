# Pilot station, systems instruments and interior refinement

Authorized 2026-09-08 after commander-instrument acceptance. Baselines: LMKit main035c5b3; LM cockpit/integrationf9d77ea. Work is local, isolated by branch/component. Priority determines integration order, with no time estimates, deadline-based omissions or cutoffs. Coordinator owns final packaging, assembly, native simulator validation and publication.

## Parallel ownership

| Priority | Lane | Branch | Owned scope |
|---|---|---|---|
| 1 | Pilot FDAI | cockpit/pilot-fdai (LM) | Second independent existing FDAI instance at Panel2; supported attitude binding and fallback |
| 2 | Readability | cockpit/cabin-readability (LM) | Runtime materials and accurate planning labels; preserve consistent mission lighting |
| 3 | Timers | cockpit/timers (LMKit) | Assets/Cockpit/Components/Timers; source/read-only clock audit and hardware |
| 4 | Engine/contact | cockpit/engine-controls (LMKit) | Assets/Cockpit/Components/EngineControls; source and signal audit, neutral hardware |
| 5 | Propulsion instruments | cockpit/propulsion-instruments (LMKit) | Assets/Cockpit/Components/PropulsionInstruments; independent moving elements and qualified signal contract |
| Parallel | Interior refinement | cockpit/interior-detail-phase2 (LMKit) | Assets/Cockpit/Components/InteriorDetails; preserve accepted groups, extend overhead/hatch/cable detail |
| Parallel | Warning panel faces | cockpit/caution-warning (LMKit) | Assets/Cockpit/Components/CautionWarning; addressable neutral lamps and source labels |

An independent read-only signal reviewer checks mission/event time, engine command paths, probe/pad contact, quantities and warnings. Each model worker returns a mounting interface early, then editable Blender, reproducible authoring, neutral USDZ, evidence, provisional dimensions, geometry checks and review views. Shared Sources/Tests/Tools and master assembly are coordinator-owned. Worker commits preserve provenance; workers do not publish main/integration or overwrite peers' binaries.

## Runtime rules

The second FDAI initially uses the supported attitude source in a separate runtime instance. Independent PGNS/AGS selections remain unavailable until their real semantics exist. Simulation elapsed time is not automatically mission elapsed time. Mission epoch, restart, pause and replay must be explicit. Panel5__Timer remains blocked by ACA clearance; do not conceal the conflict by relocating historical controls without qualification.

Use landing-gear probe state for any qualified contact indication; footpad contact, engine-off outputs and terminal landing outcome are different signals. A raw output channel bit is not a crew input API. Engine controls must remain explicitly unbound if authoritative input behavior is absent. Measured chamber pressure, propellant/helium quantities and caution/warning circuits must not be synthesized from unrelated available values. Unsupported systems can have credible neutral geometry and honest host-side qualifications.

Initial engine audit identifies landingGear.isProbeContact separately from surfaceContact and flightOutcome. No typed crew ENGINE START/STOP path is present in the audited baseline; this is a signal-implementation dependency rather than permission to infer one from mesh names.

## Acceptance

Preserve DSKY/FDAI/ACA, altitude/rate, cross-pointer and mode/DES RATE behavior, source mount datums, optional overlay fallback and the corrected startup lighting. Keep unbuilt partial-region backing. Update planning labels to reflect actual occupancy. Qualify dimensions and signal provenance. Review the combined assembly in native visionOS simulator and retain exact source/resource hashes, test results and normal/inspection comparisons. Only one simulator owner at a time; no physical Vision Pro acceptance is claimed without a device session.

## Clock and system-source audit

The audited AGC/LMCore revision is `b3f15533db335ee882dc07401790c93010809e8f`. `LMSimulationSnapshot.timeSeconds` is runtime elapsed time, reset/restored with the session; it is not launch GET. `Luminary99LandingPadLoad.pdiClockCentiseconds` gives a sourced epoch for scenario geometry, but its `clockWords()` helper has no callers in audited Sources. Runtime construction does not establish a mission-timer preset, and `loadP63PadLoads()` places TLAND relative to the existing AGC counter. Therefore this phase does not present that counter or a manufactured offset as a historically synchronized mission timer.

The app-owned event timer advances from supplied simulation time with explicit session generation, pause/restart and replay availability. Its later Apollo 13 countdown-to-count-up behavior is a documented hybrid, not an Apollo 11 qualification. Engine START/STOP stays inert: starting or stopping `PoweredDescentSession` is not an engine-button command. Only optional `landingGear.isProbeContact` supports the qualified contact lamps. Missing data stays distinguishable from false in host status. Pressure, separated propellant/helium quantities, historical T/W indication and CWEA/master-alarm behavior are unavailable in this baseline.

## Accepted package checkpoint

All five model deliveries are merged with original worker history, including the second InteriorDetails pass; receipts and exact revisions are recorded in `Provenance/pilot-systems-acceptance.json`. Required DSKY refresh completed. Native macOS SwiftPM/RealityKit validation passes all 13 test functions, including two parameterized functions with 14 resource cases each. Shipping resources are byte-identical to accepted exports. The combined geometry audit checks 153 component pairs and 61 named face/grip sightlines; no new-component intersections or blocked sampled rays remain. Fourteen rear seating/backing mesh-pair intersections remain documented, including the pilot FDAI shell penetration. These checks do not qualify fabrication or headset appearance.

Consuming LM runtime `bdbf70f` passed 98 tests across 18 suites on visionOS 26.5 Simulator; integrated history and evidence are published at `471b473` on cockpit/integration. The second FDAI, event timer and probe-contact lamps are installed; unsupported mission time, engine commands, propulsion quantities and warning circuits remain unavailable. Corrected shell shadows and normal/planning/fallback views are documented in the consumer gallery linked by Provenance/pilot-systems-acceptance.json. Physical Vision Pro acceptance remains outstanding.

The user subsequently identified a substantial visual-quality gap: exposed instrument housings, skeletal console framing and flat backing do not convey solid embedded equipment. Prioritize coherent console volumes, recessed FDAI/DSKY mounting, window reveals and enclosed lower consoles before additional small controls. This follow-up does not invalidate the source-qualified runtime tests; it means interior visual quality is unfinished.
