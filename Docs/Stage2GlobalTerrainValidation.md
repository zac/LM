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
Captures wait for the production geometry-ready event and then settle at least
90 seconds. Tile tint, normal-map-off and shadow-off controls are diagnostics,
not acceptance images.

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
  removed. A coarse triangular near-field patch remains visible at the edge.
- `/tmp/LM-Stage2-Global-Tile-Control/` and
  `/tmp/LM-Stage2-Global-Geometry-Control/`: tile tint identified the intruding
  surface as a terminal parent; disabling shadows and normal maps did not remove
  it. Widening the fine view corridor reduced but did not eliminate the artifact.
- `/tmp/LM-Stage2-Global-Coarse-Ladder/`: highland 128/32/8 m and handoff captures.
  Their generation times were 5653/3479/4907/6899 ms. These precede the final
  depth-bound fix and must not be presented as accepted final handoff images.
- `/tmp/LM-Stage2-Item4-Offline-Reanchor/`: an offline production region and
  before/after capture of the actual re-anchor trigger, with no geometry rebake.
  The final per-frame and image-difference results are recorded below.

Open gates: the coarse near-field intrusion; temporal band-arrival continuity;
site-specific handoff radiance at arbitrary locations; global source-join visual
acceptance; the complete Apollo/mare/highland ladder; N3 geology conditioning;
and physical Vision Pro frame timing, memory, stereo depth and gesture comfort.
No acceptance threshold has been relaxed to close these gates.

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
The required constant-reflectance/no-normal control is reported separately.
The mare surface tint contains only landing tiles. Its failed measurement is
correctly rejected; a same-view surface image cannot establish a boundary pass.

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
