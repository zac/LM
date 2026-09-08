# Pilot and systems combined geometry review

Read-only exact authored USDZ snapshot; no source edits, simulator or expensive rendering. `results.json` contains every asset path/SHA-256, installation matrix, bounds, suppressed placeholder and tested component pair. `check.py` reproduces the audit; unchanged pair inputs are cached while changed geometry/mount pairs are recomputed. `final-hash-verification.json` independently rereads every input after the last run.

## Outcome

- **153 installed component-pair checks completed**, including all 36 new-vs-new combinations. No new-vs-new surface intersections remain.
- **61 actual named face/grip center rays** from the relevant commander/pilot design eye find no opaque peer geometry obstruction. Includes warning lenses, propulsion instrument faces, both contact lights, engine button light faces, mission/event readouts, event control grips and pilot FDAI center. Transparent glazing/glass/lens occluders are omitted from this purely geometric obstruction test.
- Commander contact clears CrossPointer/FDAI; pilot contact clears installed pilot/control peers. EngineButtons guard/reset geometry clears neutral ACA and DescentRate. Propulsion/TW clears AltitudeRate. Timers and warning banks clear each other and new propulsion hardware.
- MissionTimer initially crossed the left CommanderPanels return. Approved readout shifts to Mission slot X=-.030 / Event X=+.093 reduced but did not remove rear overlap. Worker narrowed only MissionTimer rear housing to 116 mm. **Final return crossing is zero**; face dimensions and approved mounting offsets are preserved. Previous evidence is in `before-timer-shift.json` and `timer-return-depth.json`. MissionTimer final SHA: `ef6eb8d8d54de5dc39b31f0f9f38a3151343dc8c73ede7762615c41613570bea`.

## Retained rear seating intersections

Fourteen mesh-pair crossings remain, all between instrument rear geometry and retained original backing/shell, with named visible-face rays unobstructed:

| Pair | Mesh pairs | Interpretation |
| --- | ---: | --- |
| Pilot FDAI / Cabin forward backing | 3 | Previously accepted rear shell penetration; no instrument trim/mount change requested. |
| Pilot lunar contact / retained Panel3 lighting blank | 3 | Partial-overlay rear seating; retain other lighting reservation. |
| Propulsion instruments / retained Propulsion and RangeThrust blanks | 6 | Rear housings penetrate retained partial backing; visible faces remain forward. |
| Mission and Event readout housings / retained Timers blank | 2 | Rear housing seating; no remaining CommanderPanels return crossing. |

These are explicitly unqualified mechanical fits, not new visible-face acceptance failures. Their full mesh paths are preserved in `results.json` (`mesh_paths` disambiguates importer suffixes). This audit does not modify or erase the rear-intersection evidence.

## Installation semantics checked

InteriorDetails, BreakerBanks and CautionWarning install once at identity under Cabin. Other components use the actual inventory panel/slot transforms and interface offsets. AltitudeRate retains its approved offset. MissionTimerControls is **uninstalled and omitted**. EngineButtons coexists with DescentRate in Panel5 Engine. Timer readouts have the approved right-side slot-envelope exception.

Full replacements suppress only corresponding placeholders: DSKY, commander/pilot FDAI, CrossPointer, AttitudeMode region, DescentRate's replaced Engine region, breaker strips and two warning banks. Accepted co-occupant neutral backing is retained. Partial propulsion/timer/lighting/control regions retain their blanks. Planning labels and the coordinator-known duplicate CommanderPanels backing strips are suppressed; perimeter returns remain included.

## Limits

Neutral authored state only. No continuous actuator/guard sweep, human hand reach, dynamics, self-intersection within a single asset, exact mechanical/fabrication fit, native lighting/labels, material transparency fidelity, simulator state, AGC binding or headset acceptance. Rays sample named face centers rather than all pixels or an entire eye box. A later asset or mounting revision requires affected checks again. Outputs are disposable review evidence and contain no source changes.

## Exact new asset hashes

- PilotFDAI: `4082ef22b4e8615e78a1e62182ed8d150585dcce1755492e6abb0784076c785d`

- EngineButtons: `eedf4dcadf8e075bc3d6084c273ea5a335506d3680966aa528298dcae7bec369`

- CommanderLunarContact: `6f97cc39c398f9f19555d7ea283e8d1c711deedd9b762cc529b53725d5f31346`

- PilotLunarContact: `6f97cc39c398f9f19555d7ea283e8d1c711deedd9b762cc529b53725d5f31346`

- PropulsionInstruments: `9eedc3e28ebc5be2b5da07c5c5ff99176c17df66df974879d0348d8061d8d1e8`

- MissionTimer: `ef6eb8d8d54de5dc39b31f0f9f38a3151343dc8c73ede7762615c41613570bea`

- EventTimer: `d22f9ec7b70c28a12725414f9150f2edb3f641c97c91c67cd0b7409326d8b540`

- EventTimerControls: `3cf2edba9154f991e386337acda721a3cd163c5cef22c5164f889ec28cce3cbb`

- CautionWarning: `580b16119a484c1a6138731e81e6960aab12324524dd267c0b227628e23b743b`
