# Instrument simulator visual acceptance

Captured September 8, 2026 on visionOS 26.5, Apple Vision Pro 4K simulator `2F598E08-CF7D-43D7-8203-B0AB65897849`. Source is worker baseline `7a0d6d51bbcc43d54253274092b1f585a75f7053` plus the debug validation harness delivered with this report. Dependencies remain AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f` and LMKit `c75d37930fe34b7bf96dc5f757625ce5e983a489`, from isolated archives. `app-binary-sha256.txt` identifies the captured executable.

## Framing and scenario

The normal terminal-descent cockpit starts the real P64 simulation. Debug-only `--instrument-validation` applies the inverse observer pose to the complete scene, using the existing comfortable entry eye and aiming at the existing DSKY mount. All local cabin and instrument positions, orientation and metric scale remain unchanged. This is a repeatable debug observer view, not evidence that simulator camera automation succeeded. Native Simulator camera mode selection worked, but automated drag/key attempts did not produce useful camera motion. No sidebar browser mirror was established.

`--instrument-validation-inputs` additionally sends V16N36E, PRO, V35E and RSET through the production session FIFO. No instrument display or vehicle state is substituted. The trace samples real session state approximately every 250 ms. The capture script waits for the current process and relevant display state before capturing; JSON state and screenshot are adjacent observations, not an atomic frame/state pair. Register values or flash phase can advance between them.

## Captures and inputs

The final synchronized run is process **82830**, launched with both flags. `programmatic-inputs.jsonl` contains 166 samples through the last capture. `runtime.log` includes the final process plus a preceding trial; select `LM[82830:` for the final run. Screenshot timestamps are UTC; the runtime log uses local PDT.

| Evidence | Approximate UTC | Observed result |
| --- | --- | --- |
| [03 baseline](03-baseline.png) | 19:43:30 | Live P64 V06 N64 and descent registers before scripted input. |
| [04 V16N36E](04-v16-input.png) | 19:43:36 | Live V16 N36 monitor display after VERB, 1, 6, NOUN, 3, 6, ENTR. |
| [05 PRO](05-pro-input.png) | 19:43:46 | Programmatic PRO at 19:43:45; runtime display returns to V06 N64. |
| [06 V35E](06-v35-input.png) | 19:43:56 | AGC lamp test: P/V/N 88, three +88888 registers, white and amber annunciators, COMP ACTY. Spare lamp cells remain dark. |
| [07 RSET](07-reset-input.png) | 19:44:11 | Programmatic RSET at 19:44:10; live P64 descent continues, lamp test off and RESTART extinguished. |

Each final capture has a matching `-state.json` and `-time.txt`. The 120 ms PRO down interval was not caught by the 250 ms trace: all recorded `proPressed` values are false. Its runtime response is visible, while bounded down/up delivery and cancellation are covered by queue tests. This does not prove physical PRO interaction.

[01 live P64](01-live-p64.png) and `observation.jsonl` come from an earlier observation-only run. [02 pointer at VERB](02-pointer-at-verb.png) records a native Simulator interaction-mode pointer/click attempt at the imported VERB key. Hover appeared, but no completed physical DSKY key event was confirmed in logs. These are not successful pinch/key acceptance evidence. All successful inputs in captures 04–07 are programmatic.

## Visual findings and remaining gates

- One imported DSKY and one imported FDAI are visible; no legacy attachment duplicate is apparent in this view. Neither face is occluded by the other instrument or visibly clipped in this framing.
- DSKY digits, signs, lamp changes and AGC flash behavior are visible. Register values change during descent. Small key and lamp legends are dark and small from this observer distance; headset legibility is not qualified.
- FDAI ball markings/horizon change between captures while its housing remains fixed. The adapter's axis/sign/composition and fixed-pivot independence remain covered by native tests. These images do not calibrate instrument photometry or prove all attitude axes visually.
- Lighting is dark and the FDAI rim is reflective. Materials, transparency, stereo scale, frame time, neighboring-key selection, gaze/pinch and physical PRO ergonomics still require headset validation. Mechanical seating and panel/rear clearance remain provisional. No cabin geometry, instrument mounts or optional resources were changed.

This closes the missing DSKY rendered-face smoke check using a debug observer. Simulated gesture acceptance remains open.

## Repeat

Build the Debug visionOS simulator app with the pinned dependencies, then run:

```sh
Tools/CaptureInstrumentValidation.sh <booted-simulator-udid> <path-to-LM.app> <output-directory>
```

The script installs/relaunches the app, captures the sequence, and saves trace/logs and binary hash. It requires native Simulator access. Without the validation flags, observer framing and scripted inputs are inactive; the harness is absent from Release builds. Post-harness build/test passed **10 tests, 0 failures, 0 skips**, confirmed by xcresulttool; summary is saved alongside this report as `tests.json`. Result bundle: `/tmp/lm-instrument-final/Logs/Test/Test-LM-2026.09.08_12-46-32--0700.xcresult`. The full unrelated LM suite was not run.
