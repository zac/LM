# LunarMap package extraction report

## Acceptance baseline — 2026-09-08

The package baseline is the post-B runtime at `ba0b87e` on
`terrain-realism-and-explorer`. B landed after the owner corrected the
outside-texture callback margin and settled upper bound. Its Release build
reproduces the previously qualified executable exactly:
`2d669f868a6c05b05636f8acea23a63bf5d871b906da0bcda6810f18bc26a874`.
B's 78 focused tests pass. Parked D is rebased at
`7283b992ffdaf2ecaff4603ba95acedce5a50caa`, builds Release and passes 97 tests;
F remains an unimplemented parked reference at `ba0b87e`.

Evidence: `/tmp/LM-LunarMap-2026-09-08/B/`, `D/`, and `Baseline/`.
The frozen app is `Baseline/Control.app`. All builds, tests and captures use
serial Xcode 26.6 Release execution on the visionOS 26.5 Simulator
`8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`.

The initial journey includes the seven standard stages and the two switch
probes. Its inspected `disk.png` shows the Moon directly in the room.
`switch-before.png` and `switch-after.png` have no exposed black rectangle
or apparent size jump. `terrain.png` at 7.5 km retains the low-contrast mare,
with distinct light and shade on crater edges. This is Simulator inspection;
stereo continuity, tracked input and comfort still require Vision Pro.

| Single baseline journey metric | Value |
|---|---:|
| Frame-window footprint range | 111.9–318.7 MiB |
| Lifetime peak | 615.143 MiB |
| Maximum window mean | 19.41 ms |
| Maximum window p99 | 117.64 ms |
| Largest callback, all intervals | 430.88 ms |
| Largest callback, outside texture | 187.354 ms |
| Hitches over 25 ms | 21 |
| Globe texture interval | 396.750 ms |
| Texture-before physical / kernel peak | 118.315 / 120.877 MiB |
| Texture-after physical / kernel peak | 106.034 / 232.659 MiB |

This single run is an acceptance reference, not a three-run performance
decision. Each package candidate requires the alternating sets specified in
`MoonExplorerOneZoom.md`. Only peak, hitch count, outside-texture callback,
settled upper bounds and Apollo image identity gate landing; the other
columns remain reported.

The eleven baseline Apollo PNGs are byte-identical. All twelve final
settled windows report 16.67 ms mean/p99/max with zero missed callbacks
after the 90-second hold. All 11 pinned-resource checks and five protected
bodies pass. The soak and highland workloads are complete. No package candidate is
qualified yet.

## Inventory and extraction preflight

`LunarMapPackagePlan.md` §1 now records the post-B inventory. There are
13 ProcessInfo-reading files under `LM/`, 15 log-subsystem literals including
the root cockpit file, and **25** Swift test files, rather than the expected
24. Eight argument-reading files and 12 log literals belong to the package.
Pinned terrain resources total 177,473,236 bytes (169.25 MiB).
`inventory-raw.json` and `resource-inventory.json` retain the exact inventory.

The package location requires the LMCore dependency path `../../../AGC`.
The root cockpit file remains referenced by the LM target; only the moved
simulation-gate reference leaves that target. This run made no AGC source changes. The checkout has an existing local
`LMAGCPadLoad.swift` modification; its observed hash is retained in the evidence.

Caches remain in each app's own container under `Library/Caches`:
`LunarImagery-wac64-r8-box-pyramid-v1/tiles/<sha256>.r8`,
`LunarImagery-wac64-r8-box-pyramid-v1/slabs/`, and `LunarElevation-v1/`.
Moving code into a package does not change their ownership or paths.

The source audit and compiler exposed a build-order inconsistency in the
written plan: `LunarExplorerView` itself consumes `MainMenuViewModel`, in
addition to the controls-window wrapper. Both must be separated for the
step-1 inventory move to compile. The earlier clarification question proved
unnecessary after tracing that dependency: the root view only obtains the
existing session. Step 1 therefore brings forward the already-planned
mechanical wrapper split and passes that exact session explicitly. Wrapper
callbacks and launch behavior are preserved; launch options and HostActions
remain in step 2. This is a documented implementation-order correction,
not a new owner decision or a behavior change.

The compiler confirmed two target-ownership corrections in `Step1/build-01.log`:
`LMTerrainWorld` uses `LunarExplorerHeightFieldPicker`, and
`LMLunarTerrainPresentation` calls `LunarExplorerScene.finerOwners`.
The picker and unchanged overlap calculation now live in the engine,
avoiding an engine-to-Explorer dependency cycle. The helper retains its
exact body and MainActor isolation; `Step1/ownership-helper.json` records
the declaration-block hash. No calculation changed.

Physical-device gates remain open: stereo/crossfade perception, tracked
head/hand/gaze input, gesture comfort, CPU/GPU pacing, memory pressure,
thermals and immersive-space lifecycle. No package runtime change or Moon
app has been validated yet.

### Step 1 preparation (not yet qualified)

The manifest and inventory file moves are prepared with `git mv`. The LM
project now links both package products and retains the root cockpit source.
Resource defaults route to `LunarMap.resources`, the morph renderer uses the
package Metal bundle, and package logging routes through `LunarMapLog`.
The first package build confirmed the two ownership errors above. Its
resource build produced `LunarMap_LunarMap.bundle/LunarTerrainSR.mlmodelc`.
The next build is checking imports and access levels; the package is not
yet build-qualified.

### Completed baseline restore soak

The five-cycle restore soak completed. These are single-run reference
values, not a performance decision.

| Metric | Value |
|---|---:|
| Footprint min, MiB | 118.000 |
| Footprint max, MiB | 392.900 |
| Lifetime peak, MiB | 839.581 |
| Maximum window mean, ms | 19.190 |
| Maximum window p99, ms | 122.110 |
| Largest callback, ms | 407.240 |
| Outside-texture callback, ms | 288.670 |
| Hitches over 25 ms | 99.000 |

| Memory checkpoint | Physical, MiB | Lifetime peak, MiB |
|---|---:|---:|
| soak-1-surface | 347.221 | 839.581 |
| soak-1-returned | 348.581 | 839.581 |
| soak-2-surface | 347.221 | 839.581 |
| soak-2-returned | 348.628 | 839.581 |
| soak-3-surface | 347.253 | 839.581 |
| soak-3-returned | 348.721 | 839.581 |
| soak-4-surface | 347.518 | 839.581 |
| soak-4-returned | 348.565 | 839.581 |
| soak-5-surface | 347.425 | 839.581 |
| soak-5-returned | 348.534 | 839.581 |

### Completed baseline warm highland dive

The dive at −42°, 120° completed. Its disk capture shows the cratered
far side in the room. The regional and settled captures show the same
coarse, softly shaded terrain with the large crater in the upper-right
corner; the measured-floor label is 236.9 m. No black view is exposed.
The remaining journey images were inspected too: clipped imagery fills
the frame, the overlap retains crater rims and tonal variation, the 42.8 km
stop has shaded crater walls, immersion fills the background with terrain,
and return restores the framed surface.

| Metric | Value |
|---|---:|
| Footprint min, MiB | 117.800 |
| Footprint max, MiB | 220.800 |
| Lifetime peak, MiB | 262.596 |
| Maximum window mean, ms | 19.360 |
| Maximum window p99, ms | 101.390 |
| Largest callback, ms | 511.790 |
| Outside-texture callback, ms | 140.555 |
| Hitches over 25 ms | 27.000 |
| Texture interval, ms | 288.573 |

The cross-module compiler required an explicit Double tuple type and typed
logarithmic intermediate values in the capture-only transition probe. Its
values, arithmetic order, assignments and 33 ms waits remain unchanged.
Build logs retain the original type-checking timeout and each subsequent
access diagnostic. Both `default.metallib` and `LunarTerrainSR.mlmodelc` are
present in the compiled package resource bundle; runtime loading is still
an acceptance gate after the LM app links.

### Step 1 compiler checkpoint

The full LM Release build passes in `Step1/build-59.log`. Step 1 has not
landed and no package performance conclusion has been drawn. The temporary
access diagnostic was removed before the full app-hosted test run. It exposed
inaccessible members hidden by two large Swift expression timeouts, allowing
the original cockpit expressions to remain unchanged. Compiler logs and the exact diagnosed visibility edits are in
`Step1/build-*.log` and their adjacent JSON files. Public conformance and default
argument diagnostics required explicit versions of synthesized initializers
for the simulation gate, Explorer session and controls, planner level, and
terrain edge option set. Their existing defaults, assignments and raw bit
values are preserved.

The mechanical audit passes 54 checks, including the unchanged host wrapper
and overlap helper. All 23 moved resource and Metal files match their post-B
bytes; the 11 pinned resource hashes and five protected bodies also pass.
The audit permits only the documented extraction edits and checks the explicit
constructor bodies. Runtime tests, Apollo identity, Metal loading, and matched
performance remain outstanding for this candidate.

## Step 1 stopped at the full-test gate

Candidate branch: `lunar-map/step-1`, based on the post-B runtime plus
`ed4eab3`, the completed baseline documentation. It is not merged to
`terrain-realism-and-explorer`. Steps 2–4 have not started.

The final candidate builds in Release with testability enabled and passes
315 of 317 tests across 40 suites. Both remaining failures reproduce in a
detached, unchanged `ba0b87e` checkout using the same current AGC dependency.
The control ran the two affected suites: 12 passed, 2 failed, 14 total.
No test expectations, input timing or AGC behavior were changed.

| Test | Candidate observation | Post-B control observation |
|---|---|---|
| `globalPanHasFiniteSourceWindowAndApolloBoundsStayUnchanged` | Initial north offset 20,000 m; test expects 900 m | Same 20,000 m versus 900 m |
| `p64PROAndACAChangeLuminaryLandingTarget` | CH31 positive pitch/roll remain 1/16; trap31A remains true; monitor bits remain zero; landing target unchanged | Same five failed expectations |

This is a baseline test blocker, not evidence of an extraction regression.
It still fails the controlling plan's all-tests gate. The run stops here
under the owner's instruction to report rather than introduce a behavior
change to satisfy a test. Resuming requires resolving or explicitly exempting
these two baseline failures. The candidate is preserved for review.

Evidence:

- `Step1/Tests-01/` and `Tests-02/`: completed compiler diagnostics for the
  required testable imports.
- `Step1/Tests-03/`: completed first runtime suite, with missing resource-path
  failures and the two baseline failures.
- `Step1/Tests-04/Tests.xcresult` and `tests-summary.json`: final 315/317 result.
- `Step1/ControlTests/Tests.xcresult` and `tests-summary.json`: control 12/14 result.
- `Step1/ControlSource/LM/`: detached post-B control checkout. AGC is referenced
  through a symlink, not copied or modified.
- `Step1/resource-path-seam.json`: six flat catalog/elevation lookups now check
  the package's Terrain subdirectory, retaining the original root fallback.
- `Step1/mechanical-audit.json`, `host-source-audit.json`,
  `resource-move-audit.json`, and `Contracts/`: 54 mechanical checks, 12 host
  source checks, all 23 moved resource/Metal byte comparisons, all 11 pinned
  resources, and all five protected bodies pass.

The final testable Release executable is retained as
`Step1/Candidate-Testable.app`, SHA-256
`06a1046d6c77db3d7de1bd1cb8992d49615cadb13bc564eab42df63529f4084d`.
It is a test artifact, not a qualified performance binary. No ordinary
Release freeze or performance workload was started after the baseline
failures were confirmed. The last ordinary Release compile passed in
`build-59.log`, before completing the resource-path seam.

Package Metal loading is exercised by the passing terrain-arrival renderer
checks. The bundled Core ML seam-safe generation test passes, with its
expected albedo checksum `9fe4e0a8e870db42`; the compiled model and Metal
library are present in the package resource bundle. These tests do not
replace the capture and performance gates.

Outstanding for step 1: the all-tests gate, final ordinary Release executable,
eleven Apollo PNG comparisons and 90-second settle, alternating three-run
journey/soak/warm-highland measurements, and candidate image inspection.
There are no partial candidate measurement sets and no passing or failing
package performance conclusion. All physical-device gates listed above
remain open. No Moon executable exists yet.

The scheme-user files remain modified and excluded from commits. Their
observed order hints differ from the hashes recorded at run start. The agent
did not write those files. Automatic approval review rejected a proposed
restoration because it could overwrite files the owner asked to preserve;
the current contents were left untouched. Both observed and reconstructed
original bytes are retained under `Step1/UserFilePreservation/`, with the
hash comparison in `Step1/user-file-drift.json`.

## Step 1 resumed, then stopped by owner, 2026-09-08

Step 1 remains **unlanded** on `lunar-map/step-1`. Its runtime commit is
`3e94addd0b687c133d100c466166009a010335d8`, rebased from `88ce755` onto
`89ecb0fe641292640a56e37ddf72587c342a4066`. The latter is the only landed
change from this resumed run: `test(explorer): assert Apollo pan bounds from
the site pack`. It checks the real manifest/Eagle focus, the shifted bounds
with the 128 m collar, all four clamp edges, and the existing global 20 km
bounds. The documentation checkpoint follows the candidate runtime commit;
no package runtime changes are merged to `terrain-realism-and-explorer`.

Evidence root: `/tmp/LM-LunarMap-2026-09-08/Resume/`.
Ordinary Release candidate: `Step1/Candidate.app`, executable SHA-256
`160b382a8ac9abdac019b806483f3d5d2c16cbb6e442c72130f594408d2d9956`.
Frozen post-B control: `../Baseline/Control.app`, executable SHA-256
`2d669f868a6c05b05636f8acea23a63bf5d871b906da0bcda6810f18bc26a874`.
All measurements below are Simulator results, using Xcode 26.6 Release and
the pinned visionOS 26.5 Simulator. Builds, tests and captures ran serially.

### Completed gates and exemption

| Gate | Result | Evidence under Resume/ |
|---|---|---|
| Full baseline/candidate test outcome set | Identical: 316 pass, one exempt failure, all 317 identifiers | `ControlTests/Tests.xcresult`, `Step1Tests/Tests.xcresult`, `Step1Tests/outcome-comparison.json` |
| Ordinary Release build | Pass; executable frozen above | `Step1/build.log` |
| Eleven Apollo PNGs | All byte-identical to the pinned Release baseline | `Step1/Apollo/comparison.json` |
| Final 90-second Apollo hold | Twelve windows, 16.67 ms mean/p99/max, zero misses | `Step1/Apollo/settled.json` |
| Pinned resources / protected bodies | 11/11 resources, 5/5 bodies | `Step1/Contracts/`, `Step1/contracts.log` |
| Mechanical extraction audit | 54/54 source checks; prior 23 resource/Metal byte comparisons remain unchanged | `../Step1/` source/resource audits |
| Alternating journey triplicates | All named gates pass | `Step1/journey/comparison-v2.json` |
| Fresh alternating five-cycle soak triplicates | Peak-memory gate fails; hitch and callback gates pass | `Step1/soak-awake/comparison-v2.json` |
| Warm-highland comparison | Incomplete; no conclusion | `Step1/highland-warm/incomplete.json` |

The sole exempted test is
`PoweredDescentCheckpointSessionTests.p64PROAndACAChangeLuminaryLandingTarget`.
It fails unchanged on control and candidate. Both full-test summaries have
exactly the same failure record: positive-pitch CH31 bit is 1 where the test
expects 0, with held CH31 57777. `Step1Tests/exempt-failure-comparison.json`
records this equality. The failure is outside package scope and is handed
to the cockpit owner. No P64, cockpit/AGC test, PoweredDescentSession or AGC
repair was made.

The AGC checkout was identical for both test runs and at stop:

```text
$ git -C ../AGC rev-parse HEAD
166b5860f19ea5a4ced0b0d6d36b4e779d530935
$ git -C ../AGC status --short
 M Sources/LMCore/LMAGCPadLoad.swift
```

The existing modified file SHA-256 remains
`9a2a31a38b024e4f1bf92e34a499d146a16a1583ba33908f5db3f1b9a8b165c0`.
See `agc-state.json`. The two scheme-user files and RKC xcuserdata were
left untouched and excluded from the checkpoint commit.

### Inspected images

All nine images in `Step1/journey/Candidate-1/` were inspected against
control. Disk and switch-before/after show the free-standing Moon, Apollo
flag and glass label without exposed black background or apparent size
jump. Clipped fills the rounded frame. Crossfade retains crater rims with
contrasting lit and shadowed sides. The 42.8 km handoff remains low contrast
with small visible rims; the 7.5 km stop has clustered central pits and
softer surrounding terrain, matching control. Immersion fills the
background with the same terrain; return restores the framed view. The
immersion PNG is also byte-identical to Control-1's.

The original soak's `Candidate-1/immersive.png` and `restored.png` were
inspected beside `Control-1/restored.png` before the later host interruption.
The same crater field, heading, sunlight and 180 m altitude return. Both
builds show "Selected location" after restoring a saved coordinate. The
system-placed controls window differs in position between launches; the
terrain frame and crater positions remain fixed. These image observations
do not qualify the interrupted performance set. No highland image was
captured or inspected in the resumed run.

### journey alternating triplicates

| Run | Footprint min/max MiB | Lifetime peak MiB | Max mean ms | Max p99 ms | Raw callback ms | Outside-texture callback ms | Hitches >25 ms | Texture intervals ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Control-1 | 118.300 / 324.500 | 621.675 | 18.480 | 74.210 | 293.500 | 184.350 | 17 | 502.023 |
| Candidate-1 | 117.500 / 323.300 | 619.831 | 18.240 | 111.520 | 206.790 | 150.750 | 16 | 390.007 |
| Control-2 | 119.400 / 325.600 | 622.831 | 19.490 | 56.990 | 579.770 | 148.691 | 14 | 599.184 |
| Candidate-2 | 117.800 / 323.700 | 620.925 | 19.580 | 150.210 | 400.740 | 150.211 | 17 | 313.515 |
| Control-3 | 118.200 / 349.900 | 620.878 | 18.370 | 116.960 | 280.270 | 145.441 | 16 | 489.404 |
| Candidate-3 | 111.800 / 318.800 | 615.143 | 19.350 | 117.400 | 440.690 | 164.861 | 22 | 390.453 |

| Metric | Control min / median / max | Candidate min / median / max | Gate limit | Result |
|---|---:|---:|---:|---|
| footprint_min_mib | 118.200 / 118.300 / 119.400 | 111.800 / 117.500 / 117.800 | Reported only | Not gated |
| footprint_max_mib | 324.500 / 325.600 / 349.900 | 318.800 / 323.300 / 323.700 | Reported only | Not gated |
| lifetime_peak_mib | 620.878 / 621.675 / 622.831 | 615.143 / 619.831 / 620.925 | 646.675 | Pass |
| max_window_mean_ms | 18.370 / 18.480 / 19.490 | 18.240 / 19.350 / 19.580 | Reported only | Not gated |
| max_window_p99_ms | 56.990 / 74.210 / 116.960 | 111.520 / 117.400 / 150.210 | Reported only | Not gated |
| hitches_over_25ms | 14.000 / 16.000 / 17.000 | 16.000 / 17.000 / 22.000 | 18.400 | Pass |
| largest_callback_ms | 280.270 / 293.500 / 579.770 | 206.790 / 400.740 / 440.690 | Reported only | Not gated |
| largest_callback_excluding_texture_ms | 145.441 / 148.691 / 184.350 | 150.211 / 150.750 / 164.861 | 184.350 | Pass |

| Run / texture marker | Physical MiB | Kernel lifetime peak MiB |
|---|---:|---:|
| Control-1 / globe-texture-before | 119.424 | 120.768 |
| Control-1 / globe-texture-after | 117.815 | 263.706 |
| Candidate-1 / globe-texture-before | 118.112 | 119.330 |
| Candidate-1 / globe-texture-after | 116.112 | 252.440 |
| Control-2 / globe-texture-before | 117.737 | 119.987 |
| Control-2 / globe-texture-after | 118.424 | 263.768 |
| Candidate-2 / globe-texture-before | 132.659 | 132.659 |
| Candidate-2 / globe-texture-after | 117.080 | 262.956 |
| Control-3 / globe-texture-before | 118.487 | 119.893 |
| Control-3 / globe-texture-after | 113.299 | 263.612 |
| Candidate-3 / globe-texture-before | 119.127 | 120.440 |
| Candidate-3 / globe-texture-after | 106.830 | 245.909 |

### soak-awake alternating triplicates

| Run | Footprint min/max MiB | Lifetime peak MiB | Max mean ms | Max p99 ms | Raw callback ms | Outside-texture callback ms | Hitches >25 ms | Texture intervals ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Control-1 | 119.300 / 381.800 | 844.519 | 19.070 | 117.680 | 468.610 | 175.220 | 102 | 495.630 |
| Candidate-1 | 118.100 / 346.700 | 842.378 | 19.290 | 121.650 | 187.120 | 187.120 | 95 | 390.809 |
| Control-2 | 117.700 / 348.900 | 810.394 | 19.150 | 109.850 | 446.610 | 167.770 | 107 | 315.242 |
| Candidate-2 | 118.000 / 344.800 | 844.112 | 18.860 | 116.230 | 451.180 | 175.360 | 105 | 209.586 |
| Control-3 | 118.200 / 391.300 | 817.550 | 19.250 | 112.380 | 392.230 | 173.813 | 102 | 583.063 |
| Candidate-3 | 117.800 / 350.800 | 846.597 | 19.650 | 114.510 | 642.700 | 190.405 | 97 | 646.431 |

| Metric | Control min / median / max | Candidate min / median / max | Gate limit | Result |
|---|---:|---:|---:|---|
| footprint_min_mib | 117.700 / 118.200 / 119.300 | 117.800 / 118.000 / 118.100 | Reported only | Not gated |
| footprint_max_mib | 348.900 / 381.800 / 391.300 | 344.800 / 346.700 / 350.800 | Reported only | Not gated |
| lifetime_peak_mib | 810.394 / 817.550 / 844.519 | 842.378 / 844.112 / 846.597 | 842.550 | Fail |
| max_window_mean_ms | 19.070 / 19.150 / 19.250 | 18.860 / 19.290 / 19.650 | Reported only | Not gated |
| max_window_p99_ms | 109.850 / 112.380 / 117.680 | 114.510 / 116.230 / 121.650 | Reported only | Not gated |
| hitches_over_25ms | 102.000 / 102.000 / 107.000 | 95.000 / 97.000 / 105.000 | 117.300 | Pass |
| largest_callback_ms | 392.230 / 446.610 / 468.610 | 187.120 / 451.180 / 642.700 | Reported only | Not gated |
| largest_callback_excluding_texture_ms | 167.770 / 173.813 / 175.220 | 175.360 / 187.120 / 190.405 | 191.194 | Pass |

| Run / texture marker | Physical MiB | Kernel lifetime peak MiB |
|---|---:|---:|
| Control-1 / globe-texture-before | 117.096 | 121.362 |
| Control-1 / globe-texture-after | 118.721 | 246.581 |
| Candidate-1 / globe-texture-before | 118.721 | 120.284 |
| Candidate-1 / globe-texture-after | 117.112 | 264.065 |
| Control-2 / globe-texture-before | 133.315 | 133.315 |
| Control-2 / globe-texture-after | 112.705 | 243.487 |
| Candidate-2 / globe-texture-before | 133.268 | 133.268 |
| Candidate-2 / globe-texture-after | 117.455 | 263.143 |
| Control-3 / globe-texture-before | 117.534 | 121.190 |
| Control-3 / globe-texture-after | 117.690 | 248.956 |
| Candidate-3 / globe-texture-before | 117.362 | 120.393 |
| Candidate-3 / globe-texture-after | 124.377 | 247.409 |


The fresh soak set completed all six runs with continuous logs and all five
exact camera/sunlight restore checks per run. Its candidate peak median is
844.112396 MiB against control 817.549850 MiB: +26.562546 MiB. The allowed
limit is 842.549850 MiB, so the peak gate **fails by 1.562546 MiB**. Candidate
hitches have median 97 against control 102, and outside-texture callback
median 187.120 ms is below the 191.193841 ms limit. Those gates pass. The
peak failure is retained without rounding, changing the rule or drawing a
conclusion from selected runs. Full texture markers and all 60 surface/
returned checkpoints are retained in `Step1/soak-awake-tables.md` and the
six `summary.json` files.

| Run | Surface physical range MiB | Returned physical range MiB |
|---|---:|---:|
| Control-1 | 347.409 / 378.471 | 348.706 / 381.706 |
| Candidate-1 | 345.065 / 345.175 | 346.315 / 346.471 |
| Control-2 | 347.003 / 347.096 | 348.237 / 348.300 |
| Candidate-2 | 343.175 / 343.284 | 344.378 / 344.550 |
| Control-3 | 345.471 / 345.753 | 346.846 / 346.893 |
| Candidate-3 | 349.112 / 349.253 | 350.440 / 350.487 |

### Stop checkpoint and resume work

The original `Step1/soak/` set was interrupted by host sleep during
Candidate-2. Gaps were 4,438.88 seconds from 07:56:34 PDT and 246.07 seconds
later; `incomplete.json` and `host-power-log.txt` retain the evidence. That
driver was stopped during Control-3. No pass/fail conclusion is drawn from
that set. The separate `soak-awake/` replacement ran from the first control
through the third candidate with a process-bounded idle-sleep assertion and
continuity checks; it did not mix samples from the interrupted set.

At the owner's stop request, the replacement soak completed as the driver
advanced to warm-highland Control-1 setup. The entire process group and app
were terminated. Highland has zero completed capture stages and no valid
measurement or gate conclusion. No further builds, captures, soaks or
benchmarks were started. No validation process or sleep assertion remains.

Step 1 remains withheld because the completed soak peak gate fails and the
warm-highland gate is outstanding. The next useful action is read-only
attribution of the roughly 26.56 MiB soak peak difference using the retained
phase markers. Do not change behavior or the acceptance rule to force a
landing. Any subsequent validation needs a new authorized run; warm-highland
still requires a complete alternating three-pair set and image inspection.
Allow roughly 15–20 minutes for that set, or about 75–90 minutes if a newly
justified soak set is also needed, excluding implementation and builds.

Steps 2, 3 and 4 have not started. There is no Moon app or Moon executable.
For step 4 the owner permits moving map-only suites out of `LMTests.swift`,
verbatim into files named for their suites, changing only imports and
`Bundle.main` to `LunarMap.resources`. Remaining cockpit/AGC tests, including
P64, must remain byte-identical apart from removed map blocks. Record which
suites move and show the residual-file diff. `step4-suite-inventory.json`
is read-only preparation, not a completed extraction.

All candidate branches are preserved. `lunar-map/step-1` contains runtime
`3e94add` plus this documentation checkpoint. Main remains `89ecb0f`.
`onezoom/D` remains `7283b992ffdaf2ecaff4603ba95acedce5a50caa`, and
`onezoom/F` remains `ba0b87e10fc438fde4330c89dccd7794b9ab20ff`; their rebase
onto the package result is outstanding because no package step landed.
All onezoom branch hashes before this docs commit are retained in
`Step1/branches-before-checkpoint.txt`. Nothing was pushed.

All physical Vision Pro gates remain open: stereo/crossfade perception,
tracked head/hand/gaze input, gesture comfort, CPU/GPU pacing, memory
pressure, thermal behavior and long-session stability. Simulator acceptance
does not establish physical-device performance or comfort.

## Development and integration resumed, 2026-09-08

The owner authorized finishing steps 2–4 and integration while documenting
the long validation as outstanding. The prior soak peak failure stays a
failure; highland stays incomplete. No new captures, soaks or performance
benchmarks are being run.

### Step 2: app seams (`f1f9767`)

Hosts now supply launch options and log identity before creating models.
Package code has no ProcessInfo reads or MainMenuViewModel references. The
ordered argument payload preserves existing parser precedence and duplicate
handling; profiling enablement is parsed at construction. HostActions makes
close/cockpit callbacks optional and supplies the cockpit display name.
Process-wide presentation state and texture-cache scope are documented.
Existing compatibility initializers preserve callers and test behavior.

Release build passed; 45 focused Explorer, experience, navigation
and portal tests passed, 0 failed. Evidence: `Development/Step2/`.
Executable SHA-256: `9fd41307c563c03312fc23ab92ccda9f46b049e01c75293b6e0e658bb34e3415`.
No Moon binary exists at this step. Full-suite comparison on this revision,
Apollo captures/settle, matched performance and physical gates are deferred.

### Step 3: standalone Moon host

Added native `Moon` target, bundle identifier `io.positron.Moon`, sharing the
engine and Explorer products. MoonModel owns one session and immersive-space
state; the host opens the map, supports the existing immersion styles and
capture flags, and supplies close only. Scene manifest, automatic signing
team and placeholder spatial app icons match the project conventions.
The target has no direct AGC, RealityKitContent or cockpit dependency. LMCore
still brings AGC transitively, as accepted in the plan.

Capture scripts now use `LUNAR_BUNDLE_ID` with the LM default, including log
filters, container lookup, launch and termination. Executable hashing reads
CFBundleExecutable instead of assuming LM. Measurement output records bundle
identity; the 13 tool tests pass under both identifiers, and all capture
scripts pass bash syntax checks. No capture sequence was run.

Moon Release builds and ordinary launch succeeds. Evidence: `Development/Step3/`.
Moon executable SHA-256: `ef2a6d82a7847a5fcdb7ac8b14e20a35b12d2fd7735fbdf00ffb2e6b1773cc02`.
Release bundle: 193,419,316 bytes (184.46 MiB), including pinned resources.
LM source is unchanged by this step; its latest ordinary SHA is recorded
under Step 2. A final LM build follows the test move.

Deferred: Moon/LM Apollo byte comparisons and 90-second settle, visual journey
and restore acceptance, matched performance sets, and all physical gates.
Ordinary launch does not establish visual parity.


### Step 4: package tests and generator paths

Moved 20 standalone map-test files with `git mv` to
`Packages/LunarMap/Tests/LunarMapTests`. From the original `LMTests.swift`,
three whole suites moved into same-named files: `ProgressiveLunarTerrainTests`
(23 tests), `TerrainRelativeLandingTests` (5), and `TerrainDetailTextureTests`
(15). Seven map cases from `LMTests` and 18 map cases from
`SourceBackedTerrainTileTests` moved into same-named package suites; their
cockpit cases remain in LM. The app-model case from `LunarExplorerTests`
stays hosted. Total test identities remain 317: 231 package and 86 host.

The three whole suites are verbatim apart from imports/resource qualification.
The remaining `LMTests.swift` equals the original minus the removed blocks;
all four standalone cockpit test files and P64's method body are byte-identical.
Evidence: `Development/Step4/final-source-audit.json`, `move-audit.json` and
`LMTests-remaining.diff`. Five map fixture helpers moved verbatim with their
suite. Host-only fixture types retain verbatim builders used by cockpit tests,
so those test bodies need no changes and no test cases are duplicated.

One moved mixed-suite test, `apollo11TerrainAssetsRemainByteIdenticalToStage1`,
previously located resources relative to `#filePath`. Moving its file broke
that location. It now uses `LunarMap.resources.resourceURL` plus `Terrain`;
its eleven expected hashes and assertions are unchanged. The first executed
package run exposed that lookup failure; the corrected full run passes.
This is a test-resource location change, with no runtime behavior change.

All package tests run unhosted with the `LunarMap-Package` scheme, from
`Packages/LunarMap`; the product scheme `LunarMap` has no test action.
No Moon-hosted fallback test bundle was necessary. The generator's default
output and strip-catalog output now point to package Terrain resources.
Both tool dry runs resolve those paths without reading source rasters or
writing pinned assets. The Swift generator compiles. Evidence:
`Development/Step4/terrain-generator-dry-run.txt` and
`strip-generator-dry-run.txt`. Generator algorithms are unchanged.

#### Same-state functional control

The separate AGC checkout advanced externally during this development run
from `166b5860f19ea5a4ced0b0d6d36b4e779d530935` to
`b3f15533db335ee882dc07401790c93010809e8f`. We made no AGC changes. Its
existing uncommitted state remained:

```text
 M Sources/LMCore/LMAGCPadLoad.swift
```

The dirty pad-load SHA-256 remains
`9a2a31a38b024e4f1bf92e34a499d146a16a1583ba33908f5db3f1b9a8b165c0`.
To avoid attributing dependency changes to extraction, the unchanged LM
control `89ecb0f` was tested again against this exact AGC checkout, followed
by a fresh package run. The final host run also uses this state. Recorded in
`Development/agc-state.json` and `Development/CurrentAGC-Control/`.

| Simulator Release suite | Passed | Failed | Result |
|---|---:|---:|---|
| Unchanged control `89ecb0f` | 316 | 1 | Exempt P64 only |
| LunarMap package | 231 | 0 | Pass |
| Final LM-hosted tests | 85 | 1 | Exempt P64 only |
| Combined package + host vs control | 316 | 1 | Same 317 identities and outcomes |

`PoweredDescentCheckpointSessionTests/p64PROAndACAChangeLuminaryLandingTarget()`
fails with identical failure text on the refreshed control and final host.
It remains exempt and handed to the cockpit owner. No outcome changed in
either direction. Evidence: `Development/Step4/outcome-comparison.json`,
`PackageTests-CurrentAGC.xcresult`, `HostTests-Final/Tests.xcresult` and
`Development/CurrentAGC-Control/Tests.xcresult`.

#### Final ordinary Release builds and contract audit

Both apps build with Xcode 26.6 for the designated visionOS 26.5 Simulator,
serially. These are ordinary Release builds, after the testable builds.

| App | Executable SHA-256 | Bundle bytes | MiB |
|---|---|---:|---:|
| LM | `c146cc689373fc896685c4b36a1051ea3151c9639721819c2a780c7d24c32091` | 469,806,950 | 448.04 |
| Moon | `970d1773103b7557ae9e7bf6bcc13683681b0a42013c9569948b2b0b31e8d77c` | 193,419,316 | 184.46 |

Frozen apps are under `Development/Final-LM/` and `Development/Final-Moon/`;
build logs and `Development/final-builds.json` retain exact provenance.
The source contract audit passes all eleven pinned resources and all five
protected method bodies (`Development/Contracts/`, `Development/contracts.log`).
No terrain data, contact geometry, residual limits, source ordering, shaders,
or capture algorithms changed. The 76 MB capture JPEG XL remains bundled.

### Final development checkpoint: integration authorized, qualification open

The owner explicitly requested development completion and integration into
`terrain-realism-and-explorer` with lengthy validation documented as
outstanding. This supersedes the previous instruction to withhold package
integration until all performance/capture gates passed; it does not turn
failed or unrun gates into passing evidence. Steps 1–4 are development-complete.
Steps 5 and 6 remain not started. Candidate branches and earlier evidence
are preserved; nothing is pushed.

| Scope | Completed evidence | Still outstanding |
|---|---|---|
| Step 1 | Same-outcome tests; ordinary Release; eleven Apollo PNGs identical; 90-second settle; contracts; journey triplicates | Fresh soak peak **failed by 1.562546 MiB**; warm-highland incomplete; no passing replacement claimed |
| Step 2 | Ordinary Release; 45 focused passes; final combined outcome audit; no package ProcessInfo/host-model references | Step-specific Apollo/settle and alternating journey, soak, warm-highland qualification |
| Step 3 | Moon Release and ordinary launch; 13 tool tests under each bundle ID; final build | Moon eleven PNGs vs baseline, LM regression ladder, settle, inspected journey/switch, restore and matched performance |
| Step 4 | 231 package passes; 85 host passes + identical P64; full 317-outcome control match; source audit; both Release apps; generator dry runs | Final LM/Moon visual and performance qualification; intermediate-step performance isolation was not run |

No new captures, soaks or benchmarks were started in this development
continuation. Prior interrupted warm-highland work stays incomplete.
Performance and visual parity cannot be inferred from passing builds/tests.
Future qualification must use the existing corrected named gates, including
callback margin and ≤16.70 ms settled mean/p99/max with zero missed callbacks.
All new visual inspections are deferred; earlier Step 1 inspected images
remain the only package-run capture evidence.

Every physical Vision Pro gate remains open: stereo appearance and continuity,
tracked hand/head/gaze input, comfort, device CPU/GPU pacing, memory pressure,
thermal behavior and long-session stability. Simulator results do not establish
physical-device acceptance. The separate AGC modification and both user scheme
files are preserved; no AGC code or cockpit tests were edited by this work.


#### Integrated commits and preserved branches

`terrain-realism-and-explorer` was fast-forwarded to runtime integration head
`de2cbb94b7714d5c38f65a48af673f18ea5d0fa8`:

| Development item | Commit | Preserved branch tip before final documentation |
|---|---|---|
| Package skeleton/resource seams | `3e94add` | `lunar-map/step-1` at `9778bd7` (includes stop checkpoint) |
| Launch options and host actions | `f1f9767` | `lunar-map/step-2` at `f1f9767` |
| Standalone Moon target | `e797590` | `lunar-map/step-3` at `e797590` |
| Package tests and generator paths | `de2cbb9` | `lunar-map/step-4` at `de2cbb9` |

The final documentation-only commit does not change either recorded Release
executable. Exact final refs, worktree status and AGC state are retained in
`/tmp/LM-LunarMap-2026-09-08/Development/final-state.json`.


Parked `onezoom/D` was rebased onto the integrated runtime tree. Its validated
runtime revision is `12c8a4ab70396d95e7e512e9ca51cc4418ef5d4f`; the subsequent
rebase over this documentation-only checkpoint preserves that runtime tree.
Mechanical adaptations moved its new test with `git mv`, redirected the
existing finer-owner helper to its package location, and applied compiler-
required `package` visibility to `prepareCoarse`. No algorithm changed.
The engine and Explorer compile with 12 affected resolver/refinement tests
passing (`Development/Parked-D-Tests-Accessible.xcresult`). Earlier dependency-
path and compile failures are preserved in `Development/parked-d-tests*.log`;
the temporary worktree now links to the same existing AGC checkout.
The broader 97-test pre-package check and D app-build/capture/performance
qualification were not repeated. D stays parked. Its next experiment remains
concurrency 1/2/4 with three warm highland dives each, ranked by regional and
per-generation ready time, followed by acceptance gates. F remains an
unimplemented branch at the final base, pending D. Nothing from D or F was
merged into the integrated apps.


### Main integration, 2026-09-09

The owner authorized combining the completed package development with the
newer LMKit cockpit and publishing directly to main. Runtime merge `3ec34fa`
preserves the terrain/package and cockpit histories. Compiler-required package
interfaces expose existing sun values and rendered positions; the prepared
Apollo contact construction moves into LunarMap without changing its arithmetic.
A new regression verifies contact uses the rendered grid, including both
triangle interiors. Full results and the direct-main publication checkpoint
are in [MainIntegration.md](MainIntegration.md).

This adds 232 package passes, 170 host passes plus the independently confirmed
unchanged P64 failure, clean AGC/LMKit dependency checks, both ordinary Release
builds and bounded runtime inspection. It does not close the historical soak,
matched performance, full LM/Moon Apollo parity, or physical-device gates above.
