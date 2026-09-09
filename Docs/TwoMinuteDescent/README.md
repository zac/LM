# Two-minute cockpit entry

Apollo cockpit entry now selects `TwoMinuteApproachCheckpoint.bplist` by default. This is a complete live AGC/vehicle checkpoint in P64 at about **205.53 m altitude**, with **120 seconds until soft landing** in the measured default-surface run. Restart uses the same selected checkpoint. No simulation speed, landing outcome or vehicle fields are fabricated.

`--cockpit-start-p64` retains the original full approach (209.27 seconds in this check); `--cockpit-start-p65` retains the short terminal descent. If both flags are supplied, P64 wins. Custom landing-site scenarios retain their existing P63 behavior. With no override, entering the Apollo cockpit uses the new two-minute start.

## Validation

The original P64 checkpoint was restored and advanced at 30 Hz to real soft landing. Its measured remaining flight was 6,278 steps. The new checkpoint was captured after 2,678 steps, leaving 3,600 steps. It round-trips through binary encoding without state differences. Restoring it reaches `softLanding` after 119.9999999999 simulated seconds, transitioning from P64 to P65. Reports record the starting altitude/time and final outcome. Five assertions against the extracted app launch-selection enum pass, and the changed app/test files parse. A visionOS Simulator-targeted app build succeeded in an isolated validation checkout. Xcode reserializes the binary plist during resource copying; the decoded bundled checkpoint is exactly equal to the source fixture despite different binary encoding. This was a build only, not an app launch or simulator test.

Timing is simulated time using the default LMCore contact surface. Rendered terrain, user input, pauses and machine load can change elapsed wall time and outcome. The app was not launched and the simulator was not controlled.

## Reproduction and provenance

Fresh dependencies were built from a read-only snapshot of the current AGC checkout, including existing uncommitted pad-load changes. Exact source, rope, baseline and generated-checkpoint hashes are retained in `provenance.json`; no AGC or LMKit source was changed. This is stronger provenance than assuming older build products match current sources.

To regenerate in a temporary directory, use `ValidationPackage.swift` as `Package.swift`, copy the recorded AGC and LMCore source directories to `Sources/`, and place `GenerateCheckpoint.swift` at `Sources/LMFlightRecorder/main.swift`. Run `swift run -c release --package-path <temporary-directory> LMFlightRecorder <LM-checkout>`. The driver verifies real touchdown before writing the new checkpoint/report. App resource inclusion follows the existing synchronized LM folder, requiring no Xcode project edit.
