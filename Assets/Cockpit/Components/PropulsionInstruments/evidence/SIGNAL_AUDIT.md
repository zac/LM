# Read-only signal audit

Audit pins: AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`; LM integration `f9d77ea3a0b1c83dfafedd4768e579a5c24e8e08`. `signal-audit-files.json` records exact bytes read for the LMCore files, independent of checkout dirtiness. No AGC, LMCore or LM runtime files were edited.

| Input | Observed API | Safe conclusion |
| --- | --- | --- |
| DPS command | `LMVehicleSnapshot.dps.commandedThrustNewtons`, optional | Commanded force, not measured engine chamber pressure and not separate manual throttle demand. |
| Reference force | `LMDPSThrottleMap.ratedMaxThrustNewtons` = 10,500 lbf converted to newtons | Could support a host-qualified command percentage aid; not the exact historical CMD meter circuit. The map returns zero when the engine is off, whereas AOH describes a 10% CMD baseline/bias and TTCA/LGC summation. |
| Vehicle mass | `LMVehicleStateSnapshot.massKilograms`, optional | Total mass available; alone does not provide accelerometer specific force. |
| Propellant | `LMVehicleStateSnapshot.propellantMassKilograms`, optional aggregate | Default source-backed PDI leaves this nil. No fuel/oxidizer split, selected-tank capacity or individual quantity percentages. |
| Pressure and temperature | No chamber-pressure, tank-pressure/temperature or helium sensor fields | All related historical channels unavailable. |
| Specific force | Internal dynamics `specificForceBody`; no public snapshot sample | T/W physical accelerometer signal unavailable through the audited public boundary. |

Source pointers: `LMVehicleActuation.swift` lines 1–67 for throttle mapping; `LMVehicleCommands.swift` near 104–132 for DPS state; `LMSimulation.swift` near 661 for mass snapshot, 741 for sensor snapshot, 1590–1675 for contact gating, force integration and aggregate propellant burn, and 1849 for internal specific force. Line numbers refer to the audited files and may drift.

A DPS-only reconstruction using commanded force times gimbal cosines divided by total mass and lunar gravity would exclude RCS/contact contributions and is not the physical instrument. It is deliberately not enabled here. Net acceleration including gravity must never feed T/W: free fall is near zero proper force, not one lunar g. The snapshot may retain engine command after contact. Any later host effective-force aid must use LM's existing `LMVehicleSnapshot.isMainEngineProducingThrust(state:)` helper (PoweredDescentSession.swift near 815), which rejects terminal/contact states and applies on/off logic. Raw command may remain visible only with explicit command-source qualification. RCS frame pulse union is not a steady force or duty-cycle sample.

All channels in this delivery therefore begin unavailable. Needles and illuminated segments park behind opaque faces; a missing value must not become a plausible zero. Unavailable source data is not an electrical power-failure simulation. Any optional synthetic aid requires host-visible qualification and an explicit source adapter accepted by the simulation coordinator.
