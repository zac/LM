# Moon Explorer one zoom

Work starts at `739a0e5` on `terrain-realism-and-explorer` under
`MoonExplorerOneZoomPlan.md`. Scope is steps 1–3; steps 4–6 remain untouched.
Evidence: `/tmp/LM-Explorer-OneZoom-2026-09-06/`. Xcode 26.6, Release,
visionOS 26.5 Simulator `8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`.
Builds, tests and captures run serially.

## Step 1 implementation and validation

A rounded portal and frame enclose the existing globe/site presentation in
mixed immersion. One world contains both representations and their lighting.
Plane clipping and crossing are disabled: the established foreground projection
puts terrain in front of the fixed globe surface, so plane clipping would cut
valid terrain. The portal mask supplies the hard rounded edge. Full immersion
removes the world component and hides the portal/frame. The handoff, radiance,
foreground projection, source assets and terrain algorithms are unchanged.

Immerse is gated at 120 km across. Leaving restores the window and zoom-out
range. The scene supports mixed, progressive and full immersion styles; the
button selects full. The Globe/Surface picker and Exit surface ornament are
removed. Fixed reference captures disable the frame through configuration and
retain explicit altitude/width/tilt values.

The initial focused run passed 51 tests and failed two. One was an obsolete
browse-floor expectation; the other exposed a one-ULP roundoff above 120 km
which incorrectly disabled Immerse. Zoom now snaps that single-ULP boundary to
the exact gate. The readiness-gate run passes all 53 tests with no
failures or skips in `Step1-ReadyGate.xcresult`. Immerse additionally waits
for terrain readiness so a quick dive cannot expose the fallback sphere in
full immersion. The later journey acceptance is recorded below.

All eleven pinned terrain resource hashes match the accepted list, recorded
in `terrain-assets.json`. The existing owner edits in LandAnywhereMoonPlan and
MoonExplorerExperience are preserved, as are both scheme-user files. No AGC
changes. Physical gesture comfort, placement/parallax, portal stencil cost,
90 Hz compositor pacing and thermal behavior remain owner validation gates.

Step 1 ordinary Release build passes. Executable SHA-256: `5f78d15753a95bf605e2cb2616b6d8077aa78c2d5bff7ed1d001a8901e916d4b`.


### Handoff correction

The first six-stage journey completed its state assertions but failed visual
acceptance: `Step1-Journey/handoff.png` is black. The old product stops table
rotated the globe by about 62 degrees at 180 km across. Adding the registered
tangent's 90-degree orientation turned the site away from the viewer. The
accepted capture path keeps the globe face-on and lets the existing morph
supply the site tilt. The window path now supplies that same input throughout
the handoff. The five protected function bodies remain text-identical to
`739a0e5`, recorded in `protected-functions.json`.

`Step1-Handoff.xcresult` passes 54 focused tests, zero failures/skips. This
includes the handoff input and a regression for returning from full immersion:
leave immersion before selecting the globe altitude, otherwise the width
setter correctly clamps the request at 120 km. The subsequent ordinary Release
build passes. `Step1-Journey-Handoff` completes and all six images were inspected.
The handoff now renders terrain. The low-contrast terrain at the product's
near-noon lighting remains visible in portal and full space. This is not a
lighting-quality improvement claim. The portal is placed to the right of the
controls; the Simulator's initial camera does not frame its entire right edge.
Physical placement and viewing comfort remain open.

That six-stage run measured 95.4–302.8 MiB in frame-window process observations,
a 1,595.7 MiB lifetime peak, a largest window mean of 17.98 ms, largest window
p99 of 110.30 ms and largest callback interval of 146.23 ms. These are Simulator
CADisplayLink observations, not headset compositor or GPU timings. No stage
exceeded 60 seconds. The first rejected run and corrected run are separate
observations; their difference does not establish a performance improvement.

The final seven-stage journey adds 210 km across between clipped sphere and
handoff to exercise partial opacity inside the portal. The original required
180 km handoff stop has already completed the opacity fade and cannot test
that interaction by itself. `Step1-Journey-Final` passed; the final Apollo
check passes all eleven byte comparisons. Its ordinary Release executable SHA-256 is
`f338d84d601d94715bffcf4fec9207f8ef8bf70fff2d0f451b267ca8827788c6`.
Only capture instrumentation changed after the 54-test run.

All seven final images were inspected individually:

| Image in `Step1-Journey-Final` | Observation |
|---|---|
| `disk.png` | Whole disk, Apollo flag, room outside the rounded frame. |
| `clipped.png` | Enlarged sphere fills the frame; the frame clips its edge. |
| `crossfade.png` | At 210 km, partially transparent terrain composites over the globe inside the portal; no black frame or visible geometry cut. |
| `handoff.png` | At 180 km, registered terrain fills the portal. |
| `terrain.png` | At 24 km, the oblique terrain remains inside the frame, with low contrast under near-noon lighting. |
| `immersion.png` | Room and frame disappear; terrain continues at the same zoom, with Leave immersion available. |
| `return.png` | Room and frame return at the same terrain zoom. |

The final journey records 37 frame windows, 95.3–302.8 MiB observed process
footprint, a 1,595.2 MiB lifetime peak, maximum window mean 18.05 ms, maximum
window p99 115.11 ms and maximum callback interval 150.54 ms. No stage exceeded
60 seconds; no process sample was required. The five-cycle restore/re-entry
soak remains Step 3 work. Physical gesture comfort, portal stencil cost and
90 Hz pacing are unvalidated.


### Step 1 Apollo gate

`Step1-Apollo-Final/comparison.json` records eleven byte-identical PNGs against
`/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2`. The final ordinary Release build
used 20-second holds, one attempt per stop, and the pinned 64 ppd globe tier.
The final settled windows all measured 16.67 ms p95/p99/maximum and zero missed
callbacks, matching item 0's 16.67 ms p95. Final settled footprint ranges from
291.2 to 366.3 MiB, compared with 311.5 to 380.8 MiB in item 0. These single
Simulator runs show no settled callback regression; they do not establish a
repeatable memory or device-performance improvement. Entry hitches remain.

No Step 1 test or Apollo comparison remains failed. The initial black handoff
is retained as rejected evidence, followed by two passing visual journeys.
Steps 2 and 3, the separate Apollo site-pack gate, the five-cycle soak and all
physical Vision Pro gates remain outstanding.


## Step 2 boundary decision

Step 1 is committed as `ed9bd84`. Step 2 is not landed. Its altitude-camera
and heading-planning prototype passes 57 focused tests with zero failures or
skips in `Step2-Camera-Prototype-Retry.xcresult`. The initial prototype run
passed 55 and failed two: an obsolete independent-interactive-zoom expectation,
and a real arrival bug where the old `altitude * 3.2` assignment overwrote the
new camera's requested altitude. Both are corrected in the saved prototype.
The real terrain planner/baker test warms a 700 m view, sweeps heading through
90 degrees, and observes zero new generation requests or tile builds during
the gesture. The release requests the newly quantised corridor. This does not
yet test physical two-hand recognition or the complete gesture UI.

The prototype has been archived at
`/tmp/LM-Explorer-OneZoom-2026-09-06/Step2-Anchor-Boundary/camera-heading-prototype.patch`,
SHA-256 `1a4c760d63cae6a02854a309e84c94493fc75d9efe5cbfb25ae7d2611056e956`.
`git apply --check` succeeds against `ed9bd84`. The app source in the checkout
has been restored to that validated Step 1 commit; the owner document and
scheme changes are preserved. No Step 2 Apollo ladder or visual acceptance has
been claimed. The patch still needs gesture wiring, pinch anchoring and pin
heading alignment before its final validation.

The existing fixed-centre globe placement creates a boundary case for §3.3's
unqualified requirement that the point under the hand stays fixed. A ray
through a point 1 m right of the portal centre intersects the enlarged Moon
at 1,000 km across. At 4,400 km across, its closest approach to the centre is
1.5404 scene metres while the sphere radius is only 1.1846 m. It misses the
sphere. A lunar coordinate/heading change rotates the sphere and cannot make
it reach that ray. The same ray misses at the 5,000 km upper bound.

This is analytic evidence for the current placement, not a claim that portals
or anchored zoom in general are impossible. Reproduction and constants are
in `Step2-Anchor-Boundary/reproduce.py`, `geometry.json` and `README.md`.
The owner request says to stop and propose a bounded alternative when a
specified combination proves infeasible. The pending choice is:

- **Recommended:** preserve the anchor while the ray intersects the Moon,
  then release it continuously at the limb and keep the full zoom-out range.
  This keeps the accepted placement but qualifies the anchored-pinch contract.
- Allow a lateral camera offset inside the portal, preserving the fixed
  nearest-surface depth while letting the whole disk move off-centre. This
  adds a placement/bookmark rule and needs its own visual acceptance.

No new zoom floor was added, and neither boundary behavior was chosen silently.
Apollo site-pack migration, Step 3 scene stepping, the five-cycle soak,
physical gesture comfort, portal stencil cost and device 90 Hz pacing remain
open. Steps 4–6 were not started; AGC and terrain data were not changed.

Automatic approval review rejected removal of the existing browse-mode globe
brightness multiplier, classifying it as a protected radiance change. That
edit was not applied; the existing brightness policy is retained, including
in the saved prototype. No workaround was used.

### Approved continuation, 2026-09-07

The owner approved the recommended limb release. The prototype above is now
restored in the checkout. The camera derives width and tilt from altitude
using monotone C1 calibration; named presets select altitudes. Pinch reads a
submitted terrain triangle at gesture start and reuses that source-frame
point during the gesture. It re-picks when the visible representation changes.
The globe anchor eases through the last 2% of squared radial clearance before
releasing along the limb. The sphere retains its fixed depth and zoom range.
Terrain remains bounded by the existing resident-region pan limits; anchoring
cannot promise to follow a point beyond those limits before the sliding-region
work in Step 5.

Dragging pans below the handoff and moves over the sphere above it. Two-hand
rotation changes heading; planning holds the prior corridor until release,
then commits a 15-degree bin with a 2.5-degree hysteresis margin. Place pins
and the flag label follow the globe's heading. The Apollo site-pack migration
has not been applied.

`Step2-Gestures.xcresult` passes all 59 focused tests, zero failures/skips.
The initial gesture build rejected `.camera` coordinate conversion because
that API is unavailable in visionOS. The corrected implementation queries an
ARKit device anchor. Simulator uses an explicitly fixed calibration because
it has no world-tracking provider. Loss of device tracking preserves zoom and
skips anchoring; device pose/gesture accuracy remains unvalidated.

The ordinary Release build passes. Apollo, journey and interaction-probe
acceptance are in progress; no Step 2 commit or final visual pass is claimed.

### Camera and gesture validation

`Step2-Final.xcresult`: **61 passed, zero failed/skipped** in the six focused
suites. Tests cover C1 width/tilt calibration, limb release, exact triangle
queries including an ownership hole, pan correction, heading hysteresis,
and a real terrain planner at 700 m across: zero generation requests or tile
builds during the heading sweep, one planning request after release.
The ordinary Release executable is
`63435ec850e2788997717e6fc882ffea8ea796b7afb9b5caceb2fc1fbb52b0c0`.
All eleven resource hashes and the five protected method bodies are unchanged.

`Step2-Journey` completed the seven product stages plus four interaction
stages. Each image was inspected: disk shows the whole Moon and flag within
the room/frame; clipped sphere fills the frame; crossfade and handoff have
terrain without an open black gap; terrain is very low contrast under the
near-noon lighting; immersion removes the frame; return restores the room
and frame. The anchored 180 m to 90 m altitude pinch retains its submitted
source-frame point within 0.0001 scene metres of the fixed ray (maximum error
logs as 0.000000). Pan advances 40 m east across the 32 m tile grid. Broad
triangular facets remain visible before and after; there is no newly opened
gap in these captures, but the unqualified seam-free visual gate remains open.
These probes do not validate physical hand tracking or anchoring outside the
resident-region bounds.

The first exact Apollo pick scanned roughly 3.2 million triangles and took
199 ms. Bounds rejection alone still took 146 ms. A triangle hierarchy reduced
the candidate set to 1,333 triangles, but extracting RealityKit buffers still
cost 133 ms. Retaining the extracted buffers in the revisioned entity index
reduced the final observed pick to **0.343 ms**. Cache invalidation follows
mesh replacement; the cache holds weak entity references and prunes retired
entities. The hierarchy and buffers account for **73,047,712 bytes (69.7 MiB)**
at this view. Index preparation and a cold pick before preparation can still
hitch; the global terrain query uses its existing exact morph snapshot and
has not been profiled by this Apollo probe.

`Step2-Final-Gestures` completed all four stages; each PNG was inspected.
Pinch start/end show the same terrain feature at different altitudes, with
facets still visible. Pan before/after moves the surface without exposing an
open gap. Its 22 frame windows report 381.0–384.8 MiB footprint, 1,595.6 MiB
lifetime peak, maximum window mean 20.30 ms, p99 116.57 ms and maximum callback
interval 208.96 ms. These include loading/publication, and are CADisplayLink
observations rather than GPU or headset pacing. The earlier full journey had
117.7–339.1 MiB footprint and 1,620.3 MiB lifetime peak; those different paths
and single runs are not evidence of a general improvement. The cache's memory
cost is deliberate and remains part of the physical-device review.

`Step2-Apollo-Final` passes **11/11 byte-identical PNGs** against the item-0
baseline, 20 seconds per stop, one attempt, pinned 64 ppd. All eleven final
settled windows have p95/p99/max 16.67 ms and zero missed callbacks; footprint
is 291.4–368.3 MiB versus baseline 311.5–380.8 MiB. Across all 33 windows,
footprint is 291.4–369.4 MiB, lifetime peak 1,604.1 MiB, maximum mean 26.54 ms,
p99 153.53 ms and maximum callback interval 1,229.50 ms. The latter is a
loading/publication hitch; this change does not close entry pacing. See
`comparison.json`, `settled.json`, `metrics.json` and `performance.log` in that
folder. The camera/gesture portion is validated; Apollo site-pack migration,
scene stepping, the soak and physical acceptance remain separate work.

## Step 3 scene stepping

The camera/gesture portion of Step 2 is committed as `4c8bd2a`.
Scene stepping now subscribes to `SceneEvents.Update` through a one-element
buffered stream consumed on the main actor. Each step reads immutable session
inputs; the synchronous apply cannot interleave with another actor mutation.
A snapshot comparison avoids redundant entity/planner work. Async completions
request a step; morphing remains eligible every frame. The RealityView update
closure only maintains the place-label attachment.

Diagnostics accumulate in the unobserved scene and publish at one frame
boundary when the value changes. The old `publishDiagnostics` equality guard
and mission-sun per-field guards are removed. Reopening keeps unpublished
results if a load completed while detached. The subscription and consumer
are cancelled when the view disappears. Existing material/resource/ownership
caches still guard real work, independently of SwiftUI observation.

`Step3-Scene.xcresult` and `Step3-Final.xcresult` each pass **63 tests, zero
failures/skips**. The added tests show that UI/diagnostic outputs leave the
scene snapshot unchanged, camera inputs change it, and repeated frame
publication emits a changed diagnostic value only once. The obsolete
inspection Rotate/Move picker and its incorrect no-LOD-change help are gone.
Explicit inspection flight/calibration branches still preserve the scripted
`--lunar-explorer-fly-to` endpoint behavior and independent width/tilt probes;
comments identify those compatibility reasons. This does not claim every
`isExplorerExperience` branch has been retired.

The ordinary Release executable is
`cb181b0347b3a83de8c1ff4375cbecc83f76749fa7484d9d3fc252a670a263f1`.
`Step3-Apollo` passes **11/11 byte-identical images**, 20 seconds, one attempt,
pinned 64 ppd. Settled p95/p99/max are 16.67 ms with zero missed callbacks;
footprint is 304.1–369.3 MiB (baseline 311.5–380.8 MiB). Across 33 windows,
footprint is 304.1–370.1 MiB, lifetime peak 1,604.0 MiB, maximum mean 20.63 ms,
p99 123.96 ms, and maximum callback interval 501.43 ms. Entry/publication
hitches remain; a single run does not establish a general pacing improvement.

`Step3-Restore-Soak` passes all five restore cycles, with exact saved camera
and sunlight state and persistence reload. All five journey PNGs were
inspected individually: `globe` shows the whole Moon and location pins;
`selected` shows Apollo's flag and selected card; the legacy-named `immersive`
stage shows terrain inside the portal; `returned` restores the Moon at the
panned location; `restored` reproduces the saved terrain view and coordinates.
This is a same-space navigation soak, not a physical close/reopen test.

The automatic `passed-over-60s.sample.txt` was inspected. 3,086 of 3,406 main
thread samples wait in `mach_msg2_trap` (90.6%); brief scene-step work appears,
with no SwiftUI update-loop stack. The five surface checkpoints are
410.925, 410.925, 410.878, 411.034 and 410.940 MiB. Returned checkpoints are
412.268, 412.284, 412.300, 412.347 and 412.253 MiB. Peak remains 1,618.99 MiB
through all cycles. Across all 95 frame windows, footprint varies
116.0–685.4 MiB during loading/replacement, maximum mean is 19.71 ms, p99
108.78 ms and maximum callback interval 434.82 ms. Stable checkpoints do not
prove the absence of leaks beyond this bounded run.

`Step3-Portal-Journey` passes all seven stages; every PNG was inspected.
`disk` contains the whole Moon/flag; `clipped` fills the rounded frame;
`crossfade` and `handoff` retain terrain without an open black gap; `terrain`
is low contrast at near noon; `immersion` removes the frame and shows Leave
immersion; `return` restores the room/frame and Immerse. Its 37 windows report
95.3–365.1 MiB footprint, 1,595.3 MiB lifetime peak, maximum mean 18.38 ms,
p99 109.58 ms and maximum callback interval 151.95 ms. No journey stage
required another over-60-second sample.

Step 3's Simulator gate is complete. Physical gesture comfort and accuracy,
tracking loss/cancellation, actual space close/reopen, portal stencil cost,
90 Hz pacing and memory pressure remain unvalidated on Vision Pro. The
single-run Simulator numbers do not close those device gates.

## Apollo site-pack integration (separate gate)

Step 3 is committed as `96e7df4`. The subsequent site-pack change removes the
bundled/global presentation-height branch from the interactive renderer and
uses the common ENU coordinate conversion for camera focus. The shared camera
centres every interactive source at 1.45 m; the old Apollo -0.35 m pose and
registered globe coordinate are explicit inspection calibration. The existing
rigid source-to-floating-ENU placement is retained. Authored planar heights,
meshes, contact and source selection remain unchanged; the pack is a source
adapter, not a new terrain bake.

Inspection corrected one plan assumption: the fixed 900 m pan limit cannot
simply be lifted to the global 20 km bound. Apollo's fine contact evaluator
returns nil outside its 2,048 m tile; source selection already reserves a
128 m measured collar. `LunarExplorerSitePack` derives the camera's admissible
focus offsets from that footprint and the focus landmark's offset. The old
900 m mode constant is removed. Both global regions and packs now install
bounds from their resident coverage. Crossing the pack boundary needs another
resident source/region; it remains Step 5 work. This preserves contact coverage
rather than interpreting a camera refactor as permission to pan into missing
data. No source ordering or source data changes are part of this adapter.

`Step2-SitePack.xcresult` passes **65 focused tests**, zero failures/skips.
Pack-frame coordinate round trips across its nine centre/corner samples pass
below 0.000001 m. Bounds tests exercise the real manifest and focus landmark,
verify the 128 m collar in source coordinates, and switch the same camera to
the existing global region bound. Inspection calibration leaves an interactive
camera unchanged. Existing saved views beyond the measured collar now clamp
to that support bound on restore, through the existing shared pan method.

The ordinary Release build succeeds; executable SHA-256 is
`6f5a320a5220eaa7f3f04830ffa578a7b0efd847b41777f318551c8d82c3716d`.
All five protected method bodies and all eleven terrain resource hashes remain
unchanged. The old globe texture API deprecation and elevation-store Sendable
warning remain outside this camera change. The capture and restore evidence
for this executable follows below.

`Step2-SitePack-Apollo` passes **11/11 byte-identical PNGs**, with the same
20-second, one-attempt, pinned-64-ppd protocol. All settled p95/p99/max windows
are 16.67 ms with zero missed callbacks; footprint is 290.8–363.9 MiB against
the baseline's 311.5–380.8 MiB. Across all 33 windows: 290.8–365.0 MiB footprint,
1,603.4 MiB lifetime peak, maximum mean 19.40 ms, p99 124.42 ms and maximum
callback interval 306.55 ms. The baseline gate passes; those single-run numbers
do not establish a general improvement or close physical-device pacing.


`Step2-SitePack-Journey` completes all eleven stages. Every PNG was inspected
individually: disk shows the whole Moon and flags; clipped shows the enlarged
sphere cut by the frame; crossfade and handoff retain terrain coverage without
an open black gap; terrain shows low-contrast near-noon relief behind the frame;
immersion removes the room/frame and exposes Leave immersion; return restores
the room/frame at the same terrain view. Pinch-start/end show 180 → 90 m
altitude around the picked terrain point. Pan-before/after show the requested
40 m east translation across the 32 m tile grid. Broad triangular facets remain
visible in those close views. This is not an unqualified seam-free visual pass.

The prepared exact-triangle pick takes **0.296 ms**. The integration probe logs
maximum perpendicular ray error `0.000000 m` (six-decimal precision) and passes
the <0.0001 m scene-space bound. These are simulated gesture inputs, not tracked
hand measurements. Across 59 frame windows: 116.0–400.7 MiB footprint,
1,618.1 MiB lifetime peak, maximum mean 19.88 ms, p99 109.67 ms and maximum
callback interval 587.74 ms. Loading/publication hitches remain; the faster
prepared pick does not establish an entry-time or device frame-rate improvement.


The final restore run is `Step2-SitePack-Restore-Soak`. Its five initial PNGs
were inspected individually: globe shows the disk and catalogue markers;
selected shows the Apollo flag; the legacy-named immersive stage shows the
panned 180 m terrain inside the portal; returned shows that coordinate on the
globe; restored returns to the saved terrain pose. The latter displays
“Selected location”, as the saved coordinate is offset from the named site.

The automatic `passed-over-60s.sample.txt` covers the ongoing cycle sequence.
The main thread is waiting in `mach_msg2_trap` in 3,238 of 3,445 samples (94.0%).
Scene stepping appears briefly; no SwiftUI observation update-loop stack is
present. The initial sandbox launch could not access CoreSimulator services;
the ordinary approved Simulator-access retry ran the capture. This was a
harness-access failure before app launch, not an application timeout.


All **five cycles pass**, with exact camera/sunlight state and persistence
reload. Surface footprint is 391.61, 391.64, 391.71, 391.67, 391.61 MiB;
returned footprint is 392.52, 392.49, 392.80, 392.72, 392.55 MiB. The lifetime
peak stays at 1,595.4 MiB. There is no monotonic retained-memory increase in
these checkpoints. Across all 94 windows: 94.0–492.9 MiB footprint, maximum
mean 19.67 ms, p99 129.65 ms, maximum callback interval 170.15 ms. These
Simulator CADisplayLink intervals do not measure headset GPU frame time.

The site-pack adapter's focused-test, protected-Apollo and restore gates pass.
Step 2 implementation is complete with the measured-coverage correction above;
close-view faceting remains an open visual issue. Steps 4–6 are not started.
The five-cycle test exercises navigation inside the same space, not actual
ImmersiveSpace close/reopen. Physical Vision Pro gesture comfort/accuracy,
tracking loss/cancellation, portal placement/stencil cost, space lifecycle,
90 Hz pacing and memory pressure remain open. Cold pick/index preparation and
global surface picking still need profiling; the retained Apollo triangle
index/buffers cost about 69.7 MiB. Entry/publication hitches and texture peaks
remain future work. Owner document edits, both scheme-user files, all eleven
terrain resources and the separate AGC checkout are preserved.


## Owner review follow-up A: lighting, 2026-09-07

This run starts from `f81410c`. The owner authorized A–F and made matched
Simulator performance a landing gate. Evidence is under
`/tmp/LM-Explorer-OneZoom-2026-09-07/`. Only the specified visionOS Simulator
was booted before the control captures; no XCTest clones were active.
Control A is a frozen copy of the prior ordinary Release app, executable
SHA-256 `6f5a320a5220eaa7f3f04830ffa578a7b0efd847b41777f318551c8d82c3716d`.

The control seven-stage journey and five-cycle soak pass. Every image was
inspected individually. Disk shows the large black portal behind the Moon;
clipped fills the frame with the WAC map. Crossfade is blurred; handoff at
42.8 km altitude shows faint crater outlines on a grey field. The 7.5 km
terrain stop is nearly uniform grey, as are immersion and return. In the soak,
globe/selected show the disk and Apollo flag, immersive/restored show the same
panned terrain pose, and returned shows its coordinate on the globe. All five
cycles preserve camera and sunlight exactly. The over-60s sample has 3,375 of
3,602 main-thread samples waiting in mach_msg2_trap, with no SwiftUI update loop.

| Control workload | Footprint MiB | Lifetime peak MiB | Max window mean ms | Max window p99 ms | Largest callback ms | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Journey | 95.2–364.8 | 1595.9 | 18.38 | 110.12 | 168.03 | 15 |
| Five-cycle soak | 94.1–470.1 | 1595.5 | 19.67 | 115.86 | 163.54 | 111 |

Control surface checkpoints are 390.42, 390.53, 390.61, 390.61, 390.66 MiB;
returned checkpoints are 391.39, 391.38, 391.96, 391.97, 391.97 MiB. The
original per-checkpoint kernel peaks and phase durations remain in metrics.json.

The first 66-test candidate run found a pre-load radiance regression: an
unresolved site used the browse coordinate, which could be night-side. The
correction retains the 5.70 reference until a site coordinate resolves.
The candidate does not yet have a landing pass.

Candidate iteration 1 passed all 66 focused tests after that correction, and
all eleven Apollo ladder PNGs are byte-identical in `A/Apollo`. Its final
surface capture settled for 90 seconds; the last twelve five-second windows
all report 16.67 ms mean/p99/max with no missed callbacks. Executable SHA-256
is `3af3e17e662a2109f8b566f540d2c22f0e9d44741c8a340907e988d86a878683`.

Its seven journey PNGs were inspected. Crater interiors and rims are clearer
at the 42.8 km stop, but the 7.5 km stop remains too flat. Place selection
was retaining the daylight date chosen for the initial browse coordinate.
Iteration 2 retargets the active daylight preset when selecting a place,
while manual date edits and saved-view restoration retain their exact instant.
All 67 focused tests pass for that revision in `A/Tests-Selection.xcresult`;
ordinary Release SHA-256 is
`766a963aa5fc0d0ac900db970df2548904ffcbc89f4e0b7a637b080af6d81ca0`.

Iteration 1 fails the matched journey performance gate. Footprint is
118.4–384.8 MiB, lifetime peak 1621.1 MiB, maximum window mean 19.46 ms,
p99 109.26 ms, largest callback 444.96 ms, and 16 hitches over 25 ms.
The largest callback occurs during the monolithic texture interval, which
takes 1618.67 ms versus 1486.63 ms in control. Peak and hitch count both
increase; this is not accepted as noise or an improvement. No commit lands
on those numbers. The source change adds no texture or terrain allocation,
but that inspection alone does not explain the measured increase.

The initial isolation harness incorrectly selected the tilted Orbit preset;
`A/Isolation-Selection` is rejected framing evidence. The corrected harness
uses the original globe preset, 30000 m altitude and 210000 m width, with
90 seconds per layer. The earlier radiance report is in
`LandAnywhereMoonPlan.md`, not `MoonExplorerExperience.md`. It records a
0.376% difference but no explicit tolerance. This run uses a stated 1%
acceptance limit and records its central ROI, rather than treating that
limit as an existing plan quotation.

The central 80% crop reproduces the earlier mission numbers to the recorded
precision: globe 0.133984, site 0.134490, ratio 0.996238. At 25 degrees the
flat-ground model gives globe 0.133984 and site 0.137054, ratio 0.977600,
a 2.240% mismatch. `A/Isolation-Registered/luminance.json` records the
3072-by-1728 ROI at (384,216), linear RGB conversion and luminance weights.
Both globe images show the same blurred mare/crater features. Mission terrain
shows dark crater interiors and brighter rims; 25-degree terrain retains those
features with less severe interior shadow and slightly higher mean radiance.

A measured v1 relief response interpolates that 1.906% terrain-luminance change
over 10.689–25 degrees, multiplying the existing illuminance model. Beyond the
measured interval it holds the endpoint response; those angles are unvalidated.
The mission reference's 0.001-degree rounding cell remains exactly 5.70. A
focused test caught a 0.00000263 drift before that rounding correction. The
final 67-test run passes (`A/Tests-Exact-Mission.xcresult`). The frozen calibrated
Release executable SHA-256 is
`ab9bbf279ef0ca677121bf005ba21feffc2c5c6d74c897dac3bac9c989b7304a`.

All seven calibrated journey images were inspected. Disk still has the old
large black portal. Clipped shows mapped craters; crossfade remains blurred.
At 42.8 km, crater walls now have discernible light and dark sides. At 7.5 km,
small crater rims and broader low hills are visible in the central/right field.
Immersion and return preserve that relief while removing/restoring the frame.
These are low-contrast mare views, not highland-like relief.

The calibrated journey still fails performance: 116.7–382.8 MiB footprint,
1619.0 MiB lifetime peak, maximum mean 20.04 ms, p99 105.56 ms, largest callback
664.25 ms, and 18 hitches over 25 ms. It is withheld, with the exact source/test
patch in `A/implementation.patch`. The source patch was removed from the working
tree before B implementation validation. Revisit it after the texture load is
cheaper, rather than committing on an unexplained startup regression.

Final isolated radiance passes at both elevations. With the same 80% ROI,
mission globe/site means are 0.133984/0.134490, ratio 0.996238 (-0.376%).
At 25 degrees they are 0.136585/0.137054, ratio 0.996578 (-0.342%). All four
`A/Isolation-Calibrated` images were inspected individually. Mission images
retain their prior appearance; the corrected daylight globe is slightly brighter
and now matches the daylight terrain's mean. Compositing compensation is unchanged.

| A matched workload | Footprint MiB | Lifetime peak MiB | Max window mean ms | Max window p99 ms | Largest callback ms | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Control journey | 95.2–364.8 | 1595.9 | 18.38 | 110.12 | 168.03 | 15 |
| Calibrated candidate journey | 116.7–382.8 | 1619.0 | 20.04 | 105.56 | 664.25 | 18 |
| Control five-cycle soak | 94.1–470.1 | 1595.5 | 19.67 | 115.86 | 163.54 | 111 |
| Calibrated candidate five-cycle soak | 94.0–393.6 | 1595.3 | 19.60 | 117.41 | 287.71 | 126 |

Candidate surface checkpoints are 390.96, 390.92, 390.91, 391.00, 390.96 MiB;
returned checkpoints are 392.11, 392.14, 392.14, 392.19, 392.21 MiB. The kernel
peak remains 1595.30 MiB at every checkpoint. All five exact camera/sunlight
cycles and persistence reload pass. All five soak images were inspected:
globe and selected show the disk and Apollo flag; immersive/restored show
the same panned 180 m terrain, with rocks and crater shading; returned shows
that saved coordinate on the globe.

The final `A/Apollo-Calibrated` ladder is **11/11 byte-identical** to the
September 4 v2 baseline. The last capture settled for 90 seconds; its last
twelve five-second windows have 16.67 ms mean/p99/max and zero missed callbacks.
All eleven pinned terrain resource hashes remain unchanged in
`A/terrain-assets.json`. Four protected bodies remain exact in the candidate;
only the explicitly requested radiance-factor lookup changes the fifth.
After withholding A, all five bodies again match `f81410c` exactly.

A is **not landed**. The visual/radiance, test and Apollo gates pass; the
matched performance gate fails. Single runs do not establish a general
improvement, and smaller soak footprint does not cancel its additional hitches.
The smallest next route is to remove the monolithic texture cost in E and then
retest the retained lighting patch, while continuing B/C independently.
Physical visual comfort, binocular handoff, tracked gestures, head motion,
space lifecycle, GPU frame pacing and memory pressure are all unvalidated.
No physical Vision Pro was used.

## B — Free-standing disk and smaller portal: withheld (2026-09-07)

Evidence is under `/tmp/LM-Explorer-OneZoom-2026-09-07/B/`. The implementation is withheld in `implementation-contact.patch`; only this evidence and status update are committed.

Candidate implementation uses a 1.6 × 1.1 m portal at the existing 2.17 m nearest-surface depth. Interactive width calibration is 1.6 m; explicit reference captures retain their 3 m calibration and do not use the portal. The disk, pins and label are parented to the room root until their projected limb first reaches the rounded frame. Reparenting applies the identical world transform. The frame is a border ring, fading in over the next 0.1375 m of projected overflow. Settings placement still enters the same projection and transform calculation.

Two assumptions needed correction. A circular disk with diameter equal to a rectangle's height cannot cover its corners: the initial numerical example left 42.3% of the full rectangle uncovered. The portal aperture therefore intersects the sphere silhouette with the rounded frame until the sphere covers the whole frame. Also, the off-axis globe's projected center is displaced from the frame center. Switching on diameter alone clipped its top abruptly. The final switch uses the first actual frame contact, including rounded corners, rather than assuming concentric projection.

The first silhouette candidate incorrectly used the synthetic gesture-probe eye at 1.45 m. It exposed a black crescent below the disk. The render-camera calibration at 1.60 m removes that crescent; hardware uses the tracked eye and remains unvalidated. The initial captures are retained in B/Switch-Journey and B/Switch-Eye rather than overwritten.

Final executable: 15b0a7b592e753ee86f19433fe29b0ecee722382d514502692521bff8b3735d2 (B/Candidate-Contact.app). Control: 6f5a320a5220eaa7f3f04830ffa578a7b0efd847b41777f318551c8d82c3716d (B/Control.app), production code from f81410c, unchanged by the preceding documentation commit 6b87f68. B/Tests-Contact.xcresult: 68 passed, zero failed/skipped. An earlier compilation failure from a Float/Double conversion was corrected; B/Tests-Corrected.xcresult also passed 68 tests before the camera/edge correction.

Inspected B/Switch-Contact images individually. Disk is free-standing with room visible around its limb. Switch-before (4,211,610.403212 m across) and switch-after (4,203,195.597211 m) straddle the approximately 4,207,403 m contact threshold: no visible crescent or positional jump; flags and label remain registered. Clipped fills the smaller rounded frame with mapped craters and a narrow dark border. Crossfade remains visibly blurred. Handoff at 42.8 km and terrain at 7.5 km retain the existing weak/noon relief because A is withheld. Immersion removes the room/frame, and return restores the same terrain framing.

The eleven `B/Apollo` PNGs are byte-identical to `/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2`. The final Surface capture waited 90 seconds; its last twelve five-second windows have mean/p99/max 16.67 ms and zero missed callbacks, at 357.0 MiB footprint. The eleven pinned resource digests and five protected method bodies remain unchanged.

Matched Release measurements, using the original seven-stage workload (not the added switch stages):

| Run | Frame-window footprint MiB | Lifetime peak MiB | Max window mean ms | Max window p99 ms | Largest callback ms | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Control journey | 116.6–383.1 | 1619.378 | 19.61 | 106.37 | 571.46 | 19 |
| Control soak | 115.9–632.2 | 1618.972 | 19.75 | 123.29 | 528.71 | 118 |
| Candidate journey | 117.9–384.3 | 1620.582 | 19.19 | 86.08 | 480.11 | 16 |
| Candidate soak | 111.5–408.5 | 1614.363 | 19.75 | 115.12 | 504.45 | 116 |

Both apps were explicitly terminated and left closed for ten seconds before each run. This is a harness normalization, not a runtime optimization. No builds, tests, or offline generation overlapped captures. Source preparation in Xcode overlapped the control runs; host activity was not fully isolated, and these single runs do not establish a causal improvement. The candidate is withheld regardless.

Control surface checkpoints: 407.57, 407.50, 407.52, 407.61, 407.67 MiB.

Control returned checkpoints: 408.88, 408.83, 408.86, 408.86, 408.86 MiB.

Candidate surface checkpoints: 407.14, 407.00, 407.24, 407.28, 407.24 MiB.

Candidate returned checkpoints: 408.42, 407.96, 408.30, 408.38, 408.30 MiB.

All five cycles restore camera and sunlight exactly, including persistence reload. The candidate soak's five initial images were inspected: globe shows the free-standing disk at 0°, 0°; selected shows the Apollo flag; immersive shows the panned 180 m terrain with small craters/rocks in the smaller frame; returned shows that coordinate on the disk; restored shows the same terrain pose.

**Landing decision: withheld.** Journey peak rises by 1.203 MiB despite fewer measured hitches. The extra allocation is already present at `globe-start`: 119,490,912 bytes versus 118,376,776 bytes, before the large decode. This localizes the difference to startup but does not prove its allocation owner. The soak's lower peak does not cancel the journey gate. The smallest next experiment is lazy portal mesh/frame realization at the first actual switch, followed by the same matched measurements; keep the corrected projection and captures. Continue with independent item C as requested.


Unvalidated: all physical Vision Pro behavior, stereo silhouettes, tracked head movement, pinch recognition/comfort, device memory/GPU pacing, portal stencil cost, and real space/window lifecycle. Simulator camera calibration is not a claim about the device's eye position.
