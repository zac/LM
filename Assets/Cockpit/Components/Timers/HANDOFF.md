# Timers handoff

Four neutral assets are ready for coordinator packaging:

| File/root | Install |
|---|---|
| MissionTimer.usdz / MissionTimer | Panel1__Timers, local(-.030,0,.004)m |
| EventTimer.usdz / EventTimer | Panel1__Timers, local(.093,0,.004)m |
| EventTimerControls.usdz / EventTimerControls | Panel3__TimerHeaters, local(0,.036,.004)m; retain lower heater blank |
| MissionTimerControls.usdz / MissionTimerControls | **Uninstalled**; Panel5__Timer is blocked by ACA |

All roots are identity, meters, right-handed +X right/+Y up/+Z toward crew. Readout face dimensions130 × 32 mm and84 × 32 mm are provisional. The pair has a16 mm gap. The coordinator approved the20 mm inward shift from the old blank for support by the actual structural panel; this intentionally overruns the nominal blank's right edge20 mm without moving a datum. `interface.json` is the authoritative semantic/mounting contract; `mounting.json` records nominal neighboring-slot separations and depth limits. Exact surrounding-mesh acceptance is coordinator-owned.

Mission digits use H100/H10/H1/M10/M1/S10/S1; event digits M10/M1/S10/S1. Each has seven independently addressable mesh childrenA..G and explicit masks/poses in the interface. All neutral segments are dark with inherited USD visibility. The runtime should use native unlit/emissive material swaps or explicit entity enable states, and keep absent/invalid values blank. The tuning fork has a historical internal-oscillator-fallback meaning; do not turn it into a general unavailable flag.

Every control has its own pivot and stem. Rotation is about local+X: -25 degrees upper,0 center, +25 lower. Event ResetCount is RESET(momentary)/UP(center)/DOWN(momentary); TimerControl is START(momentary)/center/STOP(momentary); MIN/SEC are TENS(momentary)/center/UNITS(momentary),2 Hz independent upward digit slew while held. The later Apollo 13 event timer changes to effective count UP automatically after countdown zero. The app stores selected direction separately from the spring-return lever pose; releasing DOWN to center must not issue a new UP command. The 1967 early countdown-wrap description is preserved as a source variation, not used silently. 1967 DataBook p4-62 labels ResetCount Mom-main-mom; late-flight retention was not independently surveyed. Mission control detent retention is not qualified and no live binding is proposed for the uninstalled bank.

`CLOCK_AUDIT.md` pins the inspected AGC/LM code and distinguishes runtime elapsed time, possible live AGC TIME2/TIME1 samples, and unrecorded event state. There is no fabricated launch epoch and no LMKit clock implementation. The separate app-state worker supplies event behavior; coordinator owns Sources/Tests/Tools, resource refresh, runtime bindings and final assembly.

Validation:4,845 Blender/USD assertions,  valid right-handed transforms and topology, no external dependencies, four ARKit USDZ compliance passes without warnings; 1,623 native macOS RealityKit checks covering all digits and all control detents. `reviews/` contains Workbench source/fit views and native SceneKit lens comparisons. Asset/source hashes are recorded in validation and evidence manifests. No Vision Pro/simulator test or rear mechanical-fit acceptance was performed.

Reproduce from LMKit root:

```sh
blender --background --python Assets/Cockpit/Components/Timers/build.py
blender --background --python Assets/Cockpit/Components/Timers/validate.py
python3 Assets/Cockpit/Components/Timers/validate_fit.py
blender --background --python Assets/Cockpit/Components/Timers/review.py
blender --background --python Assets/Cockpit/Components/Timers/review_fit.py
swiftc -parse-as-library Assets/Cockpit/Components/Timers/validate_native.swift -o /tmp/lmkit-timers-native
/tmp/lmkit-timers-native Assets/Cockpit/Components/Timers
swiftc Assets/Cockpit/Components/Timers/review_native.swift -o /tmp/lmkit-timers-preview
/tmp/lmkit-timers-preview Assets/Cockpit/Components/Timers
```

Blender must include its USD Python SDK (validated5.2.1LTS); native checks require macOS/RealityKit. Use a writable Swift module cache when sandboxed. Helpers preserve AltitudeRate→WindowsLPD/Cabin provenance. Only this component directory is changed; no peer assets or simulation files are edited.

Final independent assembly audit: MissionTimer rear housing was narrowed to 116 mm behind its unchanged 130 mm face, leaving a measured 1 mm gap to CommanderPanels left return at the approved mounting pose. Both readouts and EventTimerControls clear the other installed new components; all selected timer face/grip crew rays are unobstructed. Remaining timer intersections are only the intentional retained blank/rear-housing seating. See `assembly-clearance.json` for exact input hashes, tested pairs and limits.
