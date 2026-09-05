# Stage 2 global terrain validation

This record supplements the controlling `LandAnywhereMoonPlan.md`. Implementation
and numerical checks are separate from visual and mission acceptance. The global
path is not yet accepted as a seamless globe-to-surface experience.

## Item 4: source ownership and amplification

The production Explorer accepts `--lunar-explorer-coordinate=latitude,longitude`.
The original Apollo pack keeps its planar evaluator, source bytes and default
presentation. Global regions resolve an immutable source set before generating
geometry. Network completions cannot silently upgrade an active region.

The global measured floor is bundled LOLA LDEM_16 (about 1,895 m). Pinned LOLA
LDEM_128 V3.0 strips provide about 236.901175 m posts everywhere; the existing
SLDEM2015 slab provides about 59.2 m where its actual downloaded coverage applies.
Normalized WAC EMP 643 nm is the only streamed reflectance input. Missing
reflectance uses a declared uniform model. WAC morphology is confined to the
unlit globe. The Apollo-only neural model is not applied to global geology;
validated N3 conditioning remains outstanding.

`pin_lola_strips.py` verified the complete 2,123,366,400-byte LDEM_128 raster before
pinning 720 overlapping strips. The full raster stays in the ignored generator
cache. Each transport range has at most 34 rows (3,133,440 bytes); neighboring
ranges share two native rows. Latitude arithmetic uses the original raster row
origin, giving bit-identical overlap samples rather than strip-local rounding.

- Image SHA-256: `0ab81a3e8d20e5528a21bc6c994974726cb486198013085f4c423c86fbd1154b`
- Label SHA-256: `85b1901def6901ee8a50415384f17a71e773af2d979beb7245fd6ac4d5e1671b`
- Strip catalog SHA-256: `3cb3fa9507cfe174ae0c0698a684f4c3704b507b6213b0d78a2c6ac6ab303181`
- Source: <https://imbrium.mit.edu/DATA/LOLA_GDR/CYLINDRICAL/IMG/LDEM_128.IMG>

The label explicitly documents latitude-band artifacts at 45-degree boundaries
and interpolation in measurement gaps. Those limitations remain part of the
source provenance. Smoothing them away would change the measured-post contract.

The versioned residual is `lunar-source-anchored-octaves-v1`: fixed Moon-centered
projections extend the existing crater morphology through 1/4/16/64 scale factors,
up to 76.8 m diameter. Subtracting the bilinear combination of native-post model
values makes the residual exactly zero at owned measured posts. The source's
own cap ratio controls the bounded residual; it is not a global hard-coded cap.
Tests include a non-default 0.03 ratio as well as the approved 0.12 ratio.
The crater-size extension follows the small-crater regime discussed in
<https://ntrs.nasa.gov/citations/19800068354>; it does not claim every lunar region
has Surveyor's measured crater abundance or geological history.

The existing planner/baker supports 512/128/32/8/2/0.5/0.125 m meshes globally.
Each child reads the actual submitted parent triangles, including its parent's
morph collar. A complete generation publishes together. CPU copies of those
vertices supply contact. Tile centers are subtracted in Double before Float
conversion, and each chunk is placed directly in the active ENU. A bounded
per-region post-value cache improves source sampling without changing values.

The 210 km handoff originally intersected the globe because a 1 cm foreground
offset cannot contain kilometer-scale relief. A bound over the submitted region
now applies a homothety about the eye to move the full region ahead of the globe,
preserving every monocular projected point. This requires stereoscopic comfort
validation on physical Vision Pro.

## Numerical and Simulator evidence

All runs use visionOS Simulator UDID `8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`.
Global captures wait for the production geometry-ready event and then settle
at least 90 seconds. The later Apollo item 0 comparison retains its matched
20-second attribution protocol, as documented below. Tile tint, normal-map-off
and shadow-off controls are diagnostics, not acceptance images.

- `/tmp/LM-Stage2-Resolver-Triangles-v2.xcresult`: 16 resolver/elevation tests
  passed. The 100-sample spherical graph probe had maximum radial error
  0.000052729854 m; its cached kernel took 0.021786333 s versus 0.147372334 s
  before post memoization. Parent-edge height and normal error were both zero.
- `/tmp/LM-Stage2-Global-Geometry-v5.xcresult`: 20 resolver, floating-origin and
  existing landing tests passed. Distant chunks at 50–64 km, with 4.2 km
  re-anchors, had worst Float presentation error 0.000905842703 m (under 1 mm).
  The foreground-bound test preserves every projected corner and bounds depth.
- `/tmp/LM-Stage2-Item4-Apollo-Control/`: Globe and Surface PNGs are byte-identical
  to item 0. Settled p95/max were 16.67 ms, zero missed frames. Physical footprint
  was 305.9/381.0 MiB; the item 0 Globe/Surface values were 312.2/368.6 MiB.
  Surface tile builds were 1260–1671 ms. This run does not cover all eleven stops.
- `/tmp/LM-Stage2-Global-Depth-Corridor/`: highland point −42°, 120°, final
  near-field and bounded-depth handoff controls. The globe intersections are
  removed. A coarse triangular patch remains visible at the edge. Its initial
  near-field interpretation is revisited by the later ownership probe.
- `/tmp/LM-Stage2-Global-Tile-Control/` and
  `/tmp/LM-Stage2-Global-Geometry-Control/`: tile tint identified the visible
  surface as a terminal parent; disabling shadows and normal maps did not remove
  it. Widening the fine view corridor reduced but did not eliminate the artifact.
- `/tmp/LM-Stage2-Global-Coarse-Ladder/`: highland 128/32/8 m and handoff captures.
  Their generation times were 5653/3479/4907/6899 ms. These precede the final
  depth-bound fix and must not be presented as accepted final handoff images.
- `/tmp/LM-Stage2-Item4-Offline-Reanchor/`: an offline production region and
  before/after capture of the actual re-anchor trigger, with no geometry rebake.
  The final per-frame and image-difference results are recorded below.

The stability follow-up below completes the Apollo/mare/highland ladders and
revisits the suspected near-field intrusion using submitted-triangle rays.
Open gates remain temporal band-arrival continuity, site-specific handoff
radiance at arbitrary locations, global source-join visual acceptance, N3
geology conditioning, and physical Vision Pro frame timing, memory, stereo
depth and gesture comfort. No acceptance threshold has been relaxed.

## Item 5: rendered contact and simulation frames

Global `LMTerrainContactSurface` queries the exact published triangle snapshot,
including parent morphs, without resampling. The existing Apollo contact patch
now uses the mesh triangle diagonal rather than bilinear interpolation of a
four-post saddle. Apollo source data and rendered geometry are unchanged.
`LMLunarLandingRehearsal` runs the actual LMCore crushable gear solver against a
frozen generation. It is a local drop diagnostic, not a full AGC mission.

`/tmp/LM-Stage2-Items456-Validation.xcresult` and its `.log` pass 117 tests across
13 suites in 190.828 seconds on visionOS 26.5 Simulator. These include the ten
baseline suites plus resolver, global contact and navigation coverage. At
8.35°, 30.83° and −42°, 120°, 2,000 contact queries have zero error against the
submitted triangles. Gear settles after 2.53 and 5.63 seconds respectively,
without strut failure or penetration beyond the solver's bearing allowance.
Those two automated drops use the bundled base; streamed production drops are
recorded separately under Item 6.

Inspection disproved the plan's assumption that spherical altitude alone made
the AGC frame arbitrary-site ready. RLS, RN/VN initialization, REFSMMAT, the
plant basis and LR geometry also referenced Apollo's site. The authorized AGC
branch `terrain-anchor-guidance` adds an explicit immutable landing-site context
and rejects cross-site checkpoints before changing AGC or vehicle state. Nil
context preserves the original NASA pad construction and old recording JSON.
Custom scenarios start P63 from a modeled retargeting of Apollo PDI conditions;
they cannot reuse Apollo P64/P65 checkpoints.

The AGC working-checkout run `/tmp/AGC-Lunar-Anchor-v6.log` passes 86 tests across
site, landing-radar and scenario/dynamics suites. `/tmp/AGC-Lunar-Anchor-v7.log`
passes five site tests, including a custom P63 → P64 → P65 descent to a sphere
at 8.35°, 30.83°, radius 1,735,000 m. It reports `softLanding` at simulation time
825.570374 s. Encoded RLS and RN errors are at most 0.308361 and 0.364937 m,
within the derived sqrt(3) × 0.25 m bound for B27 double-precision quantization.
A separate staged-tree test excludes the owner's pre-existing AGC edits.

The full cockpit still selects Apollo 11. Wiring a custom AGC run to a changing
rendered region requires a pause/publish transaction for contact and geometry,
then complete cockpit descent captures. The local drop and custom sphere test
do not close that gate. Item 5 therefore has a validated contact implementation
and AGC frame prerequisite, with mission integration outstanding.

## Item 6: navigation and region controls

The Explorer panel now has coordinate entry and copy, a searchable catalog
grouped by category, fly-to history, return to Apollo 11, measured-floor and
modeled-relief disclosure, cached-only reload, region download/pause controls,
and the local landing diagnostic. Catalog version 1 has the twelve requested
USGS natural features and six Apollo landing sites. Each entry records its
source; suggested view settings are explicitly application defaults. Apollo 11
uses the exact manifest anchor, including height, rather than substituting the
nearby LROC LM position. The other Apollo coordinates come from the published
2016 LROC coordinate table. No additional downloaded site pack is bundled.

Fly-to eases out to the globe, follows the short great circle, prepares a
regional mesh, then eases in. Pole and antipodal cases have deterministic
finite paths. One globe atlas remains resident across destinations; geographic
rotation changes its frame. A synchronous state read in RealityView's loading
path keeps later camera and contact actions observable. The global view centers
the selected coordinate; Apollo keeps its established capture framing.

The source region remains immutable while viewed. Local pan is bounded to
20 km inside the prefetched region; use fly-to to change regions. This is not
yet continuous great-circle globe dragging. The 128 MiB cache retains verified
sources and may evict old regions; download is not a permanent offline pin.
The controls say this explicitly. Existing cache tests cover transport,
coalescing, cancellation, eviction and offline reuse; UI button activation is
not itself covered by those tests.

The landing diagnostic freezes one visible generation and runs the real gear
solver. Its simple body and pad markers are inspection aids. Their unlit
materials remain visible on lunar night terrain; they are not mission vehicle
appearance. The cockpit continues to select Apollo 11.

### Measured results and failed probes

- `/tmp/AGC-Lunar-Anchor-Commit-Validation.log`: all five site tests pass in
  248.704 s in an isolated staged-tree export without the pre-existing AGC
  gear/pad-load edits. This independently validates AGC commit `65d5b99`.
- `/tmp/LM-Stage2-Items56-Final.xcresult`: 22 tests in three suites pass after
  the navigation/triangle-contact changes. A later final run is recorded below.
- `/tmp/LM-Stage2-Global-Mare-Ladder/`: all eight production stops at
  8.35°, 30.83° have settled p95/p99/max 16.67 ms and zero missed callbacks.
  Generation times for 128/32/8/2/0.5/0.125 m, Surface, and handoff were
  4918/3102/4155/5541/11763/18523/18566/6741 ms. Settled footprints were
  144.4/113.7/116.9/122.4/243.2/158.9/177.5/126.5 MiB. The complete ladder was
  inspected. Coarse posts remain visibly smooth, and the 0.5 m view exposes a
  rectangular fine-detail footprint. These precede the coordinate-centering
  correction and are not final framing controls.
- `/tmp/LM-Stage2-Item4-Offline-Reanchor/image-metrics.json`: RGB normalized
  RMSE is 0.0000348843; the largest mean linear-radiance change across fifteen
  fixed 2880×32 pixel bands is 0.000102949%. This compares identical stationary
  footprints before/after the production re-anchor, with no rebake. It does not
  measure a source-boundary seam or validate arbitrary-site handoff radiance.
- `/tmp/LM-Stage2-Navigation-Contact-Capture/`, PID 28576: failed arrival probe.
  The view remained on the globe and no contact ran. Navigation-window memory
  peaked at 880.7 MiB with a 167.13 ms maximum frame and 12 missed callbacks.
- `/tmp/LM-Stage2-Navigation-Contact-v2/`, PID 37020: corrected state observation
  and atlas reuse. Navigation-window peak was 158.1 MiB, maximum frame 36.27 ms,
  seven missed callbacks. The streamed highland drop settled in 5.23 s. Its
  diagnostic was offscreen under the old view framing, so this is numeric
  contact evidence rather than a visible-pad acceptance capture. Settled p95
  and max were 16.67 ms, zero missed callbacks, 285.6 MiB. Across startup and
  all terrain generation in that process, the maximum frame was 255.15 ms.
- Xcode's controls preview request timed out. This is an unavailable preview,
  not a successful UI check. The final production Simulator captures below
  provide the available visual evidence.

The unchanged settled 60 Hz Simulator callback rate does not establish the
physical Vision Pro 90 Hz budget. Startup/generation hitches and global visual
joins remain acceptance failures. No threshold was relaxed.

### Final navigation capture and bundle accounting

`/tmp/LM-Stage2-Items56-Final-v2.xcresult` passes all 22 tests in three suites
in 10.064 s. Xcode BuildProject and the Release Simulator build also pass.
The last small error-recovery and close-button adjustment has an additional
successful build. The default Apollo path is still selected by the existing
mission entry points.

`/tmp/LM-Stage2-Navigation-Final/` records the final centered view, PID 45064,
with actual-source readiness followed by 100 s before each automated action.
`mare-before-flight.png` and `highland-contact.png` are settled captures;
`fly-to.mov` records the complete transition. Extracted motion frames were
inspected. The destination's regional generation took 6956 ms, and the final
54-tile contact generation took 19343 ms. The local drop settled after 5.23 s.
The final image includes the diagnostic body and visible pad marker; it does
not establish visibility of all four pads or replace a cockpit landing review.
Coarse near-field geometry remains visible toward the edge of the highland view.

With video recording active, the observed navigation-window peak was 286.5 MiB,
maximum frame 52.84 ms and 12 missed callbacks. Across the entire process the
maximum frame was 306.15 ms. The final settled window returned to p95/p99/max
16.67 ms, zero missed callbacks and 247.4 MiB. Video recording and concurrent
host work differ from the earlier non-recording control; neither is a physical
headset measurement. `metrics.json` retains the PID-filtered measurements.

`Tools/CaptureLunarNavigation.sh` reproduces the sequence using caller-supplied
start/destination coordinates and a fresh output directory. It checks the live
PID, waits for geometry, records fly-to, requires a settled contact outcome,
and waits another 90 s before the final screenshot. This harness is for known
safe validation points; a real sloped-site crash should remain a failure.

The new offline raster, both provenance labels, strip catalog and POI catalog
total 33,244,624 bytes, or 31.704544 MiB. No LDEM_128 raster is bundled. All eleven
original terrain resources other than the intentionally extended manifest are
byte-identical to `c950d46`; both unrelated scheme-user files retain their
pre-session hashes. The owner's AGC pad-load and gear files retain their hashes,
and its pre-existing gear integration helper is unchanged.

`/tmp/LM-Stage2-Items56-Apollo-Final/` completes the matched Terminal and Landing
controls. Both PNGs are byte-identical to item 0. Settled p95/p99/max remain
16.67 ms with zero missed callbacks. Footprints are 337.5/374.2 MiB versus the
baseline's 336.5/380.8 MiB. Tile completion ranges are 281–377 ms at Terminal and
1316–1703 ms at Landing. Together with the earlier Globe/Surface controls, these
cover the four requested attribution points, not a new complete eleven-stop run.

`/tmp/LM-Stage2-Navigation-Panel/controls.png` captures the production panel after
90 s of settled geometry. Coordinate −42°, 120°, 237 m source spacing, modeled
relief disclosure, grouped POIs, download/reload and landing controls are visible.
The Simulator AX tree exposes its wrapper rather than individual visionOS form
controls. Two coordinate-click/typing attempts did not activate the search field;
keyboard capture was restored. Search/button activation is therefore unverified
through UI automation, despite the parser/catalog tests and session-action
capture passing. Do not report the screenshot as a complete interaction test.

Final source check: `/tmp/LM-Stage2-Items56-Commit-Validation.xcresult` passes
all 22 tests in three suites in 9.942 s, including the last error-recovery and
close-control adjustment. `LM-Stage2-Items456-Release-v10.log` is the final
successful Release build. The navigation movie/contact images use v9; v10 adds
only error-path recovery and keeps Done enabled while other controls are busy.
No terrain generation or presentation geometry changed between those builds.

## Transition stability follow-up

The opt-in performance probe now records source resolution, verified source
decoding, CPU mesh work, appearance baking, mesh upload, material upload, and
complete-generation publication. Begin/end records retain overlapping work;
their durations must not be added as if they were serial latency. The atlas
interval includes an asynchronous texture load and is not main-thread occupancy.
`Tools/SummarizeLunarTerrainTiming.py` groups these records by live process ID.

The unchanged-geometry Release control is
`/tmp/LM-Stage2-Stability-Before-Highland/`, at −42°, 120°. At the 0.5 m stop,
38 tiles took 13,191 ms. Source resolution took 77.8 ms on a worker. Mesh
uploads peaked at 3.45 ms and material uploads at 9.72 ms on the main thread;
publication took 1.33 ms. Synchronous terminator creation took 140.4 ms during
a startup window whose maximum frame was 250.14 ms. The surface repeat measured
140.9 ms for the terminator and 1.69 ms for publication; 54 tiles took 19,248 ms.
These measurements motivate moving CPU globe preparation off the main thread.
They do not attribute the entire delayed frame to one phase or accept the
visible coarse-parent patch. Both captures use readiness plus 90 seconds and
the existing production source cache, without video recording.

Globe mesh buffers and the decoded terminator normal field/opacity image now
prepare on worker tasks. Resource realization stays on the main actor, with
cancellation checked before publication and the requested sun date retained
across suspension. `/tmp/LM-Stage2-Stability-CPU.xcresult` passes 29 tests in
two suites, including exact opacity bytes, unchanged globe vertices, and
cancelled preparation. Xcode BuildProject and Release Simulator builds pass.

The matched `/tmp/LM-Stage2-Stability-Async-Highland/` PNGs are byte-identical
to both before controls. Worker terminator preparation takes about 80 ms;
globe mesh uploads take about 3.5 ms. Whole-run maximum frames changed from
250.14/382.96 ms to 240.44/125.38 ms for the terminal/surface launches, while
missed callbacks increased from 17/24 to 23/31. These are two launch pairs,
not evidence that startup hitches are solved. Both late settled windows retain
16.67 ms p95/p99/max with zero missed callbacks. Settled footprints changed
from 137.6/157.6 MiB to 142.5/158.4 MiB. The async atlas upload and resource
arrival still need attribution; background execution alone is insufficient.

The expanded shared-terrain run found an existing coarse-bake statistics
regression in `/tmp/LM-Stage2-Stability-Shared-Terrain.xcresult`: the flat-normal
shortcut reported one sample for a 64×64 texture. Two assertions in
`bakedNormalDistributionCanBeReusedForAnySunDirection` failed; 63 other tests
passed. The shortcut now reports all texels in the flat histogram without
changing texture bytes. This preserves correct weighting in ensemble checks.
The final `/tmp/LM-Stage2-Stability-Final.xcresult` passes 155 tests across 16
suites in 177.999 seconds, including the previously failing assertions.

### Oblique footprint continuity and ownership

A 0.2 m refinement over a flat parent exposes a stepped-footprint defect:
one tile can finish its edge collar at an internal corner while its neighbor
retains full refinement. `/tmp/LM-Stage2-Stability-Collars-Before.xcresult`
fails shared-edge checks at headings 17°, 35° and 135°. Global planning now
closes each level into a rectangle and encloses the quantized child bounds
inside the parent's collar before assigning perimeter edges. Apollo planning
is unchanged. At headings 0/17/35/90/135°, tile counts change from
54/71/75/54/78 to 54/82/95/54/100. This extra residency is a measured cost of
using the existing edge-only collar representation; it is not free prefetch.

`/tmp/LM-Stage2-Stability-Collars-After.xcresult` passes eight tests in three
suites. The four transition tests also pass in the final 155-test run: shared
edge heights are exactly equal at all five headings, appearance edge bytes
match, an inspection ray respects missing submitted triangles, and cancelling
a generation permits an identical request to retry without publishing it.
Release build evidence is `/tmp/LM-Stage2-Stability-Final-Release.log`.

The capture-only ownership probe intersects the actual submitted triangles.
In `/tmp/LM-Stage2-Stability-Ownership-Highland/`, eight of nine nominal rays
hit the 0.125 m level and agree with the vertical contact owner. The upper-left
ray hits the 128 m level about 7,054 m away; it does not demonstrate a coarse
parent piercing the foreground. These rays assume a nominal 1.45 m eye and
inspection projection, not a calibrated mapping from screenshot pixels.
The earlier description of this particular patch as near-field intrusion is
therefore unproven. Distant footprint joins and the complete visual acceptance
gates remain open until the final captures are assessed.

### Final highland ladder and texture-upload tradeoff

`/tmp/LM-Stage2-Stability-Final-Highland/` contains all nine production stops,
including the whole globe. All nine final settled windows have p95/p99/max
16.67 ms and zero missed callbacks. No video or Xcode build/test ran during
these captures. Both terminal and surface PNGs are byte-identical to the
unchanged-geometry before controls. The inspected ladder still shows smooth
coarse terrain and distant rectangular transitions; equal pixels establish
continuity of this change, not global appearance acceptance.

| Stop | Generation ms | Settled MiB | Whole-run maximum frame ms | Whole-run missed callbacks |
| --- | ---: | ---: | ---: | ---: |
| Globe | 4,844 | 116.8 | 220.78 | 4 |
| Crossfade | 7,368 | 125.9 | 158.78 | 5 |
| 128 m | 6,200 | 122.0 | 166.78 | 5 |
| 32 m | 3,801 | 111.8 | 220.15 | 4 |
| 8 m | 5,351 | 116.2 | 239.75 | 4 |
| 2 m | 6,895 | 121.3 | 485.91 | 4 |
| 0.5 m | 13,948 | 140.8 | 204.98 | 4 |
| 0.125 m | 20,493 | 158.1 | 237.27 | 5 |
| Surface | 20,566 | 157.1 | 156.30 | 6 |

Detail albedo and normal textures now use RealityKit's asynchronous image
initializers, followed by a cancellation check before entity publication.
Their elapsed upload intervals include suspension and are not main-thread
occupancy. Relative to the before terminal/surface controls, generation takes
757/1,318 ms longer, while whole-run missed callbacks fall from 17/24 to 4/6.
The intervening worker-only control measured 23/31 missed callbacks. These
single-launch comparisons support the responsiveness tradeoff but do not
establish a statistically stable gain. The maximum surface publication interval
is 1.85 ms; its individual mesh uploads peak at 3.25 ms. Startup stalls remain.
The 485.91 ms event occurs during initial globe setup, before source resolution
or terrain generation starts, so it is not attributed to a terrain tile bake.

After the ninth highland screenshot and hash record, the capture shell emitted
an EOF parse error because its source file had been edited while it was running.
All nine PNG hashes and PID-scoped complete settled records were verified after
this error. The corrected script passes `bash -n`; subsequent captures use that
fixed script. This is a capture-script failure after the completed ladder, not
an app failure or evidence that an unfinished capture passed.

`/tmp/LM-Stage2-Stability-Final-Mare/` completes the same nine-stop ladder at
8.35°, 30.83°. Every settled p95/p99/max is 16.67 ms with zero missed callbacks.
Both regions report a 236.901175 m focus source floor and zero missing requested
sources; this is a regional terrain comparison, not a finer SLDEM source test.
All mare images were inspected. Near-surface foregrounds are continuous in the
static views, while wider views still expose the extent of added fine detail.

| Stop | Generation ms | Settled MiB | Whole-run maximum frame ms | Whole-run missed callbacks |
| --- | ---: | ---: | ---: | ---: |
| Globe | 4,377 | 118.1 | 233.37 | 5 |
| Crossfade | 6,710 | 127.3 | 145.31 | 4 |
| 128 m | 5,597 | 121.9 | 257.31 | 4 |
| 32 m | 3,396 | 113.2 | 165.72 | 7 |
| 8 m | 4,696 | 116.8 | 219.32 | 4 |
| 2 m | 5,846 | 121.8 | 128.26 | 5 |
| 0.5 m | 12,444 | 141.4 | 137.01 | 6 |
| 0.125 m | 18,366 | 157.7 | 123.72 | 5 |
| Surface | 18,278 | 158.2 | 274.55 | 4 |

### Complete Apollo baseline regression

`/tmp/LM-Stage2-Stability-Final-Apollo/` repeats all eleven item 0 stops with
the same 20-second launch protocol. Every PNG is byte-identical to
`/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2/`. Every final settled window has
16.67 ms p95/p99/max and zero missed callbacks. Baseline maximum settled frames
were 22.22 ms at Orbit, Terminal and relief-blend start, and 16.67 ms elsewhere.
The original terrain assets also remain byte-identical to `c950d46`.

Settled physical footprints at Globe/Terminal/Landing/Surface are
305.2/325.7/349.2/362.9 MiB, versus 312.2/336.5/380.8/368.6 MiB in item 0.
Across all stops, the largest sampled footprint is 364.1 MiB, versus 406.5 MiB.
The worst startup frame is 578.65 ms, versus 643.77 ms. These matched launch
runs do not establish headset performance or a repeatable percentage gain.
Terminal tile completion ranges are 324–354 ms, versus 252–356 ms; Landing
ranges are 2021–2234 ms, versus 1471–2043 ms. As in the global comparison,
asynchronous resource creation can trade some arrival latency for fewer
blocking intervals. `baseline-comparison.json`, `performance.tsv` and
`metrics.json` retain the complete per-stop evidence. The 90-second global
readiness protocol and 20-second Apollo attribution protocol are deliberately
reported separately.

### Boundary diagnostic corrections

The seven global levels need stricter ownership masks than Apollo's original
two-color diagnostic. That broad classifier also counted distant L4/L5 pixels
as terminal/landing. A first strict classifier assumed input HSV survived the
unlit render unchanged. `/tmp/LM-Stage2-Stability-Highland-Tint/radiance.json`
records that failed attempt with empty bands and NaN values; it is invalid
acceptance evidence. The Simulator output has terminal hues 32–33 and landing
hues 79–80, while the other green L5 has hue 68 on the same 0–255 scale.

The global classifier now uses disjoint bands that include the observed output
and original input colors while excluding the other levels. Four Python tests
cover all seven input colors, captured output colors at all three landing parity
brightnesses, empty interiors, and separated regions without an adjacent edge.
Empty measurement bands now raise an error. The existing 16-pixel erosion,
8–30 pixel boundary depth, 80-pixel adjacency distance, luminance formula and
1.5% acceptance limit are unchanged. This calibration is Simulator evidence;
a different capture color pipeline needs its own palette check.

The corrected highland surface result is +0.4394% calibrated, +1.0561%
photographic and +0.4653% with normal maps off. There are 49,221 terminal and
39,175 landing boundary pixels. These results are in
`/tmp/LM-Stage2-Stability-Highland-Tint/radiance-corrected.json`.
The completed constant-reflectance/no-normal control measures +0.2679%.
All four matched controls are below the unchanged 1.5% adjacent-boundary
limit. `radiance-all-controls.json` in that directory records the full set;
the constant control is in
`/tmp/LM-Stage2-Stability-Highland-Constant-NoNormals/`.
The mare surface tint contains only landing tiles. Its failed measurement is
correctly rejected; a same-view surface image cannot establish a boundary pass.

The mare control therefore uses the existing Landing stop, at 24.5 m altitude
and 40 m width. Its tint has 62,362 terminal and 65,354 landing boundary pixels.
The measured step is -0.0394% calibrated, -0.1294% photographic and -0.0939%
with constant reflectance and normals disabled. All three satisfy the unchanged
1.5% limit without a material gain. The matched set and results are in
`/tmp/LM-Stage2-Stability-Mare-Landing-Tint/radiance-all-controls.json`,
`/tmp/LM-Stage2-Stability-Mare-Landing-Photographic/`, and
`/tmp/LM-Stage2-Stability-Mare-Landing-Constant-NoNormals/`; the calibrated
image is `06-0.125m.png` in the complete mare ladder. All controls were inspected.
These highland and mare measurements accept the sampled terminal/landing
boundaries only. They do not extend to every global LOD or the globe handoff.

### Fully hidden parent resource failure

The first production 35° capture, `/tmp/LM-Stage2-Stability-Oblique/`, failed
before publication. Its screenshot is a flat fallback, not terrain acceptance.
The rectangular footprint can fully cover a parent tile with children, leaving
an empty submitted index list. RealityKit rejects that upload with
`.geomMeshFailure`. The numerical collar tests did not exercise this resource
boundary. The new focused test reproduces the error in
`/tmp/LM-Stage2-Stability-HiddenParent-Before.xcresult` and passes in
`/tmp/LM-Stage2-Stability-HiddenParent-After.xcresult` after the fix.

A fully hidden parent now keeps its CPU vertices and samples, which its children
need for hierarchical morphing, and carries an empty `ModelEntity` without a
render mesh. Non-empty tile realization is unchanged. The regression test checks
both absence of a render component and continued parent sampling. Generation
errors now enter the log explicitly, allowing the global capture script to fail
promptly instead of waiting ten minutes for a readiness event that cannot occur.
Xcode's first test-tool call timed out, but the copied result bundle established
the actual failure; the corrected focused run passed through Xcode MCP.

`/tmp/LM-Stage2-Stability-Final-v2.xcresult` passes all 156 tests in 16 suites
in 185.609 s, including the new RealityKit regression. The final optimized build
is `/tmp/LM-Stage2-Stability-Final-Release-v2.log`. Its executable SHA-256 is
`19c330908cc8c9f4d02066c0ce3217f80947069acd821484125a21c2886bd023`.
`/tmp/LM-Stage2-Stability-HiddenParent-Apollo/11-surface.png` is byte-identical
to item 0 after this last fix; its settled callbacks are 16.67 ms with zero
misses. The complete eleven-stop Apollo and nine-stop regional matrices above
precede this empty-index guard. Their non-empty realization path is unchanged;
subsequent oblique, re-anchor and motion captures use the final build.

`/tmp/LM-Stage2-Stability-Oblique-v2/` successfully publishes 95 plans at 35°
in 38,117 ms, with 93 mesh uploads and two fully hidden CPU parents. The
settled image was inspected without a foreground hole. Its settled p95/p99/max
is 16.67 ms with zero missed callbacks and 201.0 MiB, versus 157.1 MiB for the
54-plan heading-zero surface control. Whole-run maximum frame is 270.06 ms,
with four missed callbacks. This validates the previously failing resource
path and records the larger residency cost. It does not prove every heading
or distant boundary is visually accepted.

### Offline stationary re-anchor repeat

`/tmp/LM-Stage2-Stability-Reanchor/` repeats the production 4.2 km trigger
with cached-only source access. The log records one 54-plan generation in
21,715 ms, then `Reanchor generation=2 resident=54 pending=0`. No second
terrain generation occurs. The before frame uses the deliberately offset
anchor; it is not expected to be byte-identical to a normal-anchor launch.

The same-view before/after PNG comparison changes 545 of 8,294,400 pixels,
with normalized RGB RMSE 0.0000440105. The maximum individual channel change
is 12/255. Across fifteen fixed 2,880 by 32 pixel bands, linear Rec.709 mean
radiance changes by at most 0.00033594%. `image-metrics.json` records the
individual bands. These stationary bands test re-anchor continuity, not the
separate adjacent-source-boundary acceptance protocol. The after image differs
from the normal-anchor highland surface control at 117 pixels, with RGB RMSE
0.0000209624. Both images were inspected without a new visible gap or jump.

All 23 late performance windows, including the re-anchor, have p95/p99/max
16.67 ms and zero missed callbacks. Peak physical footprint is 158.3 MiB.
The whole-run maximum is 231.52 ms with four startup misses. The measurement
supports the existing threshold and no-rebake contract; physical stereoscopic
continuity still needs Vision Pro validation.

### Production motion sequence

`Tools/CaptureLunarTerrainTransitions.sh` drives the real Explorer session
through a 35° heading change at 2 m altitude and 8 m width, a zoom to 249 m
altitude and 700 m width, and a return to heading zero at 2 m and 8 m. Each
movement uses sixty eased steps and waits for production readiness plus
100 seconds. The 4K H.264 recording in
`/tmp/LM-Stage2-Stability-Motion/transitions.mov` is 430.528 seconds long.
The script verifies the live process, all three completion markers, and valid
video metadata before writing its completion manifest.

Four generations publish successfully: 54/95/60/54 plans in
20,898/38,100/26,618/21,996 ms. The final PNG is byte-identical to the initial
PNG. Sampled movement and arrival frames contain terrain throughout, without
a black coverage hole. They also expose a real temporal acceptance failure:
on the return to the surface, the stationary coarse foreground gains its fine
craters and texture when the last generation arrives. Publication is atomic,
but has no temporal geometry morph. This pass does not close that gate.

`frames/`, `events.json`, and `arrival-image-metrics.json` retain the sampled
evidence. Approximate video times for the three arrivals are 55.85, 191.65
and 323.02 seconds. At 1280 by 720, the two-second-before/after H.264 frame
pairs have normalized RGB RMSE 0.0002033, 0.0011612 and 0.0049849. The last
pair changes 506,178 of 921,600 pixels. These lossy video comparisons identify
the arrival change; they are not substituted for the PNG radiance protocol.
The recording run peaks at 256.8 MiB during replacement, with a final settled
159.7 MiB and 16.67 ms p95/p99/max. Recording overhead makes these unsuitable
for a direct comparison with the unrecorded item 0 performance baseline.

### Repeating the stability captures

`Tools/CaptureLunarGlobalTerrain.sh <udid> <LM.app> <lat,lon> <fresh-output>`
captures the nine-stop global ladder. Each stop requires a PID-scoped ready
event, then 90 seconds of settling. It rejects generation failures, dead
processes and unexpected saturation, and records image hashes and launch
controls. Run `Tools/SummarizeLunarTerrainTiming.py` over `performance.log`
for source, CPU, upload and presentation attribution. Use the capture
manifest's PID when selecting an individual run from that summary.

For matched boundary controls, select one stop with `LUNAR_CAPTURE_FILTER`.
Set `LUNAR_CAPTURE_TILE_TINT=1` for ownership, `LUNAR_CAPTURE_GRADE=photographic`
for the photographic grade, and both `LUNAR_CAPTURE_REFLECTANCE=constant`
and `LUNAR_CAPTURE_NORMAL_MAPS=off` for the geometry control. The same camera
and completed generation are required in every image. Run
`Tools/TerrainGenerator/measure_radiance.py --global-levels --tint <tint.png>`
with repeated `--image <label>=<image.png>` arguments. A frame without an
adjacent terminal/landing boundary is invalid evidence, even when both levels
exist elsewhere in the scene.

`LUNAR_CAPTURE_HEADING=35` selects the oblique control.
`LUNAR_CAPTURE_OFFLINE=1 LUNAR_CAPTURE_REANCHOR=1` selects the cached-only
stationary re-anchor repeat. The separate
`Tools/CaptureLunarTerrainTransitions.sh <udid> <LM.app> <lat,lon> <fresh-output>`
records the motion sequence above. Run one Simulator capture queue at a time.
Keep video recording and Xcode builds/tests out of baseline performance runs.
The controls in this pass do not establish all-level radiance, temporal arrival,
arbitrary-site cockpit descent, or physical Vision Pro acceptance.

The final manifest audit verifies 44 PNG hashes across 18 completed capture
manifests. `/tmp/LM-Stage2-Stability-Capture-Manifest-Verification.json` lists
them. All eleven Apollo baseline PNGs and all eleven original terrain asset
hashes were rechecked after the final captures and remain unchanged.

### Temporal arrival: shared triangle endpoints

The first arrival change adds a common refinement of the old and new aligned
clipmaps. Its endpoints come from the actual displayed triangles. Contact and
inspection rays evaluate the same vertex interpolation, with exact endpoint
branches and a bounded smoothstep weight. This is geometry infrastructure;
GPU realization and production arrival acceptance are subsequent checks.

`/tmp/LM-Stage2-Arrival-Geometry.xcresult` passes nine tests covering both
refinement and coarsening on a saddle, intermediate contact versus submitted
triangle rays within one micrometre, unchanged native fixture posts, restart
from an intermediate state, and existing oblique ownership and contact tests.
The first build exposed a Swift name-shadowing/type-check issue in the normal
interpolation expression; naming that intermediate explicitly fixed it.

### Temporal arrival: GPU and lifecycle

The production transition uses one opaque common-refinement surface. Its
LowLevelMesh and contact snapshot share endpoint vertices and the same Float
weight; a GPU readback checks exact vertex equality, including fused multiply-add
rounding. A 1.2-second smoothstep controls both geometry and appearance. Pending
requests can cancel and reverse while the displayed transition finishes; the
next transition starts from that displayed endpoint. Re-anchoring transforms
the resident entities without resampling either endpoint.

Appearance comes from copies of the actual uploaded TextureResources, including
their color conversion and normal encoding. The compute shader interpolates in
linear light and writes the native 8-bit sRGB format. Tests constrain output to
the expected final code-value rounding. The texture-copy probe established that
the copied northern row remains row zero; independently flipping the low-level
output had mirrored its endpoint. Existing mesh UVs remain unchanged.

Only submitted vertices determine whether a mesh needs GPU updates. Unchanged
geometry uses the existing static mesh path, and unchanged appearance reuses its
material. Hidden parent samples still remain available to contact. One command
buffer updates a displayed weight, with its completion handler registered before
commit. The next update waits for GPU completion and a scene update. Initial and
final publication each allow two scene updates before the next resource change;
an inactive scene has a bounded wait. Cached appearance remains available when
changing the global detail mode, because both choices currently use the same
procedural fallback pending N3.

Seven focused tests pass in `/tmp/LM-Stage2-Arrival-Native-Format.xcresult`:
refinement/coarsening and triangle contact, restart from an intermediate surface,
hidden-parent update classification, actual GPU vertices and linear-light
appearance, production cancellation/reversal/re-anchor lifecycle, easing, and
uploaded normal row order. The final broader suite also exercises a detail-mode
reset before a transition.

The final `/tmp/LM-Stage2-Arrival-Final.xcresult` passes **163 tests in 17 suites**
with no failures, in 194.499 seconds of test execution. This includes source and
residual fidelity, coordinates and floating origins, contact and descent,
navigation, texture edges and radiance controls, and the seven arrival tests.
The four Python radiance-tool tests also pass. Xcode MCP became unresponsive
after the rejected Metal texture assertion; only that test process and its
attached debugger were terminated. The final runs used the serial xcodebuild
fallback, with the exact result bundle retained above.

The first full prototype capture, `/tmp/LM-Stage2-Arrival-Motion-v1/`, was rejected:
552.09 ms maximum callbacks, 1,167.2 MiB peak footprint, a transient dark frame,
and a remaining endpoint detail jump. The short v2 replay exited on an incorrectly
registered Metal completion handler; the corrected path is tested. A proposed
swizzled single-channel writable texture also failed Metal validation and is not
used. The short v4 shadow-off control retained the dark footprint, ruling out
dynamic shadows as its source. The short scene-synchronized replay,
`/tmp/LM-Stage2-Arrival-Motion-v5-fast/`, did not show that large artifact; these
short holds are diagnostic and do not replace the 100-second hold protocol.

The subsequent full `/tmp/LM-Stage2-Arrival-Final-Motion/` replay was also rejected.
Its second arrival retained a one-frame dark footprint (adjacent-frame normalized
RGB RMSE 0.059594), despite passing GPU endpoint tests. The zoom-return peak was
0.002339 versus the old atomic path's 0.004863, and its settled PNG remained
byte-identical to both the initial frame and the accepted highland Surface PNG.
Those improvements did not excuse the flash. Its peak footprint was 1,220.4 MiB
during initial resource realization; final settled footprint was 174.2 MiB with
16.67 ms p95/p99/max and zero reported misses. Whole-run maximum was 260.29 ms.

Inspection found that the initial low-level textures were registered with
RealityKit before their first backing contents were populated. The follow-up
initializes each appearance and its mipmaps before creating its TextureResource,
and avoids an unnecessary initial replacement of already initialized meshes.
The GPU test now checks initial contents before any post-registration update.
The seven focused tests pass in `/tmp/LM-Stage2-Arrival-Initialized.xcresult`.

`Tools/MeasureLunarTerrainArrival.py` retains adjacent frames and reports their
differences around logged arrivals, using lossy 1280×720 video samples at 60 fps.
Those values supplement visual review, not the unchanged 1.5% fixed-band PNG
radiance criterion. `CaptureLunarTerrainTransitions.sh` retains the default
100-second holds, supports an explicit shorter diagnostic hold, records launch
arguments and binary hash, and fails promptly on process death or terrain errors.

### Temporal arrival: Apollo regression control

`/tmp/LM-Stage2-Arrival-Final-Apollo/` repeats the eleven-stop Release ladder with
the item 0 twenty-second settling protocol. Every PNG is byte-identical to
`/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2/`. Every final sampled window reports
16.67 ms p95/p99/max and zero missed callbacks. Peak process footprint is
364.8 MiB versus the baseline's 406.5 MiB; worst startup callback is 518.37 ms
versus 643.77 ms. These are Simulator measurements, not 90 Hz device acceptance.

Globe, Terminal, Landing and Surface settled footprints are 305.3, 329.3, 354.5
and 361.2 MiB respectively (baseline 312.2, 336.5, 380.8 and 368.6 MiB).
Terminal completion records span 286–319 ms and Landing 1,706–1,869 ms;
baseline ranges are 252–356 ms and 1,471–2,043 ms. Per-stop numbers and byte
comparisons are in `baseline-comparison.json` and `performance.tsv` in that
capture directory. This capture uses binary
`2f10d8e20a72520111f557c8044ac0cb0ada21ba4720e2ad3964dab873c3546c`, before
the global-only texture-initialization follow-up.

### Temporal arrival: accepted highland replay and remaining cost

The initialized-texture Release binary is
`fee67ec465822baf35548ca6e1c3f0f079cf87e2530954080de9a14bb20e0dd0`.
`/tmp/LM-Stage2-Arrival-Initialized-Full/` records the production rotation,
zoom-out and zoom-return with the default 100-second holds, shadows and normal
maps enabled. Its 3840×2160 video is 446.587 seconds long. Arrival frame review
shows no recurrence of the transient gap or dark footprint. The before/after
PNGs are byte-identical, and both match the previously accepted highland
`07-surface.png` exactly. The existing highland fixed-band radiance controls
therefore still describe that settled image; this is not a new all-level
radiance acceptance claim.

| Arrival | Actual blend duration | Old atomic peak adjacent RGB RMSE | New peak | Change |
| --- | ---: | ---: | ---: | ---: |
| Rotate 0° → 35° | 1.254 s | 0.000855174 | 0.000861870 | +0.8% |
| Zoom out to 249 m / 700 m width | 1.281 s | 0.001178016 | 0.000878942 | −25.4% |
| Return to 2 m / 8 m width | 1.292 s | 0.004863249 | 0.002325657 | −52.2% |

These lossy video differences are diagnostic measurements, not a replacement
for the 1.5% radiance criterion. `arrival-frames/` retains the sampled frames
and each peak pair; `baseline-comparison.json` records both PNG equality and
the comparison with `/tmp/LM-Stage2-Stability-Motion/`. The short initialized
replay also passed visual inspection and restored identical PNG bytes in
`/tmp/LM-Stage2-Arrival-Initialized-Fast/`.

**The visual fix does not close performance acceptance.** The full run reports
111 frame windows, 16.67 ms maximum p95, 86.45 ms maximum p99, 248.80 ms worst
callback and 19 misses. The old atomic control had 108 windows, 16.67 ms maximum
p95, 86.67 ms maximum p99, 173.66 ms worst callback and six misses. The new
sampled peak physical footprint is **1,247.5 MiB**, versus **256.8 MiB** in that
control. It occurs during transient resource creation. Final settled footprint
recovers to **175.0 MiB**, versus **159.7 MiB**, with four late windows at
16.67 ms p95/p99/max and zero misses. The five-second sampling does not establish
the absolute allocation high-water mark or physical Vision Pro memory pressure.

Initial/rotation/zoom-out/return generation times are 20,759 / 42,829 / 33,461 /
26,354 ms, compared with 20,898 / 38,100 / 26,618 / 21,996 ms in the atomic
control. Common-refinement preparation takes 273–386 ms on a worker. Asynchronous
resource realization takes 3.09–5.26 seconds per arrival; those main-actor spans
include suspension and are not continuous CPU occupancy. The 99 update
submissions total 493.59 ms of measured main-actor work, with a 65.22 ms maximum.
GPU completion waits total 2,238.70 ms, with a 126.29 ms maximum; they suspend
instead of accumulating additional in-flight submissions.

The recorded abrupt highland arrival is addressed. Transient allocation cost,
arrival hitches, distant footprint joins, arbitrary-site globe handoff radiance,
and full cockpit descent remain open. Cancellation, reversal, mode reset and
re-anchoring during interpolation have production lifecycle and GPU/triangle
test coverage; this pass does not add a video of re-anchoring mid-interpolation.
Physical Vision Pro must still validate 90 Hz pacing, GPU memory/pressure,
thermals, stereo continuity and comfort. All eleven original terrain asset
hashes were rechecked against `c950d46` in
`/tmp/LM-Stage2-Arrival-Apollo-Assets.json`; all remain identical.

The additional `/tmp/LM-Stage2-Arrival-Initialized-Mare-Fast/` control rejected
broader arrival acceptance: its first arrival had a one-frame triangular gap at
the image edge, with peak adjacent RGB RMSE 0.072004. Its settled before/after
PNGs were nevertheless byte-identical to the accepted mare Surface PNG. The
texture-initialization correction alone therefore does not establish complete
scene-publication readiness. This short run used five-second holds and is a
diagnostic control, not a substitute for the long-hold performance protocol.

A zero-opacity scene-registration experiment also failed to remove that gap
in `/tmp/LM-Stage2-Arrival-Registered-Fast/` (peak 0.072002). Its cancellation
tests passed, but visual evidence rejected that approach. The next publication
path retains the previous opaque representation only at the common-refinement
starting endpoint, for a 100 ms registration interval, before removing it and
starting interpolation. Re-anchoring updates both representations during that
interval, and cancellation removes only the incoming one. The seven focused
tests, extended to cancel and re-anchor during registration, pass in
`/tmp/LM-Stage2-Arrival-Covered.xcresult`; visual acceptance is recorded below.

### Temporal arrival: final mesh-publication control

The final Release binary is
`6657e14b4f0e0f0bd5e2b800ef201ec42e2514cab600c52aaa71db0c22009086`.
Both `/tmp/LM-Stage2-Arrival-Covered-Fast/` and the default-hold
`/tmp/LM-Stage2-Arrival-Covered-Mare-Full/` remove the mare publication gap.
The full 3840×2160 recording is 433.972 seconds long. Arrival frame inspection
shows no transient gap or dark footprint, and the before/after PNGs are
byte-identical to each other and to the accepted mare Surface PNG.

The full mare rotation/zoom-out/return durations are 1.280 / 1.317 / 1.279 seconds,
with peak adjacent RGB RMSE 0.000974759 / 0.001451590 / 0.003358608. The first
arrival's 0.072004 gap spike in the rejected mare replay is absent. The 100 ms
registration interval is deliberately conservative relative to that one-frame
60 Hz defect; it retains the same starting surface and adds less than 0.3% to
the measured rotation generation time. It is not a claimed optimal threshold
or a guarantee for physical-device rendering.

The full mare run records 109 frame windows, 16.67 ms maximum p95, 84.59 ms maximum
p99, 261.64 ms worst callback and 22 misses. Its sampled peak footprint is
508.3 MiB; five late settled windows report 16.67 ms p95/p99/max, zero misses and
173.3 MiB. Initial/rotation/zoom-out/return generations take 19,216 / 40,100 /
28,186 / 24,481 ms. This lower sampled peak does not prove that the highland
allocation regression disappeared: regions and sampling alignment differ.
`metrics.json`, `endpoint-comparison.json`, `arrival-temporal-metrics.json` and
`arrival-frames/` retain the evidence. The terrain performance gates above remain
open.

The same final binary passes the short highland regression replay in
`/tmp/LM-Stage2-Arrival-Covered-Highland-Fast/`. Its peak adjacent RGB differences
are 0.000853768 / 0.000904689 / 0.002322102, with no transient gap or dark
footprint in the inspected arrival frames. The return peak is 52.3% lower than
the atomic control, and both settled PNGs remain byte-identical to the accepted
highland Surface image. Its 516.4 MiB sampled peak is substantially below the
earlier initialized-texture short run's 1,112.8 MiB, but the final long highland
comparison below controls the hold duration as well.

### Temporal arrival: final matched highland comparison

`/tmp/LM-Stage2-Arrival-Covered-Highland-Full/` repeats the original highland
sequence with the default 100-second holds on the final binary above. Its
3840×2160 video is 448.818 seconds long. All three inspected arrivals are free
of the previously recorded gap and dark footprint. Before/after PNGs are
byte-identical and match the accepted highland Surface PNG. Blend durations
are 1.295 / 1.280 / 1.279 seconds; peak adjacent RGB RMSE is 0.000856451 /
0.000902409 / 0.002300722. The zoom-out and return peaks are 23.4% and 52.7%
below the atomic control; the rotation peak differs by only +0.15%.

| Metric | Atomic highland control | Final highland arrival |
| --- | ---: | ---: |
| Frame windows | 108 | 112 |
| Maximum p95 / p99 | 16.67 / 86.67 ms | 16.67 / 101.08 ms |
| Worst callback / total misses | 173.66 ms / 6 | 154.91 ms / 18 |
| Sampled peak physical footprint | 256.8 MiB | 713.8 MiB |
| Late settled footprint | 159.7 MiB | 174.7 MiB |
| Late p95 / p99 / max / misses | 16.67 / 16.67 / 16.67 ms / 0 | 16.67 / 16.67 / 16.67 ms / 0 |
| Initial generation | 20,898 ms | 20,726 ms |
| Rotation generation | 38,100 ms | 44,357 ms |
| Zoom-out generation | 26,618 ms | 33,710 ms |
| Return generation | 21,996 ms | 26,457 ms |

This is the final comparison, superseding the earlier initialized-texture
highland run for performance reporting. The publication fix reduces the sampled
peak relative to that 1,247.5 MiB prototype, but the remaining allocation and
arrival-hitch regression keeps performance acceptance open. Five late windows
are stable; neither that result nor the lower worst callback establishes
physical 90 Hz acceptance. The 92 morph submissions total 495.09 ms of measured
main-actor work, maximum 59.96 ms, with 2,109.40 ms of suspended GPU waits,
maximum 137.37 ms. Resource realization totals 11.77 seconds across three
arrivals, maximum 5.27 seconds. Phase spans overlap and must not be summed as
total generation latency.

The final Release build log is `/tmp/LM-Stage2-Arrival-Covered-Release.log`.
The 163-test broader suite and four Python checks passed; the seven GPU/lifecycle
arrival tests were rerun after the final publication change in
`/tmp/LM-Stage2-Arrival-Covered.xcresult`. No tests failed in these final runs.
`/tmp/LM-Stage2-Arrival-Capture-Hashes.json` retains 19 PNG hashes across the
Apollo control and four final-binary motion captures. Physical-device and
broader Stage 2 gates listed above are unchanged.

## Arrival allocation attribution, 2026-09-05

The opt-in profile now records Mach physical footprint and its kernel lifetime
peak around preparation, resource realization and frame submission. The timing
summary retains these timestamped samples. Metal allocation counters return zero
in this Simulator; those values are unavailable, not evidence of no allocation.
Resource payload counts use buffer lengths and uncompressed RGBA mip dimensions,
excluding driver padding and retained replacement copies.

The first instrumented highland diagnostic, with five-second motion holds, is
`/tmp/LM-Arrival-Memory-Control/`. Release build passed. Its settled before/after
PNGs match the accepted highland PNG byte for byte. The first arrival grows from
259.4 MiB before CPU preparation to 485.6 MiB afterward, then 691.7 MiB after
resource realization. The three arrivals have 61/105/68 dynamic meshes and the
same counts of blended appearances. The five-second sample maximum is 1,039.0
MiB. CPU preparation takes 1,019.6 ms total across three arrivals.

The kernel lifetime peak is already 1,601.8 MiB before the first arrival, exposing
a separate startup peak missed by the old five-second sampler. A `vmmap` attempt
completed after the first blend, so its retained report does not attribute the
blend peak. This short diagnostic, including that inspection, is not a matched
performance acceptance run. The initial binary's Metal resource counters were
also zero; explicit logical payload accounting was added afterward and built
successfully through Xcode MCP.

The CPU-only reduction is retained at `/tmp/LM-Arrival-Compact-Highland/` with
the same five-second diagnostic holds. The first preparation increase falls
from 226.2 MiB to 47.3 MiB. Preparation totals 851.0 ms versus 1,019.6 ms,
and all seven arrival tests pass in `/tmp/LM-Arrival-Compact-Tests.xcresult`.
Its settled PNGs are byte-identical. This alone does not resolve the peak:
the complete short replay still samples 987.9 MiB. Logical texture accounting
shows why: zoom-out retains 343.1 MiB of source texels and 297.8 MiB of output
texels, before driver overhead and replacement copies.

The combined reduction preserves Float32 precision, source posts, interpolation
and final static resources. It shares compact normal/elevation endpoints with
contact, packs transient GPU vertices from 80 to 56 bytes, and retains only
level zero of copied source textures. The compute shader already samples that
level explicitly; output textures keep the complete generated mip chain.
Source copies are cached by both tile ID and full plan, retaining both endpoint
variants when their collars differ. Alternating parent ownership has a dedicated
GPU resource regression test. Uploaded endpoint pixels, linear-light blending,
GPU/contact agreement and publication cancellation remain covered.

Validation before the final captures:

- `/tmp/LM-Arrival-Resources-Tests.xcresult`: 22 methods, 25 cases across
  arrival, transitions, rendered contact and floating origins; no failures or
  skips. The Simulator emitted a launch-service error, but the result bundle
  confirms all cases completed successfully.
- `/tmp/LM-Arrival-Final-Tests.xcresult`: all eight arrival methods pass after
  the source-variant cache correction, including the new alternating-owner test.
- Four `test_measure_radiance.py` checks pass. Python compilation, shell syntax
  and `git diff --check` pass.
- Xcode MCP built the diagnostics successfully but later test/edit calls timed
  out. The Xcode skill's command-line fallback produced the result bundles and
  Release builds. Device discovery also reports a locked physical device;
  those messages do not establish physical-device test coverage.
- `/tmp/LM-Arrival-Resources-Apollo-Assets.json`: all 11 original terrain assets
  match `c950d46` byte for byte. Both user scheme files retain their original
  hashes, and the separate AGC working tree is unchanged by this work.

### Fresh paired mare allocation control

The older five-second memory sample cannot bound a transient peak. A fresh
original/optimized pair therefore uses the same Simulator, coordinates, source
set, launch arguments and five-second diagnostic holds, consecutively without
concurrent builds or tests. The original arrival implementation was rebuilt from
the five implementation files at `dafe02b`; all current source files were then
restored and verified byte for byte. Both app bundles remain available under
`/tmp/LM-Arrival-Control-Build/`.

| Metric | Original arrival | Compact arrival |
|---|---:|---:|
| Five-second sampled maximum | 716.8 MiB | 541.5 MiB |
| Maximum observed across phase samples | 1,172.4 MiB | 903.5 MiB |
| Reported frame misses | 25 | 20 |
| Maximum window p95 | 18.49 ms | 16.67 ms |
| Maximum window p99 | 84.75 ms | 85.08 ms |
| Worst callback including startup | 146.20 ms | 236.72 ms |
| CPU preparation total, three arrivals | 1,028.0 ms | 812.4 ms |
| Main-thread blend update mean | 5.284 ms | 4.454 ms |
| Main-thread blend update maximum | 64.889 ms | 59.845 ms |
| Asynchronous realization total | 11,796.0 ms | 11,881.1 ms |

The measured phase maximum falls 22.9%, and the five-second maximum falls 24.5%.
The callback maximum worsens, and resource realization remains essentially
unchanged. These are single matched runs, not a statistical performance budget
pass. Their phase samples still do not bound every sub-phase allocation; the
kernel lifetime peak is dominated by the separate approximately 1.6 GiB startup.
Raw logs, binary hashes and matched comparison are retained in
`/tmp/LM-Arrival-Fresh-Control-Mare/` and `/tmp/LM-Arrival-Final-Mare-Fast/`.

The original binary is
`477cacdaa6a0ce215cb8b3abab0ef44655fbb9c31e460471d5aaab43a48e8195`.
The final compact binary, also used for the full captures, is
`0f308cf3d1165ea0bf2786de1a3d1b27c91bbbc0ac43d99e77ee210a79925e3c`.

### Full mare replay

`/tmp/LM-Arrival-Final-Mare-Full/` uses the final binary and the original
100-second holds. All three arrivals preserve continuity in the inspected
frames; the settled before/after PNGs also match the accepted mare Surface PNG
byte for byte. Adjacent-frame peaks are 0.0009751, 0.0014131 and 0.0025583, versus
0.0009748, 0.0014516 and 0.0033586 in the preceding accepted arrival capture.
These lossy video diagnostics do not replace the fixed-band radiance contract.

All 109 windows have maximum p95 16.67 ms. The run reports 18 misses versus 22,
maximum p99 101.34 ms versus 84.59 ms, and worst callback 300.36 ms versus
261.64 ms. The five-second memory maximum is **947.2 MiB versus 508.3 MiB** in
the older capture. This regression remains in the record; the fresh paired
control above establishes a narrower memory improvement under current matched
conditions. The five late windows have 16.67 ms p95/p99/maximum and zero misses,
at 227.5 MiB versus 173.3 MiB previously. The memory and hitch gates remain open.

### Final full highland replay

`/tmp/LM-Arrival-Final-Highland-Full/` repeats the original 100-second holds with
the final binary. Its 112 frame windows have maximum p95 16.67 ms, maximum p99
99.56 ms versus 101.08 ms, worst callback 286.86 ms versus 154.91 ms, and 21
misses versus 18. The five-second memory maximum is 493.9 MiB versus 713.8 MiB;
phase samples reach 677.4 MiB. The five late windows are 16.67 ms p95/p99/maximum
with zero misses at 234.0 MiB versus 174.7 MiB. Settled memory is therefore
higher even though the sampled arrival maximum is lower.

CPU preparation totals 767.1 ms versus 986.6 ms. The 131 main-thread blend
updates total 570.7 ms with a 57.20 ms maximum; the preceding implementation
had 92 updates totaling 495.1 ms with a 59.96 ms maximum. Average update work
falls from 5.38 to 4.36 ms, with more intermediate displayed weights. Async
resource realization remains about 11.9 seconds across all three arrivals.
Generation completion is 22,111 / 43,286 / 33,522 / 26,240 ms, close to the
preceding 20,726 / 44,357 / 33,710 / 26,457 ms. This does not close generation
latency, worst-frame, settled-memory or physical-device acceptance.

The final highland before/after PNGs match one another and the accepted Surface
control byte for byte. Adjacent-frame peaks are 0.0008559 / 0.0008926 / 0.0023024,
compared with 0.0008565 / 0.0009024 / 0.0023007 previously. The inspected peak
frames show no new publication gap or flash. Blend durations are 1.251 / 1.276 /
1.279 seconds. The original static endpoint images and existing fixed-band
radiance acceptance therefore remain unchanged.

### Final Apollo 11 and acceptance boundary

`/tmp/LM-Arrival-Final-Apollo/` uses the same final binary and the item 0
eleven-stop Release protocol with 20-second holds. All eleven PNGs are
byte-identical to `/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2/`. Every final
window has 16.67 ms mean/p95/p99/maximum and zero missed callbacks. The sampled
physical maximum is 369.9 MiB versus 406.5 MiB; the worst cold callback is
513.50 ms versus 643.77 ms. The kernel lifetime maximum is 1,604.3 MiB, again
exposing startup allocation that the older five-second baseline did not bound.
Terminal tile completion is 296–317 ms versus 252–356 ms; Landing is
1,386–1,532 ms versus 1,471–2,043 ms. Surface settles at 348.3 MiB versus
368.6 MiB. `performance.tsv`, `metrics.json`, `baseline-comparison.json` and
the binary hash are retained with the images.

`/tmp/LM-Arrival-Capture-Hashes.json` records 25 primary PNG hashes across this
work's motion controls and the final Apollo ladder. The standard Release build
product is restored to the optimized source after building the isolated control
app. Code is committed as `40d5f0a`; allocation diagnostics are `dafe02b`.

This completes the focused allocation reduction and its Simulator validation.
It does **not** close overall arrival performance: full-run frame misses are
mixed, late global footprint is higher, asynchronous realization remains about
12 seconds across three arrivals, and startup still reaches about 1.6 GiB.
Distant joins, arbitrary-site globe handoff radiance and cockpit integration
remain open under the controlling plan. Physical Vision Pro must still validate
90 Hz pacing, actual GPU memory pressure, thermals, stereo continuity and comfort.
