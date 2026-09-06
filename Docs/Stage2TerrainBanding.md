# Low-Sun terrain banding correction

This continues the failed Highland controls in `ArtemisFlybyRealism.md` under
the contracts in `LandAnywhereMoonPlan.md`. The first correction fixes global
mesh shading without moving heights. Raw mesh inspection then identified a
separate source-ownership defect responsible for the prominent stripes. A
normal-map control then isolated a one-byte neutral-normal mismatch at the
fine/coarse appearance boundary.

## Reproduced collar shading error

The old normal calculation differentiated the already-morphed surface minus
measured elevation, added the measured normal, then blended the result toward
the parent's normal again. That injected derivatives of the parent's
piecewise-triangle interpolation error into the collar and weighted its ramp
twice.

A 0.2 m refinement over a flat parent reproduces the error without random
craters. At the midpoint of a 4 m collar, the rendered central-difference
slope is 0.0734375, but the old shading slope is 0.036669377. The pre-fix
transition suite fails this assertion in
`/tmp/LM-Terrain-Bands-Before-v3.xcresult`.

The corrected global path retains the unmorphed fine elevation from the
existing sample evaluation. It derives the fine endpoint's residual normal,
blends parent and fine slopes once, and adds the collar-weight derivative
times the endpoint height difference. The exact outer edge retains the parent
normal. No additional procedural relief is evaluated for interior vertices;
the temporary fine-height array costs four bytes per vertex during mesh build.
Apollo keeps its original arithmetic path.

The fixed ramp shading slope is 0.073437504. A second regression uses a smooth
quadratic source over a piecewise-linear parent. It reports zero slope error
along the collar and asserts unchanged morphed heights at each sampled vertex.

## Automated evidence

`/tmp/LM-Terrain-Bands-After.xcresult` passes 16 tests across transition,
arrival and contact suites. `/tmp/LM-Terrain-Bands-Resolver.xcresult` passes
six measured-source/residual tests. The normal Release build passes.

The first regression attempt had a throwing-expression test syntax error;
the second selected zero tests because the individual Swift Testing selector
did not match. Neither is counted as a pass. The complete pre-fix suite ran
six tests and recorded the expected failure, but its Xcode driver remained
alive after completion and required termination. Logs retain each attempt in
`/tmp/LM-Terrain-Bands`. All test/build processes finish before accepted
performance captures.

## Visual and performance evidence

The first fixed Release binary is
`acec2c9cf0f5bee552e737c588ee4b612bedd09d5324f9212c3cf091fd85e18b`.
`/tmp/LM-Terrain-Bands/Highland-Geometry` repeats the preceding 249 m / 700 m
geometry-only photographic control at a 120-hour Sun offset, with 90 seconds
of settling after readiness. Its RGB normalized RMSE against the old control
is 0.00174574, with 524,976 of 8,294,400 pixels changed. The prominent stripes
remain, so this does not accept the complete banding repair.

The ownership capture in `Highland-Tint` attributes the stripes to 2 m tiles
beside the 0.5 m corridor; they are not alternating holes in the submitted
ownership mask. A temporary opt-in raw mesh probe retained six 2 m tiles in
`/tmp/LM-Terrain-Bands/MeshProbe`. Its height/normal maps expose repeated rows
in every tile north of the local origin, beginning approximately 118 m north.
The probe run is diagnostic and excluded from performance comparisons.

## Source-strip halo defect

The Highland anchor is at a boundary of two overlapping LOLA 128 PPD strips.
The northernmost measured post of the southern strip lies about 118 m north
of the anchor. Beyond it, the resolver clamped that strip's procedural sample
to the boundary row and faded it over a coarser-source halo. It applied this
halo even where a neighboring strip of the same resolution fully covered the
coordinate. That overwrote valid two-dimensional terrain with an extruded
edge row and could move native measured posts. Reversing the strip order
could also change the result.

The correction prevents peer halos from overriding native coverage while
retaining genuine transitions to a finer source or a coarse fallback. Its 804
regression comparisons check combined strips against their native owners on
both sides of the overlap, at measured posts and fractional positions, for
512 m, 2 m and 0.125 m sampling in both strip orders.

The pre-fix fixture reports 4.523037985 m maximum measured-height error and
1.232929814 m residual error. The v2 resolver permits only strictly finer
halos above the fully covering owner. Both errors become exactly zero in
`/tmp/LM-Terrain-Bands-Final-Tests.xcresult`, which passes all 23 selected
tests across four suites. These are fixture errors, not measurements of the
previous live Highland landing. The corrected terrain can differ where the
old source selection violated native ownership, so this is a versioned
geometry correction as well as a visual repair. Contact continues to consume
the same corrected, submitted triangles as the renderer. The temporary raw
mesh probe was removed before the final build.

## Corrected source geometry control

The source-ownership control uses normal Release binary
`94a3ec1003850aaf7b5d7edd712a4023c1ccd5f379b42a53cc1baac5dfa0e2c5`.
`/tmp/LM-Terrain-Bands/Highland-Geometry-Final/05-0.5m.png` repeats the exact
low-Sun geometry control. Visual inspection confirms that the extruded-row
stripes and sharp source-strip band are gone. Craters and roughness continue
through the formerly clamped area. Coarser outer LODs remain visibly smoother;
this repair does not add measured resolution or densify the distant mesh.

| Matched geometry-only measurement | Original failed control | Final |
| --- | ---: | ---: |
| Tiles / source floor m | 38 / 236.901 | 38 / 236.901 |
| Generation ms | 13,562 | 13,118 |
| Worst startup frame ms | 274.95 | 178.92 |
| Whole-run reported misses | 6 | 5 |
| Frame-window peak MiB | 139.8 | 141.4 |
| Process lifetime peak MiB | 1,601.285 | 1,603.253 |
| Settled p95 / p99 / maximum ms | 16.67 / 16.67 / 16.67 | 16.67 / 16.67 / 16.67 |
| Settled reported misses | 0 | 0 |

`geometry-performance.json` and each directory's `metrics.json` retain the
PID-scoped data. The lifetime peak includes startup; frame-window and lifetime
measurements must not be substituted for one another. This comparison is a
measured run, not an isolated percentage performance claim.

## Neutral normal-map encoding

With corrected source ownership, the photographic low-Sun terminal capture
still exposed a narrow brightness boundary around the 0.5 m corridor.
`Highland-Photographic-Final/05-0.5m.png` retains that intermediate result.
`Highland-NoNormals-Final/05-0.5m.png` removes only normal maps and removes
the narrow boundary, retaining measured reflectance and shadows.

The coarse baker's flat-normal shortcut wrote `[128, 128, 255]`, while the
full baker truncates its neutral tangent components to `[127, 127, 255]`.
That mismatch tilts the decoded normals in opposite directions, making a
brightness step under grazing illumination. The shortcut now uses the same
`encode(0)` operation as the full baker. Relief scale, frequency filtering,
reflectance, and geometry remain unchanged by this appearance correction.

The new regression compares every shortcut texel against an exactly flat
corner produced by the full baker. All 31 tests in five suites pass in
`/tmp/LM-Terrain-Bands-Normal-Encoding-Tests.xcresult`: source resolution,
transitions, arrival, rendered contact, and detail streaming. The subsequent
normal Release build passes in `encoding-release-build.log`; its binary is
`8652cd4fb9408f9f3ee6aadff795b42c1e7492bc4c3f219c7a23bf6855e428d0`.

`/tmp/LM-Terrain-Bands/Highland-Photographic-Encoding/05-0.5m.png` repeats
the photographic terminal control with normal maps, shadows and measured
reflectance enabled. The narrow rectangular brightness step is gone on visual
inspection. The source-strip extrusion also remains absent. This accepts the
identified banding fixes in the fixed Simulator view; the outer LODs still
show their lower geometric resolution.

The same final directory includes the 2 m-altitude, 8 m-wide surface view
(`07-surface.png`). It retains continuous near-field detail; a distant coarse
facet is still visible at the upper left. Both captures settle for 90 seconds
after readiness, using the established camera and 120-hour Sun offset
(7.86634 degrees elevation, 278.80979 degrees azimuth). This is a controlled
renderer comparison, not a reconstruction of an Artemis photograph's camera.
`Highland-Calibrated-Encoding/05-0.5m.png` also passes visual inspection with
the default calibrated grade and zero Sun offset (44.00393 degrees elevation).
Every accepted global directory retains launch arguments, the PID, screenshot
hash and performance log; no heavy build or test overlaps these captures.

| Photographic measurement | Original terminal | Final terminal | Final surface |
| --- | ---: | ---: | ---: |
| Tiles | 38 | 38 | 54 |
| Generation ms | 14,585 | 13,836 | 20,927 |
| Worst startup frame ms | 270.55 | 285.73 | 271.23 |
| Whole-run reported misses | 4 | 4 | 4 |
| Frame-window peak MiB | 139.8 | 141.4 | 157.5 |
| Process lifetime peak MiB | 1,601.128 | 1,602.363 | 1,601.519 |
| Settled p95 / p99 / maximum ms | 16.67 / 16.67 / 16.67 | 16.67 / 16.67 / 16.67 | 16.67 / 16.67 / 16.67 |
| Settled reported misses | 0 | 0 | 0 |

`photographic-performance.json` retains the PID-scoped comparison, including
the intermediate source-ownership control. Startup hitches and memory
variation remain; these repairs do not establish a repeatable speedup.

## Apollo stability and item 0 comparison

The final Release binary completes all eleven stops in
`/tmp/LM-Terrain-Bands/Apollo-Final`, using the established 20-second Apollo
protocol with profiling. Every accepted PNG is byte-identical to
`/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2`; no attempt was rejected.
`baseline-comparison.json`, `accepted-metrics.json`, `profile-runs.tsv` and
`performance.tsv` retain the image checks and PID-scoped measurements.
The eleven pinned terrain assets also remain byte-identical to `c950d46`,
recorded in `/tmp/LM-Terrain-Bands/apollo-assets.json`.

| Apollo ladder measurement | Item 0 | Previous chunk | Final |
| --- | ---: | ---: | ---: |
| Frame-window peak MiB | 406.5 | 367.7 | 362.8 |
| Worst startup frame ms | 643.77 | 450.86 | 516.44 |
| Whole-run reported misses | 82 | 92 | 86 |
| Process lifetime peak MiB | unavailable | 1,602.957 | 1,602.597 |
| Accepted images identical to item 0 | 11 | 11 | 11 |

All final settled windows have p95, p99 and maximum 16.67 ms, with zero
reported misses. Startup timing varies in both directions relative to the
previous chunk. Tile generation ranges (ms) are terminal 324-342, landing
1,436-1,708, relief-start 1,795-2,073, relief-end 1,741-1,973 and surface
1,382-1,676. Item 0's corresponding ranges are 252-356, 1,471-2,043,
1,334-1,815, 1,390-1,882 and 1,351-1,819. These single-run measurements
do not isolate the banding fixes as a performance cause.

## Remaining acceptance

The identified source-strip and brightness bands pass the fixed low-Sun
Simulator comparison. Distant mesh faceting, publication hitches and memory
variation remain recorded limitations. No new P63-P65 flight was run in this
repair: contact and arrival regression suites passed, but the previous
Highland 15.84-degree crash result must not be presented as a new flight on
resolver v2. The landing envelope remains unchanged.

Physical Vision Pro validation remains required for stereo continuity,
head/hand interaction, frame pacing, memory/thermal behavior and display
brightness/EDR. Simulator captures cannot close those gates. The calibrated
grade remains the default; this repair does not promote the experimental
photographic grade.
