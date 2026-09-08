# ACA native validation

Pinned LMKit `3ad1a999ff17aea859eaea5750f1c65e66fad673`; AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`. See `../../ACAIntegrationHandoff.md` for registration, mapping, ownership and TTCA audit.

Dedicated simulator: `6EB2B257-9EFE-4CEB-A64A-5EF0086FFF85`, LM-ACA-Validation, visionOS 26.5 (23O470), arm64. No parallel XCTest runs. Xcode 26.6.0. The temporary runner `/tmp/lm-aca-xcodebuild.ts` derives from the skill runner with `-only-testing:<selector>` corrected and `-parallel-testing-enabled NO`; no shared skills were edited.

First native build passed. The first simulator run discovered 30 tests: 29 passed, 1 failed. Its failed assertion caught a zero quaternion from `simd_quatf()` assigned to the ACA container during installation. Replaced with explicit identity axis-angle. The runner exited zero despite the test failure; authoritative counts come from xcresulttool, not the wrapper exit status. `first-tests.json` retains the failure. A follow-up already running before this correction is also retained separately; it is not acceptance evidence.

Initial sandboxed build could not access simulator/caches; native measurement also required normal RealityKit process access. Retried with approved tool escalation. The first simulator creation used the legacy device type incompatible with this runtime; the compatible Apple-Vision-Pro-4K type created the dedicated device successfully. These setup failures do not count as test passes.

## Reproduction

Run the xcodebuild skill runner with scheme LM, dedicated destination, isolated DerivedData and packages, parallel testing disabled, and selectors:

- `LMTests/LMImportedACATests` (4)
- `LMTests/LMCommanderStationAssemblyTests` (4)
- `LMTests/LMInstrumentIntegrationTests` (10)
- `LMTests/LMInstrumentInteractionTests` (2)
- `LMTests/ACAInputMappingTests` (6)
- `LMTests/SpatialCockpitControlTests` (4)

Native sampled-envelope reproduction:

```sh
xcrun swiftc -parse-as-library -module-cache-path /tmp/lm-aca-swift-cache Docs/Validation/ACA/measure-envelope.swift -o /tmp/lm-aca-envelope
/tmp/lm-aca-envelope /tmp/lm-aca-deps/LMKit/Sources/LMKit/Resources/HandControllers/ACA.usdz
```

After tests, boot the same dedicated simulator, then run `bash Docs/Validation/ACA/capture.sh <UDID> <LM.app> <output-dir>`. The DEBUG `--aca-visual-review=neutral|positive|negative` harness sets only rendered pivots; it never injects a simulation command. Camera cabin eye is `(-.70,1.27,.10)`, target `(-.49,1.04,-.37)`, unchanged across captures. The optional commander assembly is enabled. These are monoscopic observer images, not a calibrated headset-eye or physical pinch test. Programmatic session generation/count tests are separate evidence.

Final test/capture source and results follow in the acceptance record.
