# Terrain publication, recording memory and contact diagnostics

This continues `Stage2CockpitStreaming.md` under Stage 2 item 5. The visual
reference review is separate in `ArtemisFlybyRealism.md`.

## Changes and attribution

Terminal capture previously encoded every recorded frame on the main actor.
The new path writes bounded JSON on a utility task into a unique partial file.
It waits for the worker before cleanup, checks cancellation and flight identity,
then atomically renames the file on the main actor. Stopping or restarting
cannot publish an older run. The gameplay recording/replay remains available.
The capture harness terminates the preceding app before clearing its two
capture artifacts, preventing an old export from racing the next launch.

The AGC writer is `166b586`; the first-contact normal diagnostic is `15c3424`.
`LMSurfaceContactSnapshot.tiltRadians` is vehicle tilt relative to the first
loaded pad's normal, not terrain slope. New captures separately report that
normal and its angle to the original site up axis. It is the existing
footpad-diameter finite difference at first contact; it does not alter contact
forces, the 6-degree tilt limit, or landing classification. Older recordings
have an unavailable normal, not a zero slope.

Cockpit morph timing now separates GPU-completion waits from contact snapshot
publication inside the existing full-step gate. The geometry/contact contract
and 1.2-second morph are unchanged. A separate opt-in
`LUNAR_CAPTURE_TERRAIN_RAYS=1` capture reports nine unoccluded terrain rays from
the nominal Simulator eye at terminal contact. It retains submitted-triangle
spacing, distance and `atan(spacing/distance)` as an angular cell-size proxy.
These rays exclude cockpit hull occlusion and do not represent tracked headset
pose. They run on a worker and are excluded from normal performance captures.

## Isolated export measurement

The Release host benchmark in `/tmp/LM-Artemis-Realism/ExportBenchmark` repeats
one captured contact frame 15,000 times in fresh processes. Both methods write
90,540,088 byte-identical bytes. Whole-document encoding took 1.070 s and
peaked at 637,681,664 bytes RSS; bounded writing took 0.925 s and peaked at
30,834,688 bytes. Both began at 26,345,472 bytes. This proves lower export
allocation for that workload, not reduced global terrain/GPU residency.

## Intermediate mission control

`/tmp/LM-Artemis-Diagnostics-Highland` uses normal Release binary
`6e4c49412e7736acd40ec07fbec8ab9d09ceabf35d1bef9415f4e7aec0aa82a6`.
It has off-main whole-document export and the new contact/timing diagnostics,
but predates bounded writing and terrain rays. It finished in 294 wall seconds
with a valid crash, 64,120 exact contact samples and zero missing samples or
coverage pauses. First-contact tilt was 16.2016 degrees and pad-scale slope
to site up was 16.2300 degrees; vertical/horizontal speeds were
0.8449/0.3173 m/s. Timing changes can shift the live touchdown position, so
these do not retroactively establish the previous run's slope.

Worst frame was 277.87 ms, versus the preceding Highland's 821.16 ms including
terminal encoding. Export ran for 840.956 ms on a worker; main-actor rename
took 0.125 ms. Publication waits still reached 115.832 ms. Across 2,395 morph
updates, GPU waits totalled 8.074 s with a 116.549 ms maximum; contact
publication totalled 37.826 ms with a 0.342 ms maximum. These intervals overlap
other counters and must not be added together.

Lifetime footprint rose to 858.785 MiB, versus the preceding Highland's
719.675 MiB. Its sampled peak occurred during `morph-submit`, before terminal
export. The export fix therefore cannot be presented as a cure for that
terrain allocation variation. The run completed 28 generations, 209.707 s
of generation work, a 30.746 s maximum and at most 73 static tiles.

The largest transition contains 113 tiles, 99 dynamic meshes and 99 appearance
pairs. Thus the 80-tile prediction cap is not a transient residency budget.
Logical phase peaks reach 253.107 MiB of source textures, 280.741 MiB of output
textures, 50.276 MiB of GPU endpoints and 87.984 MiB of vertex payload. These
phase maxima need not coincide and are not driver-allocation measurements;
do not sum them into a memory total. The summary tool now retains these
quantities separately from static generation counts.

## Automated validation

`/tmp/LM-Artemis-Diagnostics-Tests.xcresult` and
`/tmp/LM-Artemis-Export-Tests.xcresult` each pass 18 Release Simulator tests
across arrival, streaming, restart and publication-gate suites. The final
opt-in ray diagnostic was added after the latter tests and is covered by
normal Release compilation and the terminal diagnostic capture.

AGC passes 16 landing-gear tests and four recording/replay tests. New tests
separate a 12-degree plane from roughly 7-degree vehicle/contact tilt, decode
legacy contact JSON, compare complete streamed bytes across buffer boundaries,
retain selected-site replay and report write errors.

The replay checker was rebuilt against the final AGC checkout after captures.
Both final exports pass full Codable round-trip equality, 1,001 finite replay
samples with the selected site preserved, and exact terminal-state replay:
13,575 frames for Mare, 14,804 for Highland. Results are retained in
`/tmp/LM-Artemis-Realism/replay-results.log`.

Logs are in `/tmp/LM-Artemis-Realism`. An initial AGC test build overlapped a
test-source correction and failed; its clean rerun passes. A Release command
with a mistyped Simulator ID failed before building, and a first capture
launch exposed Bash 3's empty-array/nounset behavior. Both were corrected;
the failed attempts are retained and excluded from accepted measurements.

## Final Release Mare capture

`/tmp/LM-Artemis-Final-Mare-v2` uses normal Release binary
`3078b67fca3ecda7879b3bff5ddf369875d85ff12fb2b30622f4d6ccb259ed6c`.
It runs without the optional terrain rays. The selected site is 8.35 N,
30.83 E; Simulator/runtime and the capture protocol match the preceding
streaming evidence. No builds or tests overlapped the capture.

| Measurement | Previous Mare confirmation | Final Mare |
| --- | ---: | ---: |
| Capture wall seconds | 266 | 268 |
| Coverage pauses seconds | 0 | 0 |
| Maximum publication wait ms | 50.222 | 105.418 |
| Publication wait total seconds | 2.024 | 2.054 |
| Realtime frame-cap loss seconds | 0.018 | 0.057 |
| Worst frame ms | 750.86 | 175.23 |
| Reported missed frames | 478 | 534 |
| Frame-window peak MiB | 488.7 | 474.1 |
| Lifetime footprint peak MiB | 736.722 | 777.160 |
| Completed generations | 30 | 31 |
| Generation work seconds | 187.438 | 192.206 |
| Maximum generation seconds / static tiles | 29.429 / 77 | 29.098 / 77 |

Mare remains an intact hard landing: 0.866 m/s vertical, 0.266 m/s horizontal,
3.888-degree contact tilt and 3.475-degree pad-scale slope to site up.
51,996 audited samples have zero missing samples and exactly zero height error;
terrain is held at contact. Export took 673.324 ms on a worker and rename
0.202 ms on the main actor. Sampled physical footprint changed from
348,884,280 to 348,933,432 bytes across export; the lifetime peak did not rise.

GPU waits across 2,671 morph updates totalled 8.635 s, maximum 118.119 ms;
contact publication totalled 40.155 ms, maximum 0.570 ms. The large terminal
serialization stall is removed, but publication outliers, total missed frames
and terrain memory are not improved in this run. The original item-0 baseline
has no matching global mission; its Apollo ladder is compared separately.

## Final Highland terrain rays

`/tmp/LM-Artemis-Final-Highland-Rays` uses the same final binary, with the
optional terminal diagnostic enabled. It again crashes within the existing
rules: 16.092-degree contact tilt, 15.922-degree pad-scale slope to site up,
0.877 m/s vertical and 0.328 m/s horizontal. 62,192 audited samples have zero
missing samples/error; coverage pauses remain zero and contact is held.
This diagnostic run includes background ray work at terminal contact, so its
whole-run frame/memory totals are not an uninstrumented performance control.

The downward rays hit 0.125 m terrain at 8.0–11.3 m distance and 0.5 m terrain
at 24.7 m. Horizontal center/left rays hit 512 m terrain at 23.859/61.604 km,
with cell-angle proxies of 1.229/0.476 degrees. The other horizontal ray hits
0.5 m terrain at 26.9 m. The three upward rays miss terrain, consistent with
sky in those directions. A miss here is not a missing footpad sample.

This establishes coarse distant geometry along the nominal view rays, while
the close footprint remains refined. It does not identify every visible
window pixel, because the diagnostic excludes cockpit hull occlusion. The
next far-field experiment should compare 512 m against denser interpolation
of the same measured source, with silhouette and seam captures. Budget the
transient morph union and texture payload first; a static tile count alone
understates the allocation cost. No measured-source or residual contract
should change to disguise facets.

## Apollo regression comparison

The final eleven-stop Release ladder is in `/tmp/LM-Artemis-Final-Apollo`.
All eleven PNGs are byte-identical to item 0, and all eleven pinned terrain
assets remain byte-identical to `c950d46` (`apollo-assets.json` in the evidence
directory). Each stop used the established 20-second baseline settling
interval and passed on its first attempt. No build or test overlapped captures.
The comparison includes only the eleven accepted PIDs in `profile-runs.tsv`.

| Accepted Apollo measurement | Item 0 | Previous streaming chunk | Current |
| --- | ---: | ---: | ---: |
| Frame-window peak MiB | 406.5 | 367.9 | 367.7 |
| Worst cold frame ms | 643.77 | 518.03 | 450.86 |
| Reported missed frames, all windows | 82 | 88 | 92 |
| Process lifetime peak MiB | unavailable | 1,611.878 | 1,602.957 |

Every final settled window has 16.67 ms p95/p99/maximum and zero reported
misses. The slightly higher whole-run miss count remains in the evidence;
these runs do not establish an isolated improvement in every pacing metric.
Current tile-generation ranges versus item 0, in milliseconds:

| Stop | Item 0 | Current |
| --- | ---: | ---: |
| Terminal | 252–356 | 307–323 |
| Landing | 1,471–2,043 | 1,930–2,020 |
| Relief blend start | 1,334–1,815 | 1,312–1,561 |
| Relief blend end | 1,390–1,882 | 1,327–1,563 |
| Surface | 1,351–1,819 | 1,310–1,565 |

`baseline-comparison.json`, `accepted-metrics.json`, `all-attempt-metrics.json`
and `performance.tsv` retain the full measurements. The two unrelated LM
scheme-user files and AGC padload edit retain their starting hashes.

## Remaining gates

GPU publication outliers, terrain allocation variation and distant faceting
remain open. The visually inspected final Mare and Highland terminal images
retain the calibrated presentation; Highland still shows distant facets.
The separate low-Sun controls in `ArtemisFlybyRealism.md` expose bands and
striping even without shadow maps, normal maps or reflectance texture. No
appearance change is accepted from those failed controls. A valid highland crash is
not an intact-landing acceptance. Safe-site assessment or explicit pilot
redesignation must be validated before claiming land-anywhere success; do not
move the target silently or relax the gear envelope.

Physical Vision Pro still needs stereo seam/re-anchor inspection, sustained
frame pacing, GPU allocation/thermal profiling, shadow/EDR presentation and
head/hand interaction comfort. Simulator evidence does not close those gates.
