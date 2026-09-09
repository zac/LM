# Commander station assembly validation

Source checkpoint: `7a4247cfee6d16dd815aebc00c927b034049cccf`. Dependency revisions, hydrated file sizes and hashes: [dependencies.json](dependencies.json). Registration, control status and mechanical limits: [handoff](../../CommanderStationAssemblyHandoff.md).

The assembly is opt-in with `--commander-station-assembly`. The three assembly cameras use `--assembly-validation-view=front`, `side`, or `crew-eye`; all are DEBUG only. Exact cabin-relative eyes and targets are in [observers.json](observers.json). Each applies an inverse observer pose to the complete scene. Local instrument geometry and metric scale are unchanged. `--instrument-validation` takes precedence and disables assembly camera selection; the existing observer and real-session trace harness remain unchanged.

## Repeat

Use a dedicated visionOS 26.5 simulator. This run reserves `94C9CF9E-5495-4431-88AF-F3C211FD04C6` (LM Commander Assembly 5fa5). Do not run competing visionOS XCTest clones/captures. Set `-parallel-testing-enabled NO` and use selectors `LMTests/LMCommanderStationAssemblyTests` plus `LMTests/LMInstrumentIntegrationTests` when invoking the build runner. The skill runner's selector syntax required a temporary correction to `-only-testing:<selector>`; shared skill files were unchanged.

After the serial tests finish, boot that simulator and run:

```sh
Docs/Validation/CommanderStationAssembly/capture.sh <UDID> <LM.app> <output-directory>
```

The script captures front, side, actual calibrated crew-eye and existing instrument-observer views. It saves launch PIDs, timestamps, real-session observation samples and runtime logs. The executable AND Debug dylib hashes identify the rendered code. Assembly views use the real cockpit startup; the additional instrument view uses observation-only tracing with no scripted keys. These are monoscopic simulator observer images, not headset or completed physical key evidence.

## Native contract check

[native-mount-contract.json](native-mount-contract.json) records all ten authored root-relative mounts and both CDR pane corners/normals compared with actual app optical source. This independent macOS RealityKit check is not a simulator result. Reproduce from the LM root:

```sh
xcrun swiftc -parse-as-library -module-cache-path /tmp/lm-assembly-swift-cache \
  LM/LMCommanderStationGeometry.swift LM/LMLandingPointDesignator.swift \
  Docs/Validation/CommanderStationAssembly/validate-native.swift -o /tmp/lm-assembly-contract
/tmp/lm-assembly-contract <pinned-LMKit>/Sources/LMKit/Resources/Cabin
```

All corner errors were zero; normal errors below 2.2e-7 and mount matrix-column errors below 2.5e-7. Original family mesh and cabin acceptance records remain in pinned LMKit; no Blender renders or authoring changes were performed.

## Test and build result

Final captured source `7a4247c` built for visionOS Simulator and passed **14 tests, zero failures/skips**, comprising all four assembly tests and the original ten instrument/FIFO tests. [tests.json](tests.json) is the xcresulttool summary. The first serial run's one failure was exact floating-point equality on a reservation's decomposed scale (`1.0000001`); [initial-tests.json](initial-tests.json) retains it. The corrected test uses a 1e-5 tolerance, without changing production geometry. The full unrelated LM suite was not run.

## Final capture review

| View | PID | UTC capture | Findings |
|---|---:|---|---|
| [Front](front.png) | 6453 | 20:16:44 | One complete DSKY face and one complete FDAI face. Functional Panel 5 controls remain distinct. Generic specimen board appears at left, partly outside framing. |
| [Side](side.png) | 6492 | 20:16:56 | Both complete faces visible, with exposed instrument rear housings. No panel mesh covers either face in this view. |
| [Calibrated crew eye](crew-eye.png) | 6591 | 20:17:09 | Both complete faces fit after the documented DEBUG aim correction. DSKY remains oblique; this does not establish comfortable reach, stereo depth or key legibility. |
| [Existing instrument observer](instrument-observer.png) | 6667 | Trace 20:17:19–22 | Real P64 V06 N64 and changing descent registers; observer still aims at the original app mount, so relocated FDAI is cropped at the upper edge. It is retained as trace/DSKY evidence, not the full-face assembly view. |

All times are September 8, 2026. Runtime log contains preceding trials too; select the four PIDs above. Each logged successful atomic skeleton installation followed by live P64. `observation.jsonl` contains 14 observation-only real-session samples from PID 6667. No script input or native gesture was injected in this capture pass. Display/trace observations are adjacent, not atomic frame/state measurements.

Initial old-registration images, observer metadata, binary hashes and its test summary remain under [baseline-registration](baseline-registration/). That crew-eye view was rejected because the FDAI was too near/oblique and Panel 3 obscured part of the DSKY. The final forward relocation is intentionally provisional; it resolves that visible obstruction without moving the optical eye or panes.

The images show open panel reservations and exposed housings rather than certified installation. Backings for panels 1/4 are absent, not mechanically fitted holes. Supports and incomplete hull allow exterior/terrain to be visible through gaps. Panel-to-shell continuity, hatch/threshold clearance, rear housing clearance, omitted shields and generic specimen backing penetration remain unresolved. No duplicate procedural/imported cabin or instrument renderer is active after installation; native scene tests support that observation.

Lighting is highly contrasted: shell rails are bright, instrument housings/legends dark and the FDAI rim strongly reflective. No scene lights or imported instrument materials changed in this worker. Independent readability-worker changes are not in these captures. Dynamic shadow casting is disabled on skeleton meshes, but shadow reception, photometry and frame time have not been qualified. Existing control input volumes are retained; shell collision, egress, ACA swept volume and hand reach are not validated. Moving DSKY forward increases reach distance, which requires headset review. Actual pinch/key completion, pressure-tight hull and certified fitting remain explicitly unclaimed.
