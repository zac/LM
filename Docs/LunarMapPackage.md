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
