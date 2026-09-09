# Combined ACA and commander panel verification

Exact source: LM `7c1b4a751570cd8cdec35acac5c6fe976d53dfdf`, tree `24961ad4cf8be1232de6a81d776130b8ec75c894`. Dependencies: LMKit `86aa71b4b9ed203f11e8b572e23da2b0285a0ad8`, AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`.

All three are isolated hydrated archives under `/tmp/lm-aca-panels-verification/{LM,LMKit,AGC}`. Every archived file was hashed and compared with the exact commit (460 LM files, 262 LMKit files, 88 AGC files); `source-files.json` records the complete inventory. `manifest.json` records revisions, Git tree IDs, archive hashes and package resource hashes. No app, test, dependency or coordinator source edits were made. The worker delivery branch remains unchanged at `862714e3479947d70c333fff83aa03e6375f492b`.

## Native test selection

Dedicated simulator `6EB2B257-9EFE-4CEB-A64A-5EF0086FFF85` (LM-ACA-Validation), visionOS 26.5 (23O470), arm64; Xcode 26.6.0. Corrected skill runner `/tmp/lm-aca-xcodebuild.ts`, `-parallel-testing-enabled NO`, explicit `-only-testing:<selector>`. Native build/test artifacts are under `/tmp/lm-aca-panels-verification/build`; actual result bundle `/tmp/lm-aca-panels-verification/combined.xcresult`. `test.log` contains invocation and build/test output. Results must be read from xcresulttool, not inferred from wrapper exit status.

Selected suites: LMImportedACATests (4), LMCommanderStationAssemblyTests (5, including new panel test), LMInstrumentIntegrationTests (10), LMInstrumentInteractionTests (2), ACAInputMappingTests (6), SpatialCockpitControlTests (4). Expected discovery: 31. Full unrelated suite not selected. Existing tests cover real resource load, panel interfaces, identity retention, input/FIFO path, ACA signs/limits, release and stale-generation rejection. Synthetic dispatch does not establish OS gesture acceptance.

## Panel/ACA interference measurement

`check-panel-aca.swift` independently loads the exact packaged CommanderPanels and ACA resources with macOS RealityKit. It compares every panel mesh's Cabin-relative AABB against the whole ACA visual bounds at 729 combinations of pitch/yaw/roll, from -11 to +11 degrees in 2.75-degree increments, using the unchanged ACA Cabin registration `(-.49,.9075,-.37)` m.

All 40 panel meshes remain disjoint from the ACA AABB at every sampled pose. Minimum conservative AABB gap is **0.222634494 m**, nearest `Panel_4_Backing_Left`. Exact report: `panel-aca-clearance.json`. This is not continuous swept-volume, hand clearance or all-cabin collision proof. The asset's rigid grip/boot joint remains provisional. No fitting adjustment, scaling or model repair was performed.

Reproduce with native macOS RealityKit:

```sh
xcrun swiftc -parse-as-library -module-cache-path /tmp/lm-aca-swift-cache check-panel-aca.swift -o /tmp/check-panel-aca
/tmp/check-panel-aca /tmp/lm-aca-panels-verification/LMKit/Sources/LMKit/Resources
```

## Capture method

`capture.sh` launches the exact built app with `--terminal-descent-cockpit --commander-station-assembly`, then takes front, side and calibrated crew-eye images using the source's unchanged assembly observer. Cabin camera eye/target: front `(-.15,1.60,.48)` / `(-.15,1.30,-.55)`; side `(-.78,1.57,.30)` / same target; calibrated crew-eye `(-.5588,1.78,-.38)` / `(-.15,1.43,-.65)`.

The ACA neutral/positive/negative images use `--aca-visual-review=<pose>` with eye `(-.70,1.27,.10)` and target `(-.49,1.04,-.37)`. Positive and negative request combined normalized ±1 visual poses only. These flags never send simulation input. Live instrument digits are observations separate from visual deflection. No physical pinch, headset execution, stereo fit, egress or ergonomic acceptance is claimed.

Launch PIDs, UTC times, PNG hashes, binary hashes and runtime logs accompany the captures. Review findings and final counts follow below.

## Test acceptance

**31 discovered, 31 passed, 0 failed, 0 skipped**, confirmed with xcresulttool; `tests.json` and `discovery.json` are the actual bundle exports. The new `installsPanelSurroundsOnceAndRejectsMismatchedInterfaces()` test passed. No test or build failure occurred in this combined run. All 810 source/dependency files remained unchanged after testing. Seven key built cockpit resources (panels, panel manifest, ACA, ACA interface, DSKY, FDAI and Cabin) matched their pinned source bytes exactly; full built package resource hashes are in `bundled-resources.json`.

## Visual review

Front and side show both complete instrument faces inside the new surrounds, with no blank panel backing covering display or key geometry. The DSKY's lit program/register digits remain visible; the FDAI face and scale lines remain visible but dark, with strong rim reflections. The front view shows a visible border around each opening. Side view shows layered panel/edge depth and preserved instrument projection. These images do not measure a 3 mm mechanical gap or validate a mating flange.

The calibrated crew-eye view retains both complete instrument faces. The DSKY is still markedly oblique below/right; readable lit digits in a screenshot do not establish comfortable reach, stereo readability or reliable key selection. The narrowed outboard Panel 1 border leaves the existing window/LPD structures visible. The panel-to-window/frame join remains an open structural boundary; no closed cabin, seating hardware or insertion clearance is established. Existing dark materials, reflective FDAI rim and incomplete surrounding shell remain visible. No new panel-induced face occlusion is apparent in these three views.

ACA neutral and combined ±1 visual poses remain visibly separate from Panel 4 and DSKY, consistent with the sampled native separation measurement. The fixed ACA housing and pedestal do not move across the three images. The negative pose retains the previously documented rigid grip/boot misalignment; panels introduce no visible new interference. DES RATE and the mission button remain separate. This is a visual review, not a physical reach or controller-actuation test.

| Image | PID | UTC |
|---|---:|---|
| [front](front.png) | 20404 | 2026-09-08T20:39:26Z |
| [side](side.png) | 20457 | 2026-09-08T20:39:39Z |
| [crew-eye](crew-eye.png) | 20534 | 2026-09-08T20:39:52Z |
| [aca-neutral](aca-neutral.png) | 20573 | 2026-09-08T20:40:04Z |
| [aca-positive](aca-positive.png) | 20605 | 2026-09-08T20:40:17Z |
| [aca-negative](aca-negative.png) | 20639 | 2026-09-08T20:40:30Z |

All six capture PIDs logged successful skeleton installation and live P64 DSKY state. Earlier deliberately injected fallback messages in runtime.log belong to tests. Executable/dylib hashes are in app-binary-sha256.txt. The simulator was verified Shutdown after all six captures, and the exclusive slot is released. No new verification blocker was found within this scope; mechanical mounting, grip/boot kinematics, lighting/readability, continuous clearance, hand reach and real Vision Pro gaze/pinch remain acceptance gates.
