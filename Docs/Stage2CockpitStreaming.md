# Cockpit terrain streaming

This follows `LandAnywhereMoonPlan.md` Stage 2 item 5 and the mission evidence
in `Stage2CockpitIntegration.md`. It does not close physical Vision Pro gates.

Implementation commits: `9c326fd` (instrumentation), `33e3ab1` (capture/report
bookkeeping), and `efdf810` (streaming, contact hold and regression tests).

## Measured problem

The cockpit previously stopped every near-ground simulation step until a
requested terrain generation finished, even though the previous generation
remained rendered with matching contact. The first two Release missions took
up to 30.365 seconds (mare) and 34.420 seconds (highland) per generation.

Instrumentation commit `9c326fd` separates coverage/readiness pauses from
publication-gate waits and realtime frame-cap losses. Missing footpad samples
are counted explicitly. Previously the contact audit skipped missing samples.
The fresh normal Release mare control, `/tmp/LM-Streaming-Before-Mare`, has
binary SHA-256 `ab9d09be1c1ca0402e1e5bd7db25454ec15243b10273983ad393e7adf6586be9`.
It finished with an intact hard landing after 687 seconds of capture wall time:

- Terrain pauses: 422.187 seconds.
- Publication waits: 1.194 seconds total; 16.533 ms maximum.
- Realtime frame-cap losses: zero.
- Contact: 51,988 samples, zero missing samples, exactly zero height error.
- 66 completed generations: 528.606 seconds total, 28.355 seconds maximum.
- Cache: 676 complete hits; 272 absent tiles, 341 changed plans, 140 parent
  invalidations, and 376 ownership invalidations.
- Frame-window peak: 448.1 MiB; phase peak: 588.253 MiB; lifetime peak:
  655.972 MiB. Worst frame: 787.11 ms, including terminal recording encoding.

Generation time can overlap flight. It must not be added to pause time.
Publication waits can contribute to frame-cap loss, so those counters must
not be added together either. Frame-cap loss includes all causes and is not
automatically attributable to terrain.

## Implementation

Flight readiness now checks the published rectangle union covering the entire
footpad/probe sweep, including internal gaps. Its conservative reach includes
gear spread, maximum strut stroke, probe length, velocity over the largest
runtime step (0.25 seconds), and a 100 m/s² acceleration allowance using the
plant's semi-implicit position update. This allowance exceeds propulsion
acceleration in these mission configurations. Coverage is checked again inside
the simulation/publication gate. Old geometry remains installed during baking;
GPU morph completion and its matching contact snapshot remain atomic with
respect to full simulation steps.

Predictions use canonical source coordinates and radial vertical velocity.
The 40-second upper horizon exceeds the observed 34.420-second generation
maximum. Time is also limited by four tiles at the next detail level: 64 m
for landing, 256 m for terminal descent, and 1,024 m for approach. Applying
the time and distance bounds together avoids requesting landing detail at
500 m while traveling 50 m/s. Current and predicted footprints are enclosed
with the existing rectangular collar planner. Predictive residency is capped
at 80 tiles; over-budget predictions fall back to normal current-view plans.
The cockpit retains a footprint while its usable interior covers the vehicle
and a bounded motion margin. The Explorer keeps its existing residency policy.

Tile cache dependencies include nearby parent geometry revisions and plans
used by edge-normal samples. The dependency region extends two sample spacings
beyond the tile; the baker reads at most one spacing beyond its edge. Parent
revisions propagate ancestor geometry changes. An ownership-only change
replaces the shared baker's triangle list while retaining positions, normals,
and material. Equal parent positions/normals retain their geometry revision,
so changing a child's ownership mask does not invalidate unrelated geometry.
Only the previous and incoming generations are retained; there is no growing
history of cached flight footprints.

The first optimized Mare capture, `/tmp/LM-Streaming-After-Mare`, is diagnostic
evidence, not final acceptance. It removed coverage pauses and shortened the
capture from 687 to 264 seconds, but the 160-tile predictive budget allowed a
1,466.832 MiB lifetime peak, and the vehicle could settle during a continuing
morph. Its 0.230 seconds of frame-cap loss and 129.698 ms maximum publication
wait are retained as regressions. The follow-up reduces the budget to 80 tiles
and latches terrain publication at the first probe/gear contact. Unpublished
work is discarded; an active morph retains its exact displayed surface without
holding the simulation gate. Ignition restart or departure above 250 m releases
the hold. This keeps the landing dynamics active while preventing the terrain
from moving beneath a settled vehicle.

## Automated evidence

`/tmp/LM-Streaming-Tests-v3.xcresult`: 21 Release tests in six suites pass.
After coupling prediction time to its distance bound,
`/tmp/LM-Streaming-Policy-Final.xcresult`: all five streaming tests pass again.
The final contact hold and 80-tile budget pass all 22 tests in six suites in
`/tmp/LM-Streaming-Contact-Hold.xcresult`.
The tests cover pending-detail flight over published geometry, internal holes,
swept gear coverage, bounded prefetch, exact cached-versus-fresh positions,
normals and indices, ancestor and neighboring-edge invalidation, ownership
remasking, GPU/contact equality throughout morphs, re-anchoring, cancellation,
landing drops, restart, and selected-site context.
The contact-hold tests also verify an unchanged displayed morph while the
simulation gate remains available, and successful publication after release.

The first test attempt failed to compile a diagnostic's dynamic `String` as
a Swift Testing `Comment`; the corrected tests pass. No product failure was
hidden by that correction. Build/test logs are in `/tmp/LM-Cockpit-Streaming`.

`Tools/SummarizeLunarCockpitStreaming.py` creates a PID-scoped report from a
mission capture, retaining the actual terminal outcome and unavailable counters.
The capture script records the app PID explicitly for future runs.

The first final-binary Mare capture exposed a capture-script race: a screenshot
blocked while flight continued, and the script detected the finished recording
without refreshing its earlier status JSON. The stale file is retained as
`/tmp/LM-Streaming-Final-Mare/stale-capture-status.json`. The app's terminal JSON
was recovered before relaunch, and its exact terminal state matches the recording.
The corrected harness refreshes status at recording completion and records
before/after status and wall timestamps around screenshots. A missing in-flight
P65 image in that run must not be described as captured.

## Final Release mission measurements

Both final routes use binary SHA-256
`6e7f75715ba595e575aac2f61c423c8a6aa784056f3073d809acc9767e1f7d87`, built normally
after the testable Release run. The Simulator is
`8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`, visionOS 26.5 (23O470), with Xcode 26.6.0.
No builds or tests overlapped these captures. Source hashes are recorded in
`/tmp/LM-Cockpit-Streaming/final-source-hashes.json`.

| Measurement | Mare control | Final Mare | Final Highland |
| --- | ---: | ---: | ---: |
| Capture wall seconds | 687 | 296 | 295 |
| Coverage/readiness pause seconds | 422.187 | 0 | 0 |
| Publication wait total seconds | 1.194 | 2.177 | 1.861 |
| Largest publication wait ms | 16.533 | 112.500 | 35.918 |
| Realtime frame-cap loss seconds | 0 | 0.070 | 0 |
| Completed generations | 66 | 31 | 27 |
| Generation work seconds | 528.606 | 192.102 | 212.091 |
| Largest generation seconds | 28.355 | 29.022 | 31.974 |
| Largest static generation tiles | 74 | 77 | 75 |
| Frame-window peak MiB | 448.1 | 468.4 | 631.6 |
| Phase-sampled peak MiB | 588.253 | 655.988 | 657.097 |
| Process lifetime peak MiB | 655.972 | 656.035 | 719.675 |
| Worst frame ms | 787.11 | 752.31 | 821.16 |
| Audited contact samples | 51,988 | 51,252 | 64,400 |
| Missing samples / maximum error m | 0 / 0 | 0 / 0 | 0 / 0 |

The fresh Mare comparison uses the same route, Simulator, normal Release
configuration and capture method. Generation work fell 63.7%, and the
422-second readiness pauses disappeared. The smaller final budget removed the
first revision's large lifetime-memory regression. Short publication hitches
remain; this is not a zero-hitch or physical-device performance claim. Worst
frames include the opt-in terminal recording serialization.

The Highland historical control in `Stage2CockpitIntegration.md` used an older
binary without pause instrumentation: 62 generations, 668.361 seconds of
generation work, 34.420 seconds maximum, 658.82 MiB lifetime peak. That is
historical context, not a fresh paired control. Its final lifetime peak is
about 61 MiB higher and remains a performance cost to profile on hardware.

Final Mare remains an intact hard landing: 0.880 m/s vertical, 0.256 m/s
horizontal, 2.557° tilt; no gear failure. Highland remains a crash with
`contactEnvelopeExceeded`: 0.791 m/s vertical, 0.456 m/s horizontal, 15.845°
tilt. It reaches contact at radial altitude -17.460 m without a false datum
collision. Both final reports have `heldAtContact = 1`. Each performs 152
floating-origin updates on the high approach; the footpad audit begins below
250 m and does not establish contact coverage during those early updates.

Capture directories contain the recordings, screenshots, timing logs and
`streaming-summary.json`:

- `/tmp/LM-Streaming-Before-Mare`
- `/tmp/LM-Streaming-Final-Mare` (terminal status recovered as described above)
- `/tmp/LM-Streaming-Final-Highland`

Highland's P63, P64, P65, below-250/60/10 m and crash images were captured.
Screenshot metadata brackets the actual simulation state; P63 advances four
simulated seconds during its capture, while later brackets span at most about
one second. The terminal view still shows coarse distant faceting. Screenshot
inspection and exact GPU tests do not close stereo-motion or headset comfort.

The unchanged final binary was repeated at Mare with the corrected harness in
`/tmp/LM-Streaming-Mare-Confirmation`. This completes the P63/P64/P65,
below-250/60/10 m, hard-landing and settled image set. It again lands intact,
with 51,828 samples, zero missing samples/error and zero coverage pauses.
Capture wall time is 266 seconds, completed generation work is 187.438 seconds
across 30 generations, and the largest generation is 29.429 seconds/77 tiles.
Publication waits total 2.024 seconds, with a 50.222 ms maximum; frame-cap loss
is 0.018 seconds. Frame-window peak is 488.7 MiB and lifetime peak is
736.722 MiB, higher than the first final-binary Mare run. The final Mare memory
range is therefore 656.0–736.7 MiB; the 1,466.8 MiB regression was removed, but
the repeat must not be presented as memory-neutral against the 656.0 MiB
control. Worst frame is 750.86 ms, including terminal recording serialization.

All three final recordings pass the existing replay verifier: Codable round
trip, site identity in every frame, 1,001 finite replay samples, and exact
terminal state. Frame counts are 13,406 (first final Mare), 13,549 (Mare
confirmation), and 15,105 (Highland). Evidence:
`/tmp/LM-Cockpit-Streaming/replay-check.log`.

## Apollo comparison and remaining gates

The final eleven-stop, 20-second Release ladder is in
`/tmp/LM-Streaming-Final-Apollo`. All eleven PNGs are byte-identical to item 0,
and all eleven pinned assets match `c950d46`. The first globe launch failed
the established saturation check (0.0860 versus the 0.01 limit); its retry
passed. `all-attempt-metrics.json` retains that rejected PID. The comparison
uses only the accepted PIDs in `profile-runs.tsv`.

| Accepted Apollo measurement | Item 0 | Previous chunk | Current |
| --- | ---: | ---: | ---: |
| Frame-window peak MiB | 406.5 | 370.1 | 367.9 |
| Worst cold frame ms | 643.77 | 438.65 | 518.03 |
| Reported missed frames, all windows | 82 | 88 | 88 |
| Process lifetime peak MiB | unavailable | 1,605.207 | 1,611.878 |

Every settled p95/p99 is 16.67 ms, with zero reported misses. The landing
stop's final window has a 22.22 ms maximum (mean 16.61 ms); other final maxima
are 16.67 ms. This small pacing difference is retained. Current tile generation
ranges versus item 0, in milliseconds:

| Stop | Item 0 | Current |
| --- | ---: | ---: |
| Terminal | 252–356 | 313–341 |
| Landing | 1,471–2,043 | 1,844–1,966 |
| Relief blend start | 1,334–1,815 | 1,372–1,531 |
| Relief blend end | 1,390–1,882 | 1,393–1,599 |
| Surface | 1,351–1,819 | 1,404–1,604 |

These are measured runs, not isolated attribution of every timing change.
`baseline-comparison.json`, `performance.tsv`, and the PID-scoped metrics retain
the full comparison. No asset, residual-cap, measured-post, coordinate, or
landing-envelope contract was relaxed. The AGC checkout was not changed, and
the two scheme-user files and unrelated padload edit retain their original hashes.

The checked routes now fly without readiness/coverage pauses, with no missing
or mismatched audited contact and stable terrain after contact. Publication
hitches, allocation variation, distant faceting/coverage, and an intact
Highland landing remain open. Physical Vision Pro still needs stereo seam and
re-anchor inspection, sustained frame pacing, GPU allocation/thermal profiling,
and head/hand interaction and comfort validation. Simulator captures do not
close those gates.
