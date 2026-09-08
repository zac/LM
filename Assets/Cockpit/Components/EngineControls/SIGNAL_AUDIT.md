# Engine and contact signal audit

Read-only snapshots: LM `cc42b92e45aabc25513b05a6cac42f0d04a8c147`; AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`; LMKit asset base `035c5b3ad1a522cf6d25fb222d46c2fb4a4a8de8`. These are source observations, not live binding tests.

| Signal / API | Exact observed source | Meaning / binding decision |
|---|---|---|
| `state.landingGear?.isProbeContact` | AGC Sources/LMCore/LMLandingGear.swift:249,372,388–400,540,609 | Three-leg probe-tip geometric contact, latched true in the gear state. This precedes footpad contact in suitable terrain; optional gear state can be unavailable. Candidate probe observation only, not a complete powered/resettable lamp circuit. |
| `state.surfaceContact` | AGC Sources/LMCore/LMSimulation.swift:1812 (`state.surfaceContact ?? result.firstContact`); LMLandingGear.swift:478–481 | First pad contact snapshot. Not the probe light. Persists while gear settles. |
| `state.flightOutcome.isTerminal` | LMSimulation.swift:1585,1815–1830 | Stops propagation at terminal result; settling/failure determines classification. Not a direct crew ENGINE STOP or probe event. |
| `mainEngineOn`, `mainEngineOff` | LMVehicleCommands.swift:204–205, output channel 011 masks 010000 and 020000 | AGC output commands. Not input APIs for physical START/STOP buttons, and not proof of current thrust. |
| `commands.dps.commandedThrustNewtons` | LMSimulation.swift:1598–1602 | Thrust command enters dynamics only with engine-on, not engine-off, and no prior pad contact. Not measured chamber pressure or button illumination. |
| Automatic engine suppression | LMSimulation.swift:1597 `descentEngineStopped = state.surfaceContact != nil` | Existing simplification assumes crew shutdown at first footpad contact. It does not model the probe-to-crew-button sequence. |
| `LMVehicleSnapshot.isMainEngineProducingThrust(state:)` | LM PoweredDescentSession.swift:781–799 | Presentation/audio resolves terminal or pad contact to no thrust despite potentially latched AGC engine-on output. Do not derive physical button latch or lamp extinction from this helper. |
| Crew input surface | LMFrameInput.swift:152 onwards; PoweredDescentSession.swift:663–686 | Typed radar, attitude-mode, RHC and ROD, plus raw channels. No typed crew START/STOP/ENG ARM/lamp-reset interface found. Raw channel injection is not by itself a validated engine-button API. |

**Result:** engine buttons ship neutral and unbound. Probe, pad contact, terminal result, AGC command and actual propagated thrust remain separate. No new simulation is included. A future authoritative adapter must specify button electrical latch, arming/override exceptions, power, probe lamp latch/reset and restart behavior. Until then leave lamp neutral or clearly label any incomplete probe-only presentation outside the historical hardware.

Hardware evidence: later AOH pp3-81/3-87 describes engine button state; TN D-6722 tableII and p10 distinguishes momentary START and added two-action STOP reset latch. Their prose conflicts, so neutral geometry and independent plunger/latch/light components do not claim a complete mechanism. Apollo11 source evidence must choose any live reset sequence.
