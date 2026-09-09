# Instrument interaction/readability evidence

Final source `f1f612ed6e4440fb8977c0776b3cc335ee7791e9`, based on LM `acff0aeac62fc3c009831f0234d56205d36011e4`. Both before and after runs use isolated hydrated LMKit `75bdea77b57e0ae4971bb4ffbee21c4643e3b4cf` and AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f` snapshots.

Dedicated Apple Vision Pro 4K simulator `31D2A5CF-B052-42BC-86B3-590CABDDDA49`, visionOS 26.5 (23O470), Xcode 26.6 (17F113). All captures use the original opt-in inverse observer, aimed at the existing DSKY mount. Instrument transforms and metric geometry remain unchanged. Native Simulator camera controls were not used to reposition this observer; a numeric native camera pose is not exposed by the available tool. The applied observer root transform is recorded exactly in each after state sample:

- Eye meters: `[-0.5837999582, 3.760999918, -0.1279999614]`.
- Target meters: `[-0.02500000037, 3.027112484, -0.7231005430]`.
- Root position meters: `[0.5132037997, -2.592127085, -2.742229939]`.
- Root quaternion XYZW: `[0.3328682482, 0.3437106907, 0.1317855567, 0.8681556582]`.

## Before/after

| State | Before | After | Input |
| --- | --- | --- | --- |
| P64 baseline | [before](before/03-baseline.png) | [after](after/03-baseline.png) | None yet |
| V16 N36 monitor | [before](before/04-v16-input.png) | [after](after/04-v16-input.png) | Programmatic V16N36E via FIFO |
| Return V06 N64 | [before](before/05-pro-input.png) | [after](after/05-pro-input.png) | Programmatic PRO |
| V35 lamp test | [before](before/06-v35-input.png) | [after](after/06-v35-input.png) | Programmatic V35E |
| Reset | [before](before/07-reset-input.png) | [after](after/07-reset-input.png) | Programmatic RSET |

Keycaps are visibly brighter and dark ink is easier to distinguish. Off lamp backgrounds are lifted modestly; on white/amber annunciators remain clearly distinct. Lamp-test legends and fine print remain small at this observer distance. No physical geometry was enlarged. Native material emission is an appearance floor; no bloom, measured electrical behavior or historical photometry is claimed.

The FDAI fixed mask/bezel/surround is less specular; three native PBR surfaces are verified by the passing test. Bright regions remain at the ball edge. This does not establish that all apparent reflections have been eliminated. One imported FDAI and DSKY are visible, with no duplicated instrument faces. FDAI ball markings move between live captures while the fixed housing stays still. Attitude signs/composition and fixed-versus-ball independence are also covered by native tests.

State JSON and screenshot are adjacent samples, not atomic pairs. Flash phase and register values can advance between them. Capture manifests identify source, dependencies, input method and simulator. The before script hashed only the launcher; final captures hash `LM.debug.dylib` as well, where Debug implementation resides.

## Automated checks

[Final serial xcresult summary](tests.json): **12 passed, 0 failed, 0 skipped**. Local result bundle `/tmp/lm-interaction-serial-tests.xcresult`. The entire unrelated LM suite was not run.

The new tests call the same production completion adapter as `SpatialTapGesture.onEnded`, resolving actual imported key identities (including a descendant), then dispatching into the production FIFO. They cover VERB/NOUN/digits/ENTR, adjacent 7/8, impostor rejection and repeated PRO. A separate adapter test uses the real session and bundled Luminary image to show V16N36E followed by PRO returning V06N64. These are synthetic adapter invocations, not OS gesture recognition or physical pinch acceptance. The ten retained integration tests include active-PRO cancellation/release, pending-event teardown and FIFO regression cases.

[First test result](tests-first.json) records the discovered cosmetic-name lookup failure (11 pass, 1 fail). The corrected material traversal tolerates the importer's duplicate cosmetic transform/mesh names while preserving strict semantic ball/fixed/key identity checks. Invalid first-after images were quarantined locally and are not included as acceptance evidence. Final tests use `-parallel-testing-enabled NO` after concurrent visionOS clones disrupted both workers' simulator sessions.

## Headset gate

The physical Vision Pro was listed unavailable, so no device interaction or security/account changes were attempted. Use the [short headset checklist](HeadsetChecklist.md). Stereo, ergonomic reach, actual gaze/pinch, photometry, mechanical fit and frame time remain unqualified.

## Native input attempt — not accepted

Observation-only process **1532**, with scripted input flag absent, produced **164 samples and zero `completedSpatialTaps`**. See [trace](native/observation.jsonl), [adjacent final state](native/04-native-attempt-state.json), [native screenshot](native/04-native-attempt.png), [Simulator pointer-capture screenshot](native/pointer-capture-attempt.jpg) and [runtime log](native/runtime.log). All rows retain `inputKind: observation-only`. No production `Physical DSKY key` completion was logged.

The native Simulator was in “Select to interact with visionOS content” mode. Through the computer-use tool, clicks targeted the visible VERB area near `(625, 446)` in the 1295×768 app screenshot. Attempts were made with pointer capture disabled, then enabled (the first captured click entered pointer/keyboard capture and another click followed). None produced an accepted callback. This does not establish that the intended key received a real OS pinch; it establishes that this available automation route did not prove completion. The baseline's earlier click near `(616, 442)` also had no key log. AXe's `describe-ui` failed with “No translation object returned for simulator”; repeated unsupported attempts were stopped.

Consequently the full physical VERB/NOUN/numbers/ENTR sequence, adjacent-key selection and PRO release/cancellation remain unverified through OS gestures. Synthetic production-adapter and FIFO tests cover those software boundaries separately. Hardware was unavailable. This is a bounded tool limitation report, not a claim that visionOS Simulator generally cannot support clicks/pinches.

The observation-mode capture script required a macOS Bash 3 empty-array expansion correction. That script-only patch explains the native manifest's nonempty tracked patch hash; the app binary remains the tested `f1f612e` source. Native camera pose readback is unavailable; metadata wording in the app trace describing a reset is the harness convention, not a measured Simulator camera transform. Exact applied scene observer transform is recorded above.
