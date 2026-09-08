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
