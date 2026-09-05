# Arbitrary-site cockpit integration

Work in progress under `LandAnywhereMoonPlan.md` Stage 2 item 5. Local gear
drops and retargeted spherical descents do not establish cockpit acceptance.

## Prerequisites and corrections

- AGC `4a1aeb4` records the existing gear integration without changing its
  contents. The three gear-related files were exported over AGC `0bf8f29`,
  excluding the unrelated panel edits, and all 14 gear tests passed.
  Evidence: `/tmp/LM-Cockpit-Integration/gear-prerequisite.log`.
- AGC `aa6ae3a` fixes premature reference-sphere touchdown when terrain is
  installed below that datum. A regression with terrain at -20 m reproduced
  a false soft landing at zero altitude; the fixed vehicle remains airborne
  while crossing zero. All 15 contact/gear tests pass. Evidence:
  `/tmp/LM-Cockpit-Integration/datum-before.log` and `datum-after.log`.
- LM `438fd0d` serializes full physics steps with terrain publication. A
  cockpit morph holds that boundary through GPU completion and publication
  of its immutable contact snapshot. The session stages contact synchronously
  instead of launching an unawaited setter task. Two gate tests and eight
  existing arrival tests pass in `/tmp/LM-Cockpit-Publication-Tests.xcresult`.
  This bundle is Debug: the bundled runner omitted its requested Release
  configuration from the actual test command.

## Mission path under validation

The selected coordinate resolves one immutable source region. Its measured
anchor height defines both the AGC radial datum and the rendering frame.
Custom missions start at P63 and cannot reuse Apollo P64/P65 checkpoints or
recordings. Replay recordings retain their scenario ID and site. Terrain
publication and flight steps share one gate; late contact callbacks from an
earlier site are rejected by a mission binding identifier.

The cockpit uses the production global terrain presentation, including its
appearance and geometry arrivals. Near touchdown it waits for requested
terrain to finish. This can lengthen wall-clock descent time and is an open
performance concern, not real-time flight acceptance. The floating source
frame changes at the existing 4,096 m threshold. Geometry and the inverse
vehicle view use the same frame change, including sunlight and dust.

Five context/publication tests passed in Release with `ENABLE_TESTABILITY=YES`:
`/tmp/LM-Cockpit-Mission-Testable-Tests.xcresult`. Without that flag, the existing
`@testable import LM` target cannot import the ordinary Release module.
Captures use a subsequent normal Release build, without that test override.

## Rejected first capture

`/tmp/LM-Cockpit-Mare-v1` reached P64 below 250 m. Sampled footpad contact
heights matched the submitted mesh snapshot, but the custom terrain inherited
an Apollo transform on its parent, applying the vehicle movement twice. The
cockpit images therefore fail visual acceptance. The run was stopped during
approach and is not a completed terrain landing.

The correction clears the parent transform before attaching the custom
controller. Dust is moved into the same floating frame. Approach requests also
finish one bounded generation before requesting the latest pose: repeatedly
cancelling requests as the vehicle crossed tile boundaries wasted generation
work. These changes require a fresh capture.

## Mare mission evidence, 2026-09-05

Normal Release binary SHA-256:
`b35113f9db653edb7e6c1bc62354b87a400d889e9042c180332abfd4625b469a`.
Build log: `/tmp/LM-Cockpit-Integration/release-v2-build.log`.
The parent-transform regression passes in
`/tmp/LM-Cockpit-Transform-Tests.xcresult` (three Debug test methods).

`/tmp/LM-Cockpit-Mare-v2` completes P63 → P64 → P65 and an intact hard
landing at simulation time 814.720850 s. First contact is at 812.888704 s.
The first-contact speeds are 0.900104 m/s vertical and 0.244749 m/s horizontal;
3.2335° tilt exceeds the existing 2° soft-landing limit but stays within the
6° intact-landing envelope. All four pads settle with no gear failure; the
forward strut strokes 48.5 mm. The classification thresholds are unchanged.

The 13,463-frame recording retains the selected site in every frame. All
51,300 sampled footpad heights agree exactly with the published mesh snapshot,
across 152 floating-origin changes. The source spacing is 236.901175 m.
Screenshots show the surface through the commander window below 250 m and
through touchdown. These discrete images do not establish continuous stereo
or headset acceptance. The high approach lacks a distant global surface.

The run contains 65 terrain generations, with a maximum of 30,365 ms. Frame
windows peak at 496.0 MiB; phase samples reach 598.55 MiB and the process peak
counter reaches 707.25 MiB. The worst frame is 753.51 ms. These figures include
capture-only recording serialization at touchdown and substantial waits for
terrain below 250 m; they are not evidence of uninterrupted real-time flight.
`metrics.json` and `mission-summary.json` retain the detailed measurements.

All 11 protected Apollo terrain assets are byte-identical to `c950d46` in
`/tmp/LM-Cockpit-Integration/apollo-assets.json`. The separate AGC checkout's
uncommitted panel constants remain untouched; the captures include that
working tree. Those additions declare unused constants and do not alter the
executed guidance path.

## Highland mission evidence, 2026-09-05

`/tmp/LM-Cockpit-Highland-v2` uses the same binary and completes P63 → P64 →
P65, but crashes at first contact at 843.989451 s. Its 16.1392° surface-relative
tilt exceeds the unchanged 6° contact envelope; the recorded failure is
`contactEnvelopeExceeded`. Speeds are 0.865609 m/s vertical and 0.268848 m/s
horizontal. Contact occurs at radial altitude -16.7129 m, demonstrating that
the reference sphere no longer stops the vehicle above the displayed terrain.
This is a valid failure-path capture, not a successful highland landing.

All 15,106 frames retain the highland site. There are 65,200 matching footpad
samples and 152 re-anchors. The 62 generations reach 34,420 ms; frame-window
memory peaks at 422.4 MiB, phase samples at 591.44 MiB and the process peak
counter at 658.82 MiB. Worst frame: 820.26 ms. The same terrain-wait and
capture-serialization qualifications apply. The selected ephemeris date is
1969-07-20 20:17:40 UTC for both regions. The images expose distant faceting;
they do not close the existing distant-join or radiance acceptance gates.

The landing radar uses the selected site's spherical geometry and basis. This
work does not implement radar ray intersections with procedural relief or
automatic hazard avoidance. An intact highland landing remains unproven.

Both recordings pass the actual LMCore Codable round trip and 1,001 replay
interpolation samples each, including exact terminal-state preservation.
Evidence: `/tmp/LM-Cockpit-Integration/replay-check.log` and the standalone
`ReplayCheck` package beside it. This checks replay data; it does not claim
interactive coverage of every Explorer-to-cockpit or replay control.

## Capture protocol

`Tools/CaptureLunarCockpitMission.sh` launches the actual cockpit with a
coordinate, saves AGC-labelled screenshots at P63/P64 and below 250/60/10 m,
and retains the terminal recording, contact metrics, binary hash and frame/
memory logs. The two coordinates are 8.35°, 30.83° and -42°, 120°.

Physical Vision Pro remains necessary for stereo continuity, headset gesture
comfort, 90 Hz pacing, GPU memory pressure and thermals.
