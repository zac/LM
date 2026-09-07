# Explorer source loading and terrain reuse

This follows the physical Release comparison in `MoonExplorerEntryAndImport.md`.
`LandAnywhereMoonPlan.md` controls geometry, provenance and acceptance. Evidence
for this work is in `/tmp/LM-Source-Rebuild-2026-09-06/`.

## Bounded source loading

The first device entry spent 24.042 seconds resolving sources. Independent
source slabs were awaited serially. Region loading now keeps at most four
requests in flight, retaining catalog order when resolving results. Every
request still uses the existing byte-range, size, digest and persistent-store
checks. One unavailable source retains the existing fallback behavior;
cancelling navigation cancels the batch and its outstanding requests.
The standalone resumable Download Region operation is unchanged.

Release visionOS 26.5 Simulator validation passed 19 tests with no failures or
skips in `Sources-Retry.xcresult`. New tests cover bounded concurrent requests,
out-of-order completion, catalog-order results, partial failure, offline cache
reuse, empty input and cancellation without publishing partial products. The
initial Release test build lacked testability; the passing retry explicitly
sets `ENABLE_TESTABILITY=YES`. Source/post/seam tests also pass. No source data,
source ordering or sampling arithmetic changed in this item. A fresh physical
source-load timing remains to be measured; four requests do not imply a
fourfold speedup on every network.

## Resident surface return

An unchanged global destination now resumes its existing published terrain.
The region must have complete source coverage, the same anchor, presentation
grade and detail mode, and exactly the requested regional tile plans. An
unfinished registration or morph cannot be reused. Changed destinations or
plans take the normal rebuild path. Existing entities and contact snapshots
stay resident; this adds no second region or persistent mesh cache. Arrival
animation and subsequent LOD refinement still run normally.

The owner repeated Globe → Surface on the physical Vision Pro in Release.
`device-console.log`, PID 1993, records the first 16-tile construction at
7,557 ms and the unchanged return at `generation=0ms`, with all 16 tiles reused.
This removes the prior 7,576 ms repeat construction; zero denotes no geometry
work, not zero animation or compositor latency. Source resolution was warm
at 115.997 ms, so it does not measure the cold-source improvement. This device
binary predates the final prepared-normal sampling change below.

## Repeated spherical samples

Global mesh preparation now uses a temporary cache keyed by the exact Double
bits of east, north and requested spacing. Each preparation holds at most
16,384 entries and discards them after mesh construction. FIFO eviction changes
only computation cost. Vertex sampling, measured normals and residual slopes
share the prepared field. The four-iteration spherical solve and all sampling
arithmetic remain unchanged. Apollo's field follows its original code path.

The initial experiment cached vertices alone and did not improve the device's
7.6-second build. Inspection found the normal loop still using the original
field. Routing global normal calculations through the same prepared field
produced the following Release Simulator regional comparison at 0°, 0°:

| Phase | Original | Prepared sampling |
| --- | ---: | ---: |
| CPU mesh preparation, 16 tiles summed | 4,228.241 ms | 3,447.143 ms |
| Mesh imports, 16 tiles summed | 35.378 ms | 34.746 ms |
| Terrain construction | 4,999 ms | 4,249 ms |

This is an 18.5% reduction in CPU mesh preparation and 15.0% in construction
for this pair, not a universal speedup. Source timing is excluded: the control
fetched sources and the candidate reused them. Both use the same Release
configuration, coordinate, altitude 9,999 m and 24 km width. Compilation began
after candidate construction, overlapping its later settled interval; that
interval is not a clean steady-state performance measurement.

`Global-Control/03-8m.png` and `Global-Final/03-8m.png` are byte-identical after
the established 90-second wait, SHA-256
`868b1c40b67d541e04a8d767f8d9e4f9e27336026a26afba423c4c0da9709a2e`.
The control is the frozen original Release app from
`/tmp/LM-Entry-Import-2026-09-06/Final.app`. This default-coordinate view is
flat and dark on inspection, so matching it alone cannot accept global normal
or seam appearance; the detailed Highland comparison below supplies that check.

## Mesh LOD

Terrain already uses nested clipmap LODs. The default regional view contains
16 tiles across 512, 128, 32 and 8 metre vertex spacings. Moving closer adds
2 m, 0.5 m and 0.125 m geometry. Parent coverage, edge transitions and contact
sampling follow the published mesh. These spacings describe geometry density;
they do not imply measured elevation sources at each resolution.

## Validation and remaining gates

`Final-Rebuilding.xcresult` passes 34 Release tests (37 parameterized executions),
zero failures and zero skips. Coverage includes exact mesh positions, normals,
tangents, bitangents, UVs and indices against the uncached field; mixed-spacing
cache eviction; repeated resident entity identity; rejection of a different
LOD; contact, floating-origin, ownership/cache and navigation regressions.
Together with the separately validated source item, 53 distinct tests pass.
The earlier test run's Simulator shell retry is retained in the evidence;
`final-rebuilding-summary.json` records the final passing run.

Both ordinary Release builds pass. Binary SHA-256 values for the final code:

- visionOS device: `84c4739ffc11911dcefa8bbbd34ea8a55033be41a8304cb8fe3b363fc935c34f`
- visionOS Simulator: `56d7f939948b31cb102f97dc45a3189ff75a185bbab86f46dee06c6ffc2dc70b`

The two pre-existing scheme-user edits are preserved byte-for-byte; this work
does not modify AGC, elevation assets, residual caps, source provenance or the
pending texture companion budget. Fresh-cache physical source timing, texture
peak reduction, compositor frame timing, 90 Hz surface performance, thermal
behavior and a longer headset soak remain open.

## Final physical Release check

With owner approval, the final build was installed and launched as PID 2003.
The opt-in reentry probe uses the production navigation actions at the default
0°, 0° coordinate. `final-device-console.log` and `final-device-phases.json`
record 6,064 ms of first construction, including 5,527.949 ms summed CPU mesh
preparation, 32.540 ms summed mesh imports and 0.179 ms atomic publication.
The earlier physical Release construction was 7,581 ms with 6,866.086 ms CPU
mesh preparation: this pair improves construction by 20.0% and CPU preparation
by 19.5%. It is one short comparison, with source caches warm and observed
display refresh different, not a controlled thermal or sustained-frame study.

Warm source resolution is 131.079 ms. The unchanged second entry logs all
16 tiles reused at `generation=0ms`, without another source interval or mesh
import. Surface callback windows still include 20 ms at an adaptive nominal
20 ms; this cannot establish 90 Hz rendering. Texture startup still dominates
the lifetime memory peak, and transition callback gaps remain even when terrain
is reused. These changes address source scheduling and CPU construction;
they do not close those separate performance gates.

The automatic check completed with `Moon reentry passed first=6064ms second=0ms
tiles=16 sourceExact=true`, verifying unchanged source description, measured
floor and active tile count after both settled arrivals. Physical footprint at
the two settled checkpoints was 374.9 and 376.5 MiB (1.6 MiB difference); this
short pair is not a leak test. The lifetime peak was 2,188.7 MiB. Profiling was
then stopped and the improved Release app reopened without automatic navigation.

## Apollo acceptance and item 0 comparison

`Apollo-Final/` contains all eleven accepted fixed-camera stops; each PNG is
byte-identical to `/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2/`. Captures use
the established 20-second Apollo repeat protocol with no overlapping builds or
tests. The final five-second callback window has p95/p99/max 16.67 ms at every
stop, with no reported missed callbacks. Item 0 also had 16.67 ms p95/p99 at
every stop, with occasional 22.22 ms maxima. These are Simulator observations.
Final-window footprints span 304.4–361.8 MiB, versus item 0's 311.5–380.8 MiB;
that historical difference includes earlier improvements and is not attributed
to this change. `apollo-performance.json` retains the per-stop values.

`Highland-Final/05-0.5m.png` repeats the accepted calibrated terminal view at
−42°, 120°, altitude 249 m and width 700 m. It settles 90 seconds after all
38 tiles are ready, with no overlapping builds/tests, and is byte-identical to
`/tmp/LM-Terrain-Bands/Highland-Calibrated-Encoding/05-0.5m.png`, SHA-256
`7f33a3b768e2b68d14d46b20f1ff24371f97a6cab33e76a40501246c8c0ef7cd`.
Visual inspection retains the accepted crater/normal relief and transition
appearance. All required image comparisons pass; no new visual change is
accepted or requested by this optimization.
