# Terrain morph Metal compatibility repair

The owner's Simulator screenshot showed `MTLValidateFeatureSupport` aborting
at `LMLunarTerrainMorphRenderer.submit` during a non-Apollo zoom transition.
The unchanged main input is `07a77422505d23ff42fe16ba8e97417579001084`.
Evidence is under `/tmp/LM-Metal-Dispatch-2026-09-09/`.

## Reproduction and repair

Running the existing GPU arrival test with `TEST_RUNNER_MTL_DEBUG_LAYER=1`
reproduced the exact nonuniform-threadgroup assertion on unchanged main
(`Control.xcresult`, `control.log`). The log confirms Metal API Validation
Enabled. The prior passing integration suite did not enable this validation;
the Apollo journey did not exercise this global terrain morph.

Both vertex and appearance compute passes now dispatch rounded-up, uniform
threadgroups. Existing kernel bounds guards handle padded threads. Vertex
math, contact sampling, source data and tile ordering are unchanged.
Apple documents the capability restriction for
[dispatchThreads](https://developer.apple.com/documentation/metal/mtlcomputecommandencoder/dispatchthreads(_:threadsperthreadgroup:))
and bounds checking for
[uniform dispatch](https://developer.apple.com/documentation/metal/mtlcomputecommandencoder/dispatchthreadgroups(_:threadsperthreadgroup:)).

The first repaired run then exposed a second API error: compute writes to
`rgba8Unorm_sRGB` are rejected by this Simulator. This intermediate attempt
failed and is preserved (`Candidate.xcresult`, `candidate.log`). The final
repair writes through an `rgba8Unorm` view of the same output allocation and
explicitly applies the sRGB transfer function after linear-light blending.
RealityKit still reads the sRGB texture, and mip generation still uses the
sRGB texture. No extra full-size texture or pixel buffer is introduced.
Normal-map blending and geometry kernels are unchanged; only color output
encoding moves from implicit format conversion to explicit shader conversion.

## Regression validation

Xcode 26.6, visionOS 26.5 Simulator
`8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`, serial execution:

- **16 tests in 2 suites pass** with Metal API validation enabled (4.355 s),
  including terrain arrival, lifecycle cancellation/re-anchoring and transition
  collars (`Candidate-PortableColor.xcresult`, `candidate-portable-color.log`).
- The GPU test runs with 8-by-8 and 9-by-9 textures. Both final edge columns
  and rows are checked at weights 0, 0.25, 0.5 and 1, retaining the existing
  0.6-byte output tolerance. The initial texture is checked before replacement.
  GPU vertices still match the contact surface at every checked vertex/weight.
- The ordinary Release Moon build passes (`moon-build.log`). Executable SHA-256:
  `043aaa118386506c4a300b8c1373881a84cb9874a88113e7927feeb1114aeb85`.
- The highland dive at -42 degrees, 120 degrees runs with
  `SIMCTL_CHILD_MTL_DEBUG_LAYER=1`; the actual process environment is checked
  in `runtime-validation-environment.json`. The log records `Global morph
  complete`, with 16 regional tiles ready at 8 m spacing in 6.045 s for the
  final regional request. This is a single functional observation, not a
  matched performance improvement.


The full five-stage highland capture completes (`Highland/completion.txt`
contains `passed`). `Highland/highland-regional.png` was inspected: the portal
is filled with shaded ridges/depressions, with no missing tile at the captured
stop; the source-limited terrain remains visibly soft. This is crash/functional
acceptance, not an appearance upgrade.

The script's built-in settled observation also finishes without an assertion,
but **does not pass the performance settle gate**: the last 18 five-second
windows include a 19.00 ms mean / 118.74 ms p99 / 278.58 ms max window and a
37.90 ms callback in the following window, with nine missed callbacks total.
The remaining windows are 16.67 ms with zero misses. No cause is inferred from
this single run with validation enabled. `settled-experience.json` records the
failure; the initial `settled.json` query used the wrong default preset and
returned no windows, so it provides no timing evidence. This crash repair does
not claim to close the previously deferred performance qualification.

No full Apollo ladder, matched performance triplicates, physical-device run,
or guidance changes were made. AGC/LMKit and pinned terrain resources are
unchanged. Existing dirty user schemes/editor metadata remain untouched.
Future GPU regression runs must explicitly enable Metal validation:

```sh
TEST_RUNNER_MTL_DEBUG_LAYER=1 xcodebuild test \
  -scheme LunarMap-Package -configuration Release ENABLE_TESTABILITY=YES \
  -destination 'platform=visionOS Simulator,id=8F38C0E7-6366-4DAC-9372-DCF6F9151DCB' \
  -parallel-testing-enabled NO \
  -only-testing:LunarMapTests/LMLunarTerrainArrivalTests \
  -only-testing:LunarMapTests/LMLunarTerrainTransitionTests
```

Run from `Packages/LunarMap` with Xcode 26.6 selected. The app capture uses
`SIMCTL_CHILD_MTL_DEBUG_LAYER=1` with `LUNAR_HIGHLAND_DIVE=1` and
`LUNAR_BUNDLE_ID=io.positron.Moon`.
