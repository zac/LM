# Main-branch integration: LM, LunarMap, LMKit and AGC

## Scope and ownership

The owner authorized direct commits and pushes to main, without pull requests,
on 2026-09-09. This combines the cockpit work at `9a297b8` with LunarMap/Moon
at `cc42b92`, preserving both histories. LMKit owns models/resources, AGC and
LMCore own simulation, LunarMap owns terrain and Explorer, and LM owns cockpit
presentation, input and session binding. LunarMap remains inside the LM repo.

The isolated integration checkout is based on clean committed dependencies:

| Repository | Validated input |
|---|---|
| LM terrain/package | `cc42b92e45aabc25513b05a6cac42f0d04a8c147` |
| LM cockpit | `9a297b8` |
| LMKit main | `5287dfd` |
| AGC main | `b3f15533db335ee882dc07401790c93010809e8f` |

Both dependency revisions were fetched from origin/main. The canonical AGC
checkout's uncommitted pad-load constants are excluded from validation and
preserved in place. Existing Xcode user schemes, editor metadata, and the
cockpit owner's worktree remain untouched. The existing shared LM scheme is
included in the integration so builds and tests do not require user schemes.

## Integration intent

The Xcode project retains LM, Moon, LunarMap, LunarMapExplorer and LMKit.
Moon has no direct LMKit or cockpit dependency. Cockpit changes retain the
live two-minute P64 checkpoint, terrain-readiness gate, fixed prepared Apollo
near-field contact grid and 2 m terrain, imported instruments, and current
lighting/material choices. Explorer retains progressive terrain behavior.
No simulation algorithm, asset bytes or landing outcome is replaced here.

The package-boundary fixes required by the compiler and the actual build,
test and runtime evidence are recorded below when completed. No blanket
choice of one branch's files is used for terrain or cockpit source.

## Qualification boundary

This is a bounded integration validation: clean dependency tests, both Release
apps, package/cockpit tests, one automated Apollo landing, and Moon launch/zoom
smoke inspection. It does not repeat the one-zoom triplicate performance sets
or restore soaks. The previous package soak peak failure, incomplete highland
measurements, eleven-stop LM/Moon capture parity and physical Vision Pro
acceptance remain recorded in `LunarMapPackage.md`. D stays parked on
`onezoom/D`; F remains unimplemented on `onezoom/F`.

Evidence root: `/tmp/LM-Main-Integration-2026-09-09/`.


## Dependency checks

AGC clean main: all **255 tests in 17 suites pass in Release**, 46.658 seconds
of test execution (`agc-release-tests.log`). The initial unoptimized full-suite
run was interrupted after roughly eleven minutes while full-flight cases were
still running; its partial results are not used as a pass/fail decision
(`agc-tests.log`, `agc-debug-incomplete.json`). The complete Release run includes
those trajectory and checkpoint cases. AGC's cancelled Linux main check was
rerun separately; its conclusion is recorded in the final checkpoint below.

All 22 LunarMap terrain/model resources match `cc42b92` byte-for-byte;
`terrain-resource-audit.json` records their current SHA-256 values.


LMKit clean main: all **13 Release test functions pass**, including the
parameterized packaged-resource equality and native RealityKit load cases
(17 cases each), with 3.518 seconds of test execution. Evidence:
`lmkit-release-tests.log`. No LMKit source or shipping resources were changed.


## Compiler-driven package interfaces

The first combined build identified inaccessible manifest loading, lighting
helpers and rendered near-field/contact construction. The resolved boundary:

- Public manifest loading and read-only sun elevation; public shared sun
  construction/orientation/reference elevation, with their arithmetic unchanged.
- `Assembly.renderedNearFieldPositions` exposes the existing row-major positions
  without exporting internal mesh-builder types or generating another mesh.
- `LMTerrainContactSurfaceBuilder.buildPreparedApollo` owns the exact construction
  formerly in the cockpit. The extent, spacing, dimensions, Float datum
  subtraction, fallback field/alignment and triangle interpolation are unchanged.
  The cockpit still performs this preparation off the main actor.

The combined LM ordinary Release build passes (`lm-build-interfaces.log`).
All **232 LunarMap tests in 26 suites pass**, including the added prepared-contact
regression, in 18.168 seconds (`PackageTests.xcresult`, `package-tests.log`).
That test deliberately uses different source and rendered heights and a
non-planar quad, checking all corners, both triangle interiors, the diagonal,
Eagle datum subtraction and the out-of-grid fallback.

Builds use the Xcode skill's wrapper. Simulator tests use direct xcodebuild
because the wrapper's test path does not carry Release configuration, testability
and serial-run flags; explicit `-configuration Release ENABLE_TESTABILITY=YES
-parallel-testing-enabled NO` preserves the intended check. Only the designated
visionOS 26.5 Simulator was booted, with no XCTest clones.


### Cockpit test configuration

The first host-test attempt used Release and could not compile the incoming
cockpit tests: they reference `LMCommanderStationAssemblyObserver` and
`LMCockpitPresentationPolicy.validation`, which are intentionally `#if DEBUG`.
Those test bodies and runtime guards are preserved. The host suite therefore
runs in its authored **Debug** configuration; ordinary Release app builds and
runtime checks are separate. This is a configuration limitation, not a passing
Release-test result (`HostTests.xcresult`, `host-tests.log`).

`LMCockpitStartupLightingTests` additionally required `@testable import
LunarMap` and `LunarMapExplorer` after extraction. Its assertions are unchanged.
The historical contact validation script now reads the production sampler's
package path; its assertions and interface stubs are unchanged.


The initial Debug host attempt compiled, then blocked in the Simulator's
app-install service before launching tests. A one-second runner sample shows
`dvt_installApplicationAtPath` waiting in the CoreSimulator bridge install
request. That attempt was interrupted and marked **incomplete**, with no
assertion outcome inferred (`host-debug-incomplete.json`,
`host-test-runner.sample.txt`, `HostTests-Debug.xcresult`). The designated
Simulator was restarted without erasing data; the compiled test bundle was
retried with `test-without-building`. No other Simulator or physical device
was restarted.


AGC Linux CI **passes** for the exact clean main revision `b3f1553`:
[Tests run 34261541819](https://github.com/zac/AGC/actions/runs/34261541819).
The rerun used the existing workflow without changing AGC code or CI policy;
`agc-ci.json` records the completed successful job.


The Debug host retry completed: **170 pass, one exempt P64 failure**, 171 tests
in 34 suites, 211.960 seconds (`HostTests-Retry.xcresult`,
`host-tests-retry.log`, `host-tests-summary.json`). The startup/prepared-sun
consistency test passes. `bundledP65CheckpointLandsOnTheDrawnTerrain` passes
in 40.303 seconds. Combined with LunarMap, the integration has 402 passing
tests plus the pre-existing P64 redesignation case; no test body was weakened.
The P64 case is checked separately against unchanged cockpit input `9a297b8`
using the same clean dependency commits before accepting the exemption.


The single P64 control run on unchanged cockpit `9a297b8` fails with the same
summary diagnostic and all five evaluated conditions as the integrated host
suite (`P64-Control.xcresult`, `p64-control-summary.json`, `p64-comparison.json`).
The large unrelated checkpoint dump is normalized out of the trap31A diagnostic;
the evaluated Boolean is compared. The existing exemption remains, handed to
the cockpit/guidance owner. Neither that test nor AGC was altered to pass it.

The existing standalone production contact-sampler check also passes all eight
corners/interior/diagonal/fallback assertions after its path update
(`contact-interpolation.log`).
