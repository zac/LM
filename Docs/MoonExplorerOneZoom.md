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

## C: Height-field gesture anchor, withheld, 2026-09-07

Evidence: `/tmp/LM-Explorer-OneZoom-2026-09-07/C/`. The tested source patch is retained as `implementation.patch` and removed from the checkout. This item removes the entity triangle-index cache, mesh-buffer extraction and LunarExplorerTriangleIndex. Apollo gesture picking marches resident measured grids in Double precision and retains source-frame anchors. Contact and rendered geometry do not change. The near grid is shared; the two outer grids add 2,105,352 bytes of scalar heights. The previous roughly 69.7 MiB index and its detail variants are absent from candidate checkpoints.

The real Apollo pick takes 0.018416 ms. The 61-step anchored pinch passes a 0.0005 m scene-space bound. The source's 1 cm height quantum projects to 0.000081 m at the probe scale; 0.5 mm allows interpolation and transform rounding. The maximum logged anchor error rounds to 0.000000 m at six decimal places. This bounds anchor retention, not the distance to procedural detail or rocks, which the gesture picker intentionally does not sample.

Release tests: 66 passed, zero failed/skipped in `Tests-Edges.xcresult`. The initial run passed 65 and failed one test: a vertical ray exactly on an ownership-hole edge selected only the unowned adjacent cell. The fix checks both adjoining cells for rays parallel to grid lines. Tests compare against an independent brute-force triangle oracle, including oblique/grazing rays, hole boundaries, nested bands and regional-distance precision. The original failure remains in `Tests.xcresult`.

Candidate executable SHA-256: `16d48cb3a396e393ea9c83a4db88fc9b916f393c66b9be320bb9073e13bda151`. Control SHA-256: `6f5a320a5220eaa7f3f04830ffa578a7b0efd847b41777f318551c8d82c3716d`. The control contains the production code from f81410c, unchanged by the preceding documentation-only commits. Both frozen apps were terminated for ten seconds before each matched run. Source edits, builds, tests and offline generation were paused throughout this pair. Only the target Simulator was booted.

| Run | Frame-window footprint MiB | Lifetime peak MiB | Max window mean ms | Max window p99 ms | Largest callback ms | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Control journey | 115.9–382.8 | 1618.488 | 19.80 | 85.64 | 562.17 | 18 |
| Candidate journey | 119.1–322.6 | 1621.128 | 19.26 | 95.08 | 409.50 | 13 |
| Control soak | 117.1–412.5 | 1620.082 | 19.60 | 125.01 | 207.57 | 115 |
| Candidate soak | 118.2–405.5 | 1621.441 | 19.44 | 110.12 | 534.04 | 94 |

Control surface checkpoints: 410.081, 410.065, 410.112, 410.159, 410.097 MiB. Returned: 411.206, 411.128, 411.175, 411.097, 411.128 MiB.

Candidate surface checkpoints: 346.143, 346.159, 346.128, 346.221, 346.221 MiB. Returned: 347.503, 347.518, 347.487, 347.487, 347.565 MiB. These repeat the surface/returned locations used by Step2-SitePack-Restore-Soak. Each app retains its reported lifetime peak at every checkpoint. All five camera/sunlight restore cycles and persistence reload pass.

Inspected all four `Gestures` images: pinch-end enlarges the crater pair and rocks from 180 m to 90 m altitude; pan-before/after translate those landmarks without a visible seam. All seven `Candidate-Journey` images were inspected: disk retains the black portal, clipped shows mapped craters, crossfade is blurred, handoff/terrain retain weak noon relief, and immersion/return remove and restore the frame at the same terrain pose. All five `Candidate-Soak` images were inspected: globe is the default coordinate, selected has the Apollo flag, immersive/restored show the same panned 180 m crater/rock field, and returned shows its saved coordinate on the Moon.

Landing is withheld. Journey peak rises 2.641 MiB and soak peak 1.359 MiB during the unchanged globe decode, before gesture height fields are prepared. The soak's largest callback also rises. The lower retained footprint and fewer hitches do not cancel those measurements. These single runs do not establish a general performance improvement. The smallest next route is to retest this retained patch after E removes the dominant monolithic decode; do not claim that changing the picker alone reduces lifetime peak.

Unvalidated: every physical Vision Pro gate, including hand/gaze recognition, head-tracked anchor precision, comfort, stereo appearance, device memory pressure, GPU/compositor pacing and space lifecycle. No physical device was used.

C/Apollo passes all eleven byte comparisons against the September 4 v2 baseline. Its final Surface capture settled for 90 seconds. The last twelve five-second windows have 16.67 ms mean/p99/max and zero missed callbacks, at 351.5–351.6 MiB footprint. All eleven pinned terrain digests and all five protected function bodies remain unchanged.

## D: Coarse-first terrain and prefetch, withheld, 2026-09-07

Evidence: `/tmp/LM-Explorer-OneZoom-2026-09-07/D/`. The complete source patch, including new tests and the common highland driver, is retained in `implementation.patch` and removed from the checkout. No D runtime changes land.

The candidate starts cancellable source resolution and a 512 m generation below 600 km, adopts that prepared generation at the handoff, and publishes subsequent levels separately. Siblings run two at a time, with every parent level complete before its children. Existing ownership, morph, contact publication and floating-origin behavior remain intact. A new immutable parent-resolution table and allocation-free ownership search remove per-sample temporary grid arrays while preserving source order and arithmetic.

Release validation: 78 passed, zero failed in `Tests-SourceSelection.xcresult`. Coverage includes concurrent versus serial mesh positions/normals/indices, uncancelled coarse-first progression, and bit-exact comparison with the former source-selection algorithm across interiors, overlap halos, edges and native posts at seven sample spacings. Measured elevation, residual, cap, resolution and source ID match. The initial compile failure and corrected 68-test run are preserved.

Control executable SHA-256: `a3c13361703b742c5a52d3610eb3322ad2e8846fac67e1cf9f9d3af0ae5091d0`. Candidate: `52018dd2c744488315b8efb85ad9dfeee826a90dbdbf1a9476acb929d9d9c9b9`. Control uses the preceding production code plus the same diagnostic-only highland driver as the candidate, recorded in `control-instrumentation.patch`. It is not an unmodified prior-commit binary. No source edits, builds, tests or offline generation overlapped the matched acceptance runs. Only the specified Simulator was booted.

| Run | Frame-window footprint MiB | Lifetime peak MiB | Max window mean ms | Max window p99 ms | Largest callback ms | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Control Journey | 118.1–384.4 | 1620.050 | 19.96 | 85.40 | 582.72 | 15 |
| Candidate Journey | 118.8–385.2 | 1621.113 | 19.11 | 111.51 | 461.93 | 18 |
| Control Soak | 116.6–413.6 | 1620.519 | 19.83 | 113.97 | 602.49 | 128 |
| Control Highland Warm | 111.2–149.3 | 1613.972 | 19.48 | 67.21 | 545.80 | 18 |
| Control Highland Cold | 110.8–171.8 | 1613.332 | 19.20 | 68.50 | 509.92 | 20 |
| Candidate Highland SourceSelection (diagnostic, not matched) | 112.2–180.1 | 1614.738 | 19.29 | 83.33 | 486.27 | 19 |

Control surface checkpoints: 410.784, 410.815, 410.518, 411.253, 410.706 MiB.

Control returned checkpoints: 413.268, 413.409, 413.300, 412.175, 412.175 MiB.

All five control restore cycles and persistence reload pass. Candidate soak checkpoints are not available: acceptance stopped after the completed candidate journey failed both peak memory and hitch count. Candidate peak increases 1.063 MiB, already during the unchanged globe decode, and hitches increase from 15 to 18. Its smaller largest callback does not cancel those failures. These are single runs, not evidence of a general causal improvement or regression.

The initial two-sibling candidate took 8.807 seconds to prefetch and missed the 240 km handoff. The aligned `coarse-concurrency.sample.txt` identified frequent Swift retain/release and temporary source-array work. The allocation-free selection candidate reduced diagnostic prefetch to 3.215 seconds. It completed at 12:20:17.817, before the 240 km crossing at 12:20:18.448; adoption followed at 12:20:18.452. The crossing log itself has zero visible tiles because it precedes the scene update. It did not wait on a CPU build. This is one diagnostic dive, not the completed matched warm-dive gate.

| Regional 16-tile build | 512 m sum | 128 m sum | 32 m sum | 8 m sum | Total ready time |
|---|---:|---:|---:|---:|---:|
| Matched control warm | 797 ms | 827 ms | 892 ms | 984 ms | 6.208 s |
| Candidate diagnostic after source optimization | 1208 ms | 1179 ms | 1207 ms | 1260 ms | 6.482 s |

These sums are the existing per-tile CPU mesh preparation wall intervals; concurrent intervals overlap and must not be called CPU utilization. The candidate's initial 16-tile 512 m generation sums 5356 ms and publishes in 3136 ms. The subsequent four-tile 128 m refinement sums 1198 ms and completes its generation in 2419 ms. The initial slower candidate's regional ready time was 12.736 seconds. All logs and the failed candidate binary remain available.

The control warm dive published its initial 20 tiles in 5049 ms, about 5.14 seconds after the 240 km crossing. Cold control resolved all sources with zero missing slabs and published about 10.54 seconds after crossing; its regional ready time was 6.530 seconds. Globe/site endpoints at both crossings were 1/0. The cache was moved aside, preserved and restored for the cold run. A matched candidate cold run was not performed after the journey gate failed.

Inspected all seven candidate journey images individually. Disk retains the black rectangular portal; clipped shows mapped crater rims; crossfade is conspicuously blurred; handoff at 42.8 km has very weak relief; terrain at 7.5 km remains a nearly uniform grey field with faint craters; immersion removes the room/frame; return restores the same framing. The diagnostic highland overlap shows blurred hills and craters; its regional and final settled views show broad low-contrast hills without a black hole. The final diagnostic highland image follows a 90-second settle. The final twelve logged windows have 16.67 ms mean/p99, a 20.98 ms largest callback and zero missed callbacks, at 136.2–136.3 MiB footprint.

The eleven pinned resource hashes and five protected bodies remain unchanged in the candidate and restored checkout. D's Apollo ladder, final Apollo settled check, candidate restore soak and matched warm/cold highland acceptance remain unvalidated because the journey gate stopped this item. No Apollo identity pass is inferred from unchanged source files.

Smallest next route: retain the source-selection optimization and prefetch patch, remove the dominant texture decode in independent E, then repeat D's complete matched suite against that cheaper baseline. The initial parallelism experiment was slower and is not proposed as a stand-alone improvement. F remains gated on D and E landing.

All physical Vision Pro behavior is unvalidated: tracked gestures, stereo handoff and relief, comfort, head motion, device CPU/GPU pacing, memory pressure and space lifecycle. No physical device was used.

## E: Tiled globe imagery, withheld, 2026-09-07

Evidence: `/tmp/LM-Explorer-OneZoom-2026-09-07/E/`. No E runtime or resource changes land. The complete final candidate is preserved in `implementation.patch` (including the binary coarse base) and `Source/`, with per-file digests in `source-sha256.json`. `git apply --check` passes against the restored checkout.

The candidate replaces the interactive monolithic decode with a pinned 5760 × 2880 Display P3 coarse companion and view-selected 32/64 ppd tiles. The 16 ppd PNG and explicit texture-tier/inspection arguments retain their existing path. The original 64 ppd JPEG XL remains bundled and unchanged for deterministic Apollo captures and later device comparison. The new bundled companion is 16,125,401 bytes (15.378 MiB); its manifest is about 0.39 MiB. This is within the new E scope's explicit authorization to bundle a coarse base, not a reinterpretation of the earlier elevation-only 32 MiB approval.

Offline generation produced 2,560 canonical R8 tiles with 360-pixel interiors and two-pixel gutters: 512 at 32 ppd and 2,048 at 64 ppd. The generator and runtime share the exact source transfer function, box reduction, longitude wrapping and polar clamping. Runtime reconstructs missing tiles from verified PDS source-row slabs, then verifies the resulting tile hash against the offline manifest. Fine tiles are not all bundled or hosted on a new server. The independent imagery store bounds source slabs to 128 MiB, derived tiles to 32 MiB and resident GPU textures to sixteen. An offline cache miss keeps the previous verified map; cached slabs can reconstruct evicted or corrupt derived tiles without a fetch. Cancellation drains prior source work before a new request begins.

This experiment adapts W2's pinned tile-pyramid/residency design to the existing equirectangular sphere instead of adding a cube-sphere mesh. Each fine patch owns exactly the same original triangles that its coarse remainder relinquishes in one publication. Positions, normals, source-frame coordinates and opaque material endpoints stay unchanged; no skirts, offsets, new terrain geometry or ShaderGraph materials are involved. A cube-sphere conversion and screen-error-driven geometric subdivision remain outside this experiment. This adaptation preserves the accepted capture geometry; it does not claim completion of every original W2 subtask.

Provenance is preserved in the patch's `LunarImageryPyramid.json` and `generator-provenance.json`:

- Pinned WAC Float32 IMG: `bc1feab6e86ae2cf47798a4f00cdf7f5e73030fcbc2223fba7fab59a5a2a34ec`, 1,061,775,360 bytes; 23,040 × 11,520 samples after a 92,160-byte label. Ninety independently hashed source slabs contain at most 128 rows each.
- Unchanged bundled JPEG XL: `819ca84afedca9a5fe864a0a3a036bc6384a105f21135614c90808c184355841`.
- Coarse companion: `840379f0f6cc9311e3674086579bce2a6cc8bd30d822cb1e63e3200e2bc2303e`. It preserves the actual Simulator GPU import pixels from `/tmp/LM-Texture-Publication-2026-09-06/ExportGPUBase.swift` and `GPU-Import/GlobeImport-0.lzfse`; that earlier folder contains the export provenance. Its `.pngdata` extension prevents Xcode's PNG optimizer from rewriting the pinned bytes.
- Pyramid manifest: `142a5dc06d20f405283460ace716c651f6856abe26c10112216f14910ccb6667`. Generator and shared conversion hashes are recorded separately in `generator-provenance.json`.

The pinned PDS URL now redirects to NASA's archive. A followed HTTP 206 request returned the exact requested 92,160-byte row, the expected total length and bytes identical to the local pinned source (`range-follow.headers`, `range-follow.bin`). Every runtime slab and derived tile still requires a hash match; a redirect does not relax provenance.

Release validation before the scheduling revision: **79 tests passed in eight suites**, zero failed, `Tests-Final.xcresult`. Tests cover manifest/bundle hashes, native and reduced tile generation, dateline/pole selection, complementary triangle ownership, source-to-texture V mapping, offline reconstruction and corrupt-cache recovery. An earlier packaging test failed because Xcode rewrote a `.png` asset; changing only its container extension fixed the hash mismatch. The final scheduling revision built successfully (`paced-build.log`) and completed its integration journey, but the unit suite was not rerun after the failed performance gate. Do not attribute all 79 tests to that later executable.

Control executable SHA-256: `a3c13361703b742c5a52d3610eb3322ad2e8846fac67e1cf9f9d3af0ae5091d0`. First acceptance candidate: `9b7de193fa95397d20d8926fc62e08deb725b52237b34a2b875241fde360dbb0`. Frame-paced candidate: `8fb1decffb7339b860fe16ad61479fa822cc5057f72bcbd98d4db75b7d44bf4a`. The frozen control is the preceding production implementation plus the common diagnostic highland driver from D; `D/control-instrumentation.patch` records that instrumentation. D itself did not land.

All runs use Release, Xcode 26.6 and the specified visionOS 26.5 Simulator. Builds, tests and captures ran serially; only the target Simulator was booted. Each workload terminated the prior app and waited ten seconds before launch. The same frozen control journey is compared with both candidates; it was not rerun immediately before the scheduling revision. These single runs do not establish a general causal improvement or regression.

| Run | Frame-window footprint MiB | Lifetime peak MiB | Max window mean ms | Max window p99 ms | Largest callback ms | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Control journey | 111.9–379.2 | 1614.144 | 18.92 | 111.29 | 444.28 | 15 |
| First candidate journey | 118.9–388.4 | 621.690 | 19.19 | 115.38 | 444.65 | 20 |
| Frame-paced candidate journey | 118.0–387.5 | 620.815 | 19.12 | 86.25 | 441.48 | 17 |
| Control five-cycle soak | 117.8–414.2 | 1620.457 | 20.02 | 121.05 | 335.84 | 129 |

The p99 column is the maximum five-second-window p99, not a percentile pooled across the run. Hitches count the individual logged callbacks above 25 ms.

Control surface checkpoints: 410.784, 410.706, 410.706, 410.831, 410.847 MiB. Returned: 412.081, 412.050, 412.050, 412.034, 412.050 MiB. All five restores and persistence reload are exact. Candidate surface/returned checkpoints are unavailable: the first journey failed, and the already-running control soak was allowed to finish before the revised candidate was built. The revised journey also failed, so candidate soaks and matched highland dives were not launched. The prepared serial driver and cache-preserving cold-dive script remain in E for resumption; they are not evidence that those runs occurred.

The globe-texture interval is 1372.826 ms in control, 210.664 ms in the first candidate and 199.085 ms in the paced candidate. At its completion, kernel lifetime peaks are 1614.144, 263.424 and 262.424 MiB respectively. Later Apollo preparation raises candidate lifetime peaks to 621.690 and 620.815 MiB. Thus the measured journey peak is more than halved, but retained frame-window footprint is not lower. The control soak's texture interval was 2355.482 ms; it is reported separately rather than substituted for the matched journey control.

The initial candidate imported nine textures and ten meshes during Apollo's base import. Frame pacing gives that import priority and waits for actual `SceneEvents.Update` events between imagery imports; `Task.yield()` had allowed several imports inside a single frame. Texture uploads then occurred roughly one frame apart and the fine map published at 14:16:51.633. Hitches fell from twenty to seventeen, still above control's fifteen. The final two excess callbacks occur in the arrival interval; timing overlap is not an allocation or causality proof. Lower memory, lower p99 and a slightly lower largest callback do not cancel the failed hitch-count gate.

Visual inspection covered all seven `Candidate-Paced-Journey` images. Disk retains the black portal and Apollo flag. Clipped shows the original broad crater field. Crossfade now resolves small crater rims, narrow ridges and branching channels while retaining the large landmarks. Handoff at 42.8 km still has weak, blurry noon relief; 7.5 km remains a nearly uniform grey terrain field. Immersion removes the room/frame; return restores the same terrain pose. E does not conceal the withheld A/B failures.

The final fixed disk and 210 km overlap are in `Fixed-Paced/`, each after 90 seconds. The disk PNG is byte-identical to the September 4 v2 baseline: zero pixel error, hence infinite PSNR, exceeding the prior accepted 64.75 dB result. The overlap is visibly finer than the blurred baseline: the upper-right crater has a defined rim, the middle crater pair retains position, and thin diagonal ridges and small pits are distinct. The final overlap is byte-identical to the corrected `Fixed-UV` diagnostic image. Both before/after originals remain available; no edited image is used as acceptance evidence.

Earlier `Fixed-Probe`, `Fixed-Origin` and `Fixed-FileImport` images were rejected. Flipping local image rows alone removed a stripe but displaced landmarks. A file-import probe was byte-identical to the original CGImage upload, ruling out that API choice as the cause. Matching both the source tile band and local UVs to the whole-texture sampler removed the stripe and displacement. A smoothed comparison reports 0.986579 correlation and best local translation of zero pixels (`uv-registration.json`); the new mapping test checks equivalence within 0.002 source pixels. This preserves the existing base's V convention, not a new coordinate transform or independent geographic-orientation validation.

The final overlap's last twelve five-second windows have 16.67 ms mean, p99 and largest callback, zero missed callbacks, and 307.0–307.1 MiB footprint (`final-settled.json`). All eleven pinned terrain resource hashes and five protected function bodies match in the candidate and restored checkout. The complete E Apollo ladder was stopped with acceptance; byte identity of its other ten PNGs is not claimed from source equality or the disk result alone.

**Landing decision: withheld.** The smallest next experiment is to validate the pinned coarse companion independently, then prepare the bounded fine imagery resources before the arrival interval. That isolates the measured decode improvement from the added import work. A companion-only change would not satisfy E's sharper-overlap gate; the full E gate remains intact and requires a new complete matched suite, including soak, highland dive and Apollo ladder.

All physical Vision Pro gates remain unvalidated: effective texture resolution and color, stereo appearance, head/gaze/hand input, comfort, device CPU/GPU pacing, memory pressure, thermal behavior and space lifecycle. No physical device was used.

## F: Sliding region, not started, 2026-09-07

F explicitly depends on D and E landing. Both failed measured performance gates and remain preserved patches, so no region-sliding implementation or 100 km pan/contact acceptance was attempted. No independent item remains in this A–F run. The production implementation remains the previously landed Steps 1–3; the follow-up commits record evidence and withheld candidates only.

## E revalidation under protocol 2, withheld, 2026-09-07

Evidence: `/tmp/LM-Explorer-OneZoom-2026-09-07/Revalidation/E/`. Candidate source is committed on `onezoom/E` (`b750e58` before rebasing the evidence report); it no longer depends on a temporary patch. No E runtime change lands. The final frame-paced revision was rebuilt and its **79 tests in eight suites passed**, zero failed (`Tests.xcresult`, `tests-summary.json`). The reusable measurement tools have **7 passing tests**, including inclusive decimal boundaries, three-run medians, noise/cap interaction and texture-interval overlap exclusion.

Frozen control executable SHA-256: `a3c13361703b742c5a52d3610eb3322ad2e8846fac67e1cf9f9d3af0ae5091d0`. Candidate: `8fb1decffb7339b860fe16ad61479fa822cc5057f72bcbd98d4db75b7d44bf4a`, byte-identical to the final paced executable from the earlier E experiment. Control remains f81410c production behavior plus the shared diagnostic highland driver documented above; the intervening landing commits change documentation only.

Each workload below alternates Control 1, Candidate 1, Control 2, Candidate 2, Control 3, Candidate 3, terminating and waiting ten seconds between launches. Release/Xcode 26.6/visionOS 26.5 on the specified Simulator; only that Simulator was booted. Builds, app tests and captures ran serially. One lightweight measurement-script unit invocation overlapped an earlier Xcode build/test, before acceptance captures; no build or test overlapped these capture sets.

For the owner's unspecified arithmetic interpretation of “spread,” these tables use control median + (control maximum − control minimum), with the separate peak/hitch caps still applied. This assumption was stated while an optional clarification remained unanswered. Both raw and texture-excluded callback maxima are reported; **E is judged on the raw maximum** because it changes texture loading. The p99 is the maximum five-second-window p99, not a pooled-run percentile. All decisions use completed triplicates. Numeric comparisons allow only 1e-9 arithmetic roundoff at an exact decimal boundary.

**Decision: withheld under revision 2.** Journey passes. Soak fails maximum-window mean (19.91 ms > 19.67 ms noise limit) and p99 (132.42 > 129.24 ms). Warm highland fails maximum footprint (221.9 > 159.5 MiB) and p99 (97.66 > 75.64 ms). Cold highland fails maximum footprint (246.5 > 214.3 MiB) and largest callback (558.14 > 420.47 ms). These are fresh three-run failures, not a reuse of revision 1's withholds. All navigation integration checks passed: thirty repeated restores across the six soaks, plus persistence reload and all twelve highland dives.

The journey lifetime peak median falls from 1620.269 to 621.159 MiB (61.7%). The five-cycle soak reaches 919.144 MiB median, so the journey's 621 MiB value is not a universal lifetime ceiling. Candidate journey outliers include 24 hitches and a 633.90 ms callback; they are retained in the table rather than discarded. Reduced peak and sharper imagery do not cancel the failed metrics.

### journey: passes corrected performance comparison

| Run | Footprint MiB | Peak MiB | Max mean ms | Max p99 ms | Largest ms (outside texture) | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Control 1 | 111.4–378.9 | 1614.066 | 19.49 | 114.33 | 464.24 (183.40) | 18 |
| Candidate 1 | 117.9–387.8 | 621.159 | 18.58 | 88.89 | 287.54 (187.76) | 18 |
| Control 2 | 118.3–384.7 | 1620.269 | 19.74 | 118.51 | 483.42 (150.31) | 18 |
| Candidate 2 | 118.5–387.9 | 621.737 | 18.72 | 89.12 | 187.72 (137.78) | 24 |
| Control 3 | 117.9–385.1 | 1620.285 | 19.22 | 112.85 | 482.33 (127.05) | 16 |
| Candidate 3 | 117.8–386.8 | 620.675 | 20.00 | 85.44 | 633.90 (144.98) | 18 |

| Metric | Control min / median / max | Candidate min / median / max | Noise limit | Additional cap | Pass |
|---|---:|---:|---:|---:|---|
| footprint_min_mib | 111.400 / 117.900 / 118.300 | 117.800 / 117.900 / 118.500 | 124.800 | — | True |
| footprint_max_mib | 378.900 / 384.700 / 385.100 | 386.800 / 387.800 / 387.900 | 390.900 | — | True |
| lifetime_peak_mib | 1614.066 / 1620.269 / 1620.285 | 620.675 / 621.159 / 621.737 | 1626.488 | 1652.674 | True |
| max_window_mean_ms | 19.220 / 19.490 / 19.740 | 18.580 / 18.720 / 20.000 | 20.010 | — | True |
| max_window_p99_ms | 112.850 / 114.330 / 118.510 | 85.440 / 88.890 / 89.120 | 119.990 | — | True |
| hitches_over_25ms | 16.000 / 18.000 / 18.000 | 18.000 / 18.000 / 24.000 | 20.000 | 20.700 | True |
| largest_callback_ms | 464.240 / 482.330 / 483.420 | 187.720 / 287.540 / 633.900 | 501.510 | — | True |

### soak: fails corrected performance comparison

| Run | Footprint MiB | Peak MiB | Max mean ms | Max p99 ms | Largest ms (outside texture) | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Control 1 | 117.8–513.0 | 1620.753 | 19.67 | 117.42 | 480.82 (163.04) | 121 |
| Candidate 1 | 117.3–459.0 | 917.394 | 19.91 | 139.02 | 280.31 (280.31) | 118 |
| Control 2 | 110.9–448.3 | 1613.832 | 19.52 | 114.73 | 478.30 (174.98) | 122 |
| Candidate 2 | 111.8–411.9 | 919.144 | 19.67 | 132.42 | 470.90 (167.89) | 120 |
| Control 3 | 118.9–415.5 | 1622.019 | 19.52 | 126.55 | 477.43 (146.29) | 112 |
| Candidate 3 | 117.4–413.3 | 944.316 | 20.15 | 117.99 | 280.36 (176.61) | 116 |

| Metric | Control min / median / max | Candidate min / median / max | Noise limit | Additional cap | Pass |
|---|---:|---:|---:|---:|---|
| footprint_min_mib | 110.900 / 117.800 / 118.900 | 111.800 / 117.300 / 117.400 | 125.800 | — | True |
| footprint_max_mib | 415.500 / 448.300 / 513.000 | 411.900 / 413.300 / 459.000 | 545.800 | — | True |
| lifetime_peak_mib | 1613.832 / 1620.753 / 1622.019 | 917.394 / 919.144 / 944.316 | 1628.941 | 1653.169 | True |
| max_window_mean_ms | 19.520 / 19.520 / 19.670 | 19.670 / 19.910 / 20.150 | 19.670 | — | False |
| max_window_p99_ms | 114.730 / 117.420 / 126.550 | 117.990 / 132.420 / 139.020 | 129.240 | — | False |
| hitches_over_25ms | 112.000 / 121.000 / 122.000 | 116.000 / 118.000 / 120.000 | 131.000 | 139.150 | True |
| largest_callback_ms | 477.430 / 478.300 / 480.820 | 280.310 / 280.360 / 470.900 | 481.690 | — | True |

| Run | Surface checkpoints, cycles 1–5 (MiB) | Returned checkpoints, cycles 1–5 (MiB) |
|---|---|---|
| Control 1 | 412.847, 412.675, 412.628, 412.768, 412.737 | 414.081, 413.862, 413.878, 413.847, 413.893 |
| Candidate 1 | 413.472, 413.534, 413.378, 413.440, 413.550 | 414.628, 414.534, 414.534, 414.487, 414.565 |
| Control 2 | 402.472, 402.409, 402.675, 402.581, 402.659 | 403.378, 403.378, 403.268, 403.300, 403.347 |
| Candidate 2 | 408.643, 408.581, 408.612, 408.643, 408.612 | 409.253, 409.300, 409.315, 409.253, 409.268 |
| Control 3 | 413.878, 413.847, 413.831, 413.893, 413.909 | 415.112, 415.034, 415.050, 415.034, 415.050 |
| Candidate 3 | 411.393, 411.518, 411.472, 411.534, 411.581 | 412.675, 412.753, 412.722, 412.753, 412.706 |

### highland-warm: fails corrected performance comparison

| Run | Footprint MiB | Peak MiB | Max mean ms | Max p99 ms | Largest ms (outside texture) | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Control 1 | 117.2–154.2 | 1620.222 | 19.80 | 68.73 | 562.75 (144.46) | 24 |
| Candidate 1 | 117.6–199.3 | 245.737 | 19.27 | 63.72 | 445.97 (132.85) | 24 |
| Control 2 | 118.0–154.3 | 1620.957 | 19.04 | 75.22 | 457.94 (152.10) | 24 |
| Candidate 2 | 118.2–221.9 | 262.518 | 19.13 | 101.72 | 295.59 (122.71) | 26 |
| Control 3 | 112.0–149.0 | 1614.425 | 19.44 | 68.31 | 483.77 (143.62) | 25 |
| Candidate 3 | 117.4–223.1 | 257.112 | 19.27 | 97.66 | 443.64 (128.14) | 21 |

| Metric | Control min / median / max | Candidate min / median / max | Noise limit | Additional cap | Pass |
|---|---:|---:|---:|---:|---|
| footprint_min_mib | 112.000 / 117.200 / 118.000 | 117.400 / 117.600 / 118.200 | 123.200 | — | True |
| footprint_max_mib | 149.000 / 154.200 / 154.300 | 199.300 / 221.900 / 223.100 | 159.500 | — | False |
| lifetime_peak_mib | 1614.425 / 1620.222 / 1620.957 | 245.737 / 257.112 / 262.518 | 1626.753 | 1652.627 | True |
| max_window_mean_ms | 19.040 / 19.440 / 19.800 | 19.130 / 19.270 / 19.270 | 20.200 | — | True |
| max_window_p99_ms | 68.310 / 68.730 / 75.220 | 63.720 / 97.660 / 101.720 | 75.640 | — | False |
| hitches_over_25ms | 24.000 / 24.000 / 25.000 | 21.000 / 24.000 / 26.000 | 25.000 | 27.600 | True |
| largest_callback_ms | 457.940 / 483.770 / 562.750 | 295.590 / 443.640 / 445.970 | 588.580 | — | True |

### highland-cold: fails corrected performance comparison

| Run | Footprint MiB | Peak MiB | Max mean ms | Max p99 ms | Largest ms (outside texture) | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Control 1 | 117.2–182.9 | 1619.847 | 19.18 | 76.43 | 326.45 (159.82) | 30 |
| Candidate 1 | 118.2–246.5 | 260.815 | 19.47 | 111.11 | 305.18 (164.79) | 25 |
| Control 2 | 117.6–212.9 | 1620.738 | 19.79 | 102.23 | 379.74 (127.96) | 24 |
| Candidate 2 | 117.4–234.8 | 258.424 | 19.78 | 87.06 | 614.56 (128.85) | 20 |
| Control 3 | 117.8–181.5 | 1620.425 | 18.41 | 68.73 | 285.72 (133.00) | 22 |
| Candidate 3 | 118.3–249.1 | 264.612 | 19.65 | 85.14 | 558.14 (136.54) | 19 |

| Metric | Control min / median / max | Candidate min / median / max | Noise limit | Additional cap | Pass |
|---|---:|---:|---:|---:|---|
| footprint_min_mib | 117.200 / 117.600 / 117.800 | 117.400 / 118.200 / 118.300 | 118.200 | — | True |
| footprint_max_mib | 181.500 / 182.900 / 212.900 | 234.800 / 246.500 / 249.100 | 214.300 | — | False |
| lifetime_peak_mib | 1619.847 / 1620.425 / 1620.738 | 258.424 / 260.815 / 264.612 | 1621.316 | 1652.834 | True |
| max_window_mean_ms | 18.410 / 19.180 / 19.790 | 19.470 / 19.650 / 19.780 | 20.560 | — | True |
| max_window_p99_ms | 68.730 / 76.430 / 102.230 | 85.140 / 87.060 / 111.110 | 109.930 | — | True |
| hitches_over_25ms | 22.000 / 24.000 / 30.000 | 19.000 / 20.000 / 25.000 | 32.000 | 27.600 | True |
| largest_callback_ms | 285.720 / 326.450 / 379.740 | 305.180 / 558.140 / 614.560 | 420.470 | — | False |


### Globe-texture intervals and kernel peak markers

| Workload/run | Texture interval ms | Kernel peak immediately after texture MiB | Lifetime peak MiB |
|---|---:|---:|---:|
| journey Control 1 | 1483.926 | 1614.066 | 1614.066 |
| journey Candidate 1 | 473.682 | 263.674 | 621.159 |
| journey Control 2 | 1409.959 | 1620.269 | 1620.269 |
| journey Candidate 2 | 395.726 | 263.143 | 621.737 |
| journey Control 3 | 1397.403 | 1620.285 | 1620.285 |
| journey Candidate 3 | 397.162 | 262.502 | 620.675 |
| soak Control 1 | 1346.790 | 1620.753 | 1620.753 |
| soak Candidate 1 | 467.571 | 262.846 | 917.394 |
| soak Control 2 | 1426.615 | 1613.832 | 1613.832 |
| soak Candidate 2 | 415.263 | 232.627 | 919.144 |
| soak Control 3 | 1411.889 | 1622.019 | 1622.019 |
| soak Candidate 3 | 476.722 | 262.612 | 944.316 |
| highland-warm Control 1 | 1413.391 | 1620.222 | 1620.222 |
| highland-warm Candidate 1 | 477.066 | 245.737 | 245.737 |
| highland-warm Control 2 | 1374.247 | 1620.957 | 1620.957 |
| highland-warm Candidate 2 | 203.165 | 262.518 | 262.518 |
| highland-warm Control 3 | 1518.816 | 1614.425 | 1614.425 |
| highland-warm Candidate 3 | 205.907 | 257.112 | 257.112 |
| highland-cold Control 1 | 1839.506 | 1619.847 | 1619.847 |
| highland-cold Candidate 1 | 529.023 | 260.815 | 260.815 |
| highland-cold Control 2 | 1435.966 | 1620.738 | 1620.738 |
| highland-cold Candidate 2 | 389.023 | 258.424 | 258.424 |
| highland-cold Control 3 | 1353.343 | 1620.425 | 1620.425 |
| highland-cold Candidate 3 | 322.026 | 264.612 | 264.612 |

All eleven fresh `Apollo/*.png` files are byte-identical to `/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2`; all eleven pinned terrain hashes and all five protected method bodies match. `Apollo/comparison.json`, `terrain-assets.json` and `protected-functions.json` record each result. The final Apollo stop waits 90 seconds (despite the helper's generic “20s” log text); its last twelve windows have 16.67 ms mean/p99/max and zero missed callbacks. The final fixed overlap also waits 90 seconds and passes the same values (`Fixed/final-settled.json`).

`Fixed/01-globe.png` is byte-identical to the baseline disk, giving infinite PSNR and exceeding the accepted 64.75 dB comparison. Inspected `Fixed/03-crossfade.png`: small crater rims, narrow diagonal ridges and branching channels remain distinct across the mare. The prior blurred baseline and the new original are both retained. All seven `journey/Candidate-1` images were inspected individually: disk retains the black rectangular portal and flag; clipped fills the aperture with mapped craters; crossfade resolves small pits that the control blurs; 42.8 km handoff has weak, blurred relief; 7.5 km remains mostly gray with faint pits; immersion removes the room/frame; return restores the original pose. A and B remain necessary. Cold candidate arrival and overlap were inspected: a coarse map covers the aperture before fine imagery arrives, without a black loading hole; the later map resolves dark crater interiors and small rims. `inspection-notes.md` names the originals.

The initial cold control completed, but a reinstall rotated its Simulator data-container UUID and the wrapper attempted to restore caches to the stale path. Both original caches were recovered, and newly fetched elevation cache was preserved. The fixed wrapper resolves the live container again on exit. The entire alternating cold set restarted; the interrupted run remains separately labeled under `highland-cold-interrupted/` and is not part of these tables. The app binary did not change.

Smallest next experiment: remove the full-width source-slab concatenation in `LMLunarImageryTileStore.pixels(for:)` and sample verified slabs directly, retaining exact offline tile hashes. This targets a concrete duplicate allocation seen in code; its benefit is not yet measured. Separately test stricter fine-imagery import deferral around Apollo mesh/material publication: all three soak maximum-mean windows overlap that publication, which is evidence for an isolation experiment rather than proof of causality. No such optimization was implemented in this revalidation.

Owner bundle note, no action taken: the original 64 ppd JPEG XL (76,112,646 bytes, approximately 76 MB) remains bundled for deterministic capture alongside the 15.378 MiB companion. Removing it remains an owner decision.

All physical gates remain open: tracked head/hand/gaze input, stereo registration and relief, comfort, effective device imagery resolution/color, CPU/GPU pacing, thermal behavior, memory pressure and space lifecycle. F and the post-F Apollo-peak attribution remain gated on D and E landing. Continue with independent A on the current landed baseline because E did not land.

## A revalidation under protocol 2, accepted, 2026-09-07

Evidence: `/tmp/LM-Explorer-OneZoom-2026-09-07/Revalidation/A/`. A rebased onto `db86a0c`, the current landed baseline; E remains withheld, so this is an independent lighting validation with the original monolithic globe. Iteration 2 is retained: Explorer launch and “Daylight here” target 25° elevation in the existing 30-day window, preferring morning; place selection retargets the active daylight preset. Manual dates and saved views keep their exact instant. The measured relief response and exposure model return exactly 5.70 at the Apollo mission instant; compositing compensation is unchanged.

**74 selected Release Simulator tests passed**, zero failures/skips (`Tests.xcresult`, `tests-summary.json`). Tests include daylight selection, polar fallback, manual-date/saved-view semantics, radiance calibration, navigation, transitions and contact. Ordinary Release build succeeded. Frozen control executable SHA-256: `6f5a320a5220eaa7f3f04830ffa578a7b0efd847b41777f318551c8d82c3716d`; candidate: `ab9bbf279ef0ca677121bf005ba21feffc2c5c6d74c897dac3bac9c989b7304a`.

The journey and soak each alternate three control/candidate pairs with app termination and a ten-second pause. Same Xcode 26.6 and specified visionOS 26.5 Simulator; no booted test clones, serial builds/tests/captures. Protocol 2 uses the stated median-plus-control-range interpretation and independent peak/hitch caps. Largest-callback judgment excludes texture-overlapping intervals because A does not change texture loading; raw maxima remain reported. Both complete comparisons pass. All thirty repeated restores and six persistence reloads pass.

### journey: passes corrected performance comparison

| Run | Footprint MiB | Peak MiB | Max mean ms | Max p99 ms | Largest ms (outside texture) | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Control 1 | 110.5–377.8 | 1612.894 | 20.30 | 108.58 | 715.25 (136.52) | 15 |
| Candidate 1 | 116.4–382.6 | 1618.878 | 19.55 | 113.80 | 318.93 (165.54) | 18 |
| Control 2 | 116.5–383.3 | 1619.222 | 18.68 | 114.17 | 293.51 (147.53) | 19 |
| Candidate 2 | 117.8–384.1 | 1620.191 | 19.79 | 84.14 | 469.01 (129.82) | 17 |
| Control 3 | 116.9–383.1 | 1619.238 | 19.34 | 105.56 | 491.31 (178.71) | 19 |
| Candidate 3 | 116.8–383.6 | 1619.910 | 18.47 | 111.00 | 312.72 (171.32) | 17 |

| Metric | Control min / median / max | Candidate min / median / max | Noise limit | Additional cap | Pass |
|---|---:|---:|---:|---:|---|
| footprint_min_mib | 110.500 / 116.500 / 116.900 | 116.400 / 116.800 / 117.800 | 122.900 | — | True |
| footprint_max_mib | 377.800 / 383.100 / 383.300 | 382.600 / 383.600 / 384.100 | 388.600 | — | True |
| lifetime_peak_mib | 1612.894 / 1619.222 / 1619.238 | 1618.878 / 1619.910 / 1620.191 | 1625.566 | 1651.607 | True |
| max_window_mean_ms | 18.680 / 19.340 / 20.300 | 18.470 / 19.550 / 19.790 | 20.960 | — | True |
| max_window_p99_ms | 105.560 / 108.580 / 114.170 | 84.140 / 111.000 / 113.800 | 117.190 | — | True |
| hitches_over_25ms | 15.000 / 19.000 / 19.000 | 17.000 / 17.000 / 18.000 | 23.000 | 21.850 | True |
| largest_callback_excluding_texture_ms | 136.525 / 147.533 / 178.713 | 129.820 / 165.540 / 171.323 | 189.721 | — | True |

### soak: passes corrected performance comparison

| Run | Footprint MiB | Peak MiB | Max mean ms | Max p99 ms | Largest ms (outside texture) | Hitches >25 ms |
|---|---:|---:|---:|---:|---:|---:|
| Control 1 | 115.6–409.0 | 1618.550 | 19.83 | 120.73 | 499.43 (168.82) | 111 |
| Candidate 1 | 116.7–416.0 | 1619.847 | 19.67 | 121.32 | 400.96 (184.53) | 119 |
| Control 2 | 116.1–586.3 | 1619.503 | 20.23 | 122.55 | 574.49 (184.93) | 122 |
| Candidate 2 | 116.7–683.2 | 1619.925 | 19.91 | 130.97 | 436.45 (168.93) | 114 |
| Control 3 | 116.3–414.5 | 1619.191 | 19.83 | 115.91 | 506.42 (172.22) | 131 |
| Candidate 3 | 111.4–406.6 | 1614.285 | 19.60 | 124.89 | 479.97 (175.65) | 125 |

| Metric | Control min / median / max | Candidate min / median / max | Noise limit | Additional cap | Pass |
|---|---:|---:|---:|---:|---|
| footprint_min_mib | 115.600 / 116.100 / 116.300 | 111.400 / 116.700 / 116.700 | 116.800 | — | True |
| footprint_max_mib | 409.000 / 414.500 / 586.300 | 406.600 / 416.000 / 683.200 | 591.800 | — | True |
| lifetime_peak_mib | 1618.550 / 1619.191 / 1619.503 | 1614.285 / 1619.847 / 1619.925 | 1620.144 | 1651.575 | True |
| max_window_mean_ms | 19.830 / 19.830 / 20.230 | 19.600 / 19.670 / 19.910 | 20.230 | — | True |
| max_window_p99_ms | 115.910 / 120.730 / 122.550 | 121.320 / 124.890 / 130.970 | 127.370 | — | True |
| hitches_over_25ms | 111.000 / 122.000 / 131.000 | 114.000 / 119.000 / 125.000 | 142.000 | 140.300 | True |
| largest_callback_excluding_texture_ms | 168.820 / 172.220 / 184.930 | 168.930 / 175.650 / 184.535 | 188.330 | — | True |

| Run | Surface checkpoints, cycles 1–5 (MiB) | Returned checkpoints, cycles 1–5 (MiB) |
|---|---|---|
| Control 1 | 406.831, 406.503, 406.503, 406.612, 406.597 | 407.847, 407.831, 407.847, 407.847, 407.831 |
| Candidate 1 | 413.456, 413.581, 413.440, 413.503, 413.503 | 414.987, 414.909, 414.768, 414.722, 414.753 |
| Control 2 | 409.284, 409.206, 409.065, 409.175, 409.175 | 410.565, 410.597, 410.409, 410.440, 410.362 |
| Candidate 2 | 408.206, 408.175, 408.143, 408.237, 408.112 | 409.534, 409.534, 409.487, 409.456, 409.331 |
| Control 3 | 411.909, 411.972, 411.784, 411.925, 411.878 | 413.284, 413.128, 413.128, 413.159, 413.128 |
| Candidate 3 | 405.393, 405.425, 405.565, 405.393, 405.472 | 406.346, 406.268, 406.143, 406.112, 406.143 |


The comparison wrapper initially failed after all six journeys completed because Bash 3 treats an empty array as unbound under `set -u`. Its argument array now always contains the spread option. The six original runs were retained and compared; no app binary changed or run was selected out. The subsequent complete soak exercised the corrected wrapper successfully. This validation-tool fix is included with A.

All eleven fresh Apollo PNGs are byte-identical to the September 4 v2 baseline. The eleven pinned resource hashes match. Four protected bodies are text-identical to f81410c; the radiance body differs only by the explicitly authorized constant-to-sun-dependent lookup substitution, verified by an exact transformed-body comparison. No compositing compensation, terrain geometry, residual, source ordering or AGC change is included.

Fresh layer-isolation captures at 210 km use the same central 80% ROI (384,216,3072,1728) and linear RGB luminance with alpha excluded. All four PNGs are byte-identical to the earlier calibrated iteration-2 originals. Recomputed means:

| Sun | Globe-only mean | Site-only mean | Globe/site | Difference |
|---|---:|---:|---:|---:|
| Mission, about 10.689° | 0.133984 | 0.134490 | 0.996238 | −0.3762% |
| Daylight, about 25° | 0.136585 | 0.137054 | 0.996578 | −0.3422% |

Both pass the established 1% radiance tolerance. The initial analysis included alpha in ImageMagick's mean; removing alpha restored the correct RGB measurement above. No image was edited for acceptance. The mission value remains exactly 5.70 by test, not inferred from an approximately matched image.

The seven-stage journey was recaptured in all three candidate runs. Inspected `journey/Candidate-1/handoff.png` and `terrain.png`: at 42.8 km crater bowls have distinct opposing lit and dark sides and narrow ridges are visible. At 7.5 km, small pits have bright rims and darker interiors; low ridges and surface undulations read around the center. The Apollo mare remains low contrast and distant detail remains soft. The daylight globe/site isolation pair was also inspected: mean brightness matches while the site layer reveals more relief than the blurred monolithic globe. This accepts the lighting improvement without claiming E's imagery improvement has landed.

Both the final Apollo stop and final daylight site isolation wait 90 seconds; their last twelve windows have 16.67 ms mean/p99/max and zero missed callbacks. See `Apollo/final-settled.json`, `Isolation/final-settled.json` and `Isolation/luminance.json`.

Physical Vision Pro gates remain open: stereo relief and crossfade, tracked head/hand/gaze input, comfort, device CPU/GPU pacing, memory pressure, thermal behavior and space lifecycle. No physical device was used. C proceeds against the accepted A baseline; E remains independently reviewable on its branch.


## Run checkpoint — stopped at owner request, 2026-09-07 20:53 PDT

Validation is stopped. No runtime item was landed after A. The driver, capture
child and Simulator app were terminated; completed and partial evidence and
all five candidate branches are preserved. This checkpoint changes only the
two one-zoom documents.

Landed during this run: `2d72f2c` (corrected performance protocol), `db86a0c`
(E's completed revalidation report and measurement tooling), and `ceac6fc`
(A's relief lighting and sun-dependent radiance). Steps 1–3 remain landed.
The landing branch's runtime baseline is `ceac6fc`.

| Candidate branch | Preserved commit | Current status |
|---|---|---|
| `onezoom/A` | `ceac6fcc7071fe82eb6ebca3d8f1fc2dac0e90d6` | Landed; complete Simulator acceptance |
| `onezoom/B` | `8693749cd6dfc9a4ef7aa4ec725600b03c3169dc` | Not landed; Simulator eye calibration fix and protocol-2 validation outstanding |
| `onezoom/C` | `afef8c76d80a8ef78e1e5e174f9ccf2d04f5893b` | Rebased onto A; not landed; validation interrupted |
| `onezoom/D` | `06fb4abfb856e748fcdeb9cfc34ceac6b7444bbe` | Not landed; concurrency experiment and full protocol-2 validation outstanding |
| `onezoom/E` | `b750e58df459f3b1178956fd7c01f7390a573257` | Not landed; completed protocol-2 soak/highland failures |

B, D and E retain their existing bases; no wrap-up rebase was performed. There
is no F candidate. F still depends on D and E landing; the subsequent Apollo
peak attribution has not started.

**Completed gates.** A passed 74 selected Release Simulator tests, alternating
three-run journey and five-cycle soak comparisons, all eleven byte-identical
Apollo PNGs, resource/protected-body contracts (only the authorized radiance
lookup differs), and the 90-second settled checks. Its 42.8 km and 7.5 km
captures show opposing lit and shadowed crater sides; the mare remains low
contrast. Globe/site luminance differs by −0.3762% at mission sun and −0.3422%
at about 25°, both within 1%. A's executable SHA-256 is
`ab9bbf279ef0ca677121bf005ba21feffc2c5c6d74c897dac3bac9c989b7304a`.

E passed 79 selected tests, the complete journey comparison, all eleven exact
Apollo images, fixed-disk identity, resource/protected-body checks and final
90-second settles. The 210 km image resolves finer crater detail. Journey
median lifetime peak fell from 1,620.269 to 621.159 MiB, but the complete soak
failed mean/p99 gates; warm highland failed footprint/p99 and cold highland
failed footprint/largest-callback gates. These are completed three-run
failures, not conclusions from partial data. Full tables, texture intervals
and kernel peaks remain in the E report above and its evidence directory.
The original 76 MiB JPEG XL remains bundled alongside the 15.4 MiB companion;
removal remains an owner bundle decision.

**C is incomplete, not accepted or rejected.** Its Release build and 75 selected
tests completed. All six journeys completed and the existing protocol-2
comparison passes: median maximum footprint 383.8 → 321.8 MiB; lifetime peak
1,619.347 → 1,620.363 MiB; hitches over 25 ms 18 → 16; largest callback outside
the texture interval 166.082 → 137.000 ms. The complete per-run and
min/median/max tables are preserved in `C/completed-journey.md` and
`C/journey/comparison-v2.json` under the evidence root below.

Four five-cycle soak runs completed: Control-1, Candidate-1, Control-2 and
Candidate-2. Control-3 was interrupted after the latest logged stage
`soak-1-returned`; its completion marker and metrics file are absent.
Candidate-3 never started. No aggregate soak verdict is assigned. Partial
images/logs remain in `C/soak/Control-3/`, marked `INCOMPLETE.md`. Fresh C
anchored-pinch timing/0.0005 m accuracy, full Apollo ladder, final 90-second
settle, final contract audit and complete surface/returned checkpoint
comparison were not reached. The index removal is implemented on the branch;
the complete fresh checkpoint gate for its retained-memory saving remains
outstanding. Prior 0.018 ms picking is historical evidence, not a new result.
C's executable SHA-256 is
`6a336ca18628b9059adb2d78a50e21e19790fb4ac79e03a05958ce8f360293c9`;
its frozen control is A's executable above.

B has no fresh gate results this run. Unify its Simulator eye constant before
validation; retain frame-contact switching, corner intersection and border
fade. D likewise has no fresh gate results: compare concurrency 1/2/4 with
three warm dives each, report regional/per-generation ready times, then run
the complete matched suite. Their historical single-run withholds do not
constitute protocol-2 failures. E's smallest proposed experiments remain
sampling verified slabs without the duplicate concatenated buffer and
isolating fine-imagery import deferral around Apollo publication; neither
was implemented during wrap-up.

Evidence root: `/tmp/LM-Explorer-OneZoom-2026-09-07/Revalidation/`.
A's complete tables, captures and isolation measurements are in `A/`; E's
complete tables, texture/kernel markers, soak, warm/cold dives and Apollo
captures are in `E/`; C's completed tests/journeys and partial soak are in
`C/`, with stop details in `C/INTERRUPTED.md`. Exact preserved branch refs are
in `wrap-up-branches.txt`. Original evidence and patches under
`/tmp/LM-Explorer-OneZoom-2026-09-07/{A,B,C,D,E}/` remain intact.

**Next action:** finish C's acceptance before landing it. Budget roughly
60–75 minutes for a fresh alternating six-run soak set after the interruption,
then the pinch probe, Apollo ladder/90-second settle and contract audit.
Keep the completed journey evidence; repeat it only if the binary or test
conditions change. The broader E/B/D validation still represents roughly
5–8 hours of serial Simulator work after fixes, excluding implementation,
F and physical validation; these are scheduling estimates, not measured gates.

All results here are Xcode 26.6 Release on the visionOS 26.5 Simulator
`8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`. Physical Vision Pro stereo/crossfade,
tracked head/hand/gaze interactions, comfort, real CPU/GPU pacing, memory
pressure, thermal behavior and space lifecycle remain unvalidated. No AGC,
terrain data, residual caps, source ordering or contact geometry was changed.
Unrelated owner documents, both scheme-user files and RealityKitContent
xcuserdata remain outside this checkpoint commit.

## Performance protocol, owner gate correction for wrap-up

This correction supersedes the historical decisions and arithmetic above.
Only these are gates:

- Lifetime peak: candidate median ≤ control median + max(25 MiB, 2%).
- Hitches over 25 ms: candidate median ≤ control median + max(2, 15%).
- Largest callback outside the globe-texture interval: candidate median ≤ max(control maximum, control median × 1.10). A tightly clustered control set does not remove the ten-percent margin. This applies to E too; the raw maximum remains reported.
- The 90-second settled window: mean ≤ 16.70 ms, p99 ≤ 16.70 ms and max ≤ 16.70 ms, with zero missed callbacks. A mean below 16.67 ms passes.
- All eleven Apollo PNGs byte-identical to the September 4 v2 baseline.

The percentages use the corresponding control median. Frame-window footprint
minimum/maximum, max-window mean and max-window p99 are reported, not gated.
"Within the spread" uses the control maximum, with the explicit ten-percent callback margin above. Peak and hitches retain their separately specified allowances. These permanent owner corrections supersede the historical no-margin callback and exact-16.67 decisions below.
Keep three alternating control/candidate runs for matched comparisons, with
app termination and ten seconds between runs; judge the medians only after
the complete set. E's existing triplicates are reused by owner instruction.
The wrap-up adds one E journey and an Apollo ladder to verify its rebase,
not to replace the completed triplicates with a single-run decision.

Re-evaluating E's completed tables without new captures: peak and hitch gates
pass for journey, soak, warm highland and cold highland; the callback gate
passes except for the soak, whose outside-texture median is 176.610 ms against
a 174.980 ms control maximum. The former footprint/mean/p99 failures are now
reported-only differences. The cold dive's raw largest callback is 558.14 ms
against a 379.74 ms control maximum, while its outside-texture median passes
at 136.543 ms against 159.824 ms. The owner accepts E for its peak reduction,
including these reported regressions and the 1.630 ms soak callback excess.
The journey peak median is 621.159 MiB versus 1,620.269 MiB control; the soak
median is 919.144 MiB, so 621 MiB is not a universal peak ceiling. Fresh
rebase tests, journey and exact Apollo verification remain required before
landing. Recomputed gate records are `Wrapup/E-existing-*.json` under
`/tmp/LM-Explorer-OneZoom-2026-09-07/`.

### Initial wrap-up rebases and focused tests

All four candidates were rebased onto `2ae5bc5` before acceptance work. E's
only conflict was the comparison script; the landed Bash 3 empty-array fix
was retained. No runtime conflict required a behavior change. These are
initial candidate hashes; accepted and parked final refs are recorded below.

| Branch | Rebased commit | Passed tests | Failed tests | Evidence |
|---|---|---:|---:|---|
| `onezoom/B` | `bcb9f6ba083981664c41d1dc4cbf9ab440cc897d` | 70 | 0 | `Wrapup/Initial-B/Tests.xcresult` |
| `onezoom/C` | `7d6e69165c619ab90e48b7612ad51cc49a02d733` | 75 | 0 | `Wrapup/Initial-C/Tests.xcresult` |
| `onezoom/D` | `d8a87dd4201a8613a4b8b03c8818e76689977531` | 86 | 0 | `Wrapup/Initial-D/Tests.xcresult` |
| `onezoom/E` | `ed2d65b3f49a9af59dbc312d026068d21875b5d3` | 81 | 0 | `Wrapup/Initial-E/Tests.xcresult` |

## C wrap-up acceptance, 2026-09-07

Evidence: `/tmp/LM-Explorer-OneZoom-2026-09-07/Wrapup/C/`.
Rebased candidate `7d6e691` builds to SHA-256
`6a336ca18628b9059adb2d78a50e21e19790fb4ac79e03a05958ce8f360293c9`,
byte-identical to the preceding C candidate. Its 75 selected Release Simulator
tests pass. The retained complete journey comparison therefore applies without
a recapture and passes the named gates; see `Wrapup/C-retained-journey.json`
and the six original runs in `Revalidation/C/journey/`.
Control is the accepted A executable,
`ab9bbf279ef0ca677121bf005ba21feffc2c5c6d74c897dac3bac9c989b7304a`.

The fresh six-run alternating soak passed all named performance gates. All
thirty repeated restores and six persistence reloads passed. No run was
restarted or omitted. The previous interrupted set remains separate and
incomplete. Surface and returned entries below are physical-footprint
checkpoints, not lifetime peaks. Full texture/kernel markers remain in each
run's `metrics-v2.json` and `performance.log`.

| Run | Footprint MiB | Peak MiB | Max mean ms | Max p99 ms | Largest ms / outside texture | Hitches >25 ms | Texture ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Control 1 | 116.6–411.2 | 1619.535 | 19.60 | 114.08 | 476.740 / 184.890 | 124 | 1623.793 |
| Candidate 1 | 117.6–348.4 | 1620.722 | 19.44 | 110.29 | 395.830 / 181.273 | 95 | 1434.383 |
| Control 2 | 116.1–502.9 | 1619.066 | 19.63 | 125.10 | 416.130 / 150.373 | 128 | 1375.490 |
| Candidate 2 | 111.9–502.4 | 1614.894 | 18.99 | 108.24 | 472.370 / 168.004 | 101 | 1436.268 |
| Control 3 | 117.5–503.4 | 1620.332 | 19.44 | 131.10 | 582.060 / 146.380 | 122 | 1445.601 |
| Candidate 3 | 110.8–389.2 | 1613.800 | 19.04 | 97.85 | 487.260 / 165.724 | 96 | 1368.914 |

| Metric | Control min / median / max | Candidate min / median / max | Gate limit | Result |
|---|---:|---:|---:|---|
| footprint_min_mib | 116.100 / 116.600 / 117.500 | 110.800 / 111.900 / 117.600 | — | Reported |
| footprint_max_mib | 411.200 / 502.900 / 503.400 | 348.400 / 389.200 / 502.400 | — | Reported |
| lifetime_peak_mib | 1619.066 / 1619.535 / 1620.332 | 1613.800 / 1614.894 / 1620.722 | 1651.925 | Pass |
| max_window_mean_ms | 19.440 / 19.600 / 19.630 | 18.990 / 19.040 / 19.440 | — | Reported |
| max_window_p99_ms | 114.080 / 125.100 / 131.100 | 97.850 / 108.240 / 110.290 | — | Reported |
| largest_callback_ms | 416.130 / 476.740 / 582.060 | 395.830 / 472.370 / 487.260 | — | Reported |
| largest_callback_excluding_texture_ms | 146.380 / 150.373 / 184.890 | 165.724 / 168.004 / 181.273 | 184.890 | Pass |
| hitches_over_25ms | 122.000 / 124.000 / 128.000 | 95.000 / 96.000 / 101.000 | 142.600 | Pass |

| Run | Surface checkpoints, cycles 1–5 MiB | Returned checkpoints, cycles 1–5 MiB |
|---|---|---|
| Control 1 | 409.253, 409.268, 409.284, 409.409, 409.331 | 410.472, 410.487, 410.487, 410.472, 410.440 |
| Candidate 1 | 346.425, 346.300, 346.362, 346.440, 346.425 | 347.722, 347.675, 347.628, 347.690, 347.675 |
| Control 2 | 408.722, 408.972, 408.878, 408.956, 409.065 | 411.675, 411.440, 411.472, 411.268, 411.378 |
| Candidate 2 | 342.393, 342.425, 342.596, 342.550, 342.550 | 343.362, 343.362, 343.253, 343.331, 343.300 |
| Control 3 | 409.878, 409.847, 409.909, 409.972, 410.034 | 411.222, 411.222, 411.222, 411.222, 411.315 |
| Candidate 3 | 343.659, 343.581, 343.596, 343.518, 343.471 | 344.628, 344.706, 344.487, 344.596, 344.596 |


The median of each run's five surface checkpoints falls from 409.284 to
343.581 MiB; returned checkpoints fall from 411.222 to 344.596 MiB. The net
reductions are 65.703 and 66.625 MiB. `LunarExplorerTriangleIndex`, its entity
cache and mesh-buffer extraction are absent from the candidate. The former
69.7 MiB retained index is replaced by shared measured posts plus 2,105,352
bytes of additional outer height grids, recorded at `pinch-height-fields-ready`.
Process-footprint differences are not asserted to equal the index's allocation
size exactly. Lifetime peak still comes from the unchanged monolithic texture.

The fresh anchored-pinch integration passes its 0.0005 m scene-space bound.
The printed maximum ray error rounds to 0.000000 m; that is log precision,
not a claim of mathematically zero error. Source quantization at the probe
scale is 0.000081 m. Pick duration is 0.003875 ms, below 1 ms. Pan and pinch
stages complete with `oneZoom=true`. Inspected `Gestures/pinch-end.png`:
crater bowls and scattered rocks remain visible behind the portal and browser;
the displayed altitude is 90 m. Anchor accuracy comes from the numerical probe,
not this still image. Physical tracking and gesture recognition remain open.

All eleven fresh Apollo PNGs are byte-identical to the pinned baseline.
All eleven pinned resource hashes and all five protected-body comparisons pass,
with only A's authorized radiance lookup substitution. After the final
90-second capture wait, the last twelve windows are 16.67 ms mean/p99/max
with zero missed callbacks. The ten gate-tool tests pass, including reported
columns, the control-maximum callback boundary and independent peak/hitch
allowances. C is accepted in Simulator. No terrain data, residual, contact
geometry, source-order or AGC change is included. All physical-device gates
remain open.

## E wrap-up acceptance by owner decision, 2026-09-07

C landed as `f9e7b143ff0c3aff24cc80627a31fa675814d025`. E was rebased onto
that baseline as `d742c35`; no runtime conflict required a behavior change.
The rebased suite passes 82 tests, including the former 79-test selection's
coverage plus the landed lighting and replacement height-field tests.
Release executable SHA-256:
`d08b291820d537f3dd9b3ee850a0155cf5a3e2ef4fa721eb527af57338707a04`.
Evidence: `/tmp/LM-Explorer-OneZoom-2026-09-07/Wrapup/E/`.

The single rebase-confirmation journey passes all seven stages. This is not
a new three-run performance decision. Its observations are:

| Footprint MiB | Lifetime peak MiB | Max mean ms | Max p99 ms | Largest ms / outside texture | Hitches >25 ms | Texture interval ms |
|---:|---:|---:|---:|---:|---:|---:|
| 117.3–323.1 | 619.456 | 19.43 | 117.48 | 544.090 / 152.100 | 17 | 307.783 |

Inspected `journey/crossfade.png`, `handoff.png` and `terrain.png`. The overlap
shows distinct rims, craterlets and ridges where the old monolithic map was
blurred. The terrain stops preserve lit/shadowed crater sides and small pits;
the mare remains low contrast. The unchanged wide portal is still present,
with its room placement to be addressed by B's separate attempt.

The completed E triplicates were not repeated. The owner accepted the peak
reduction despite the reported regressions: soak max-window mean and p99,
warm/cold highland maximum footprint, and the cold dive's raw largest callback.
Warm highland p99 also exceeded its previous control range. These columns are
reported, not gated by the corrected rule. The soak outside-texture callback
also exceeds the corrected control-maximum gate by 1.630 ms, as recorded in
the protocol reassessment above; E lands by explicit owner acceptance, not a
claim that every named gate passed. All peak and hitch gates pass in the
existing complete tables. No failing-item iteration was performed.

Tracked follow-ups, not implemented: sample verified slabs directly in
`LMLunarImageryTileStore.pixels(for:)` instead of concatenating full-width
source slabs; defer fine-imagery imports around Apollo mesh/material
publication. The 76 MB 64 ppd JPEG XL remains bundled for the deterministic
capture path alongside the 15.4 MiB companion. Its removal remains an owner
bundle decision.

All eleven rebased Apollo PNGs are byte-identical to the pinned baseline.
Eleven resource hashes and five protected-body comparisons pass, allowing
only A's radiance substitution. The final 90-second capture wait ends with
twelve 16.67 ms mean/p99/max windows and zero missed callbacks. E is accepted
and landed by owner decision. Physical stereo, tracked gestures, pacing,
memory pressure, thermals, comfort and lifecycle remain unvalidated.

## B single wrap-up attempt, parked, 2026-09-07

Candidate `dbbc048` is based on landed E, `7be191b`. It retains the free-standing
disk, first-frame-contact switch, sphere/rounded-frame aperture intersection,
border fade and 1.6 × 1.1 m default portal. `simulatorEyePosition` is the one
named 1.60 m calibration used by the gesture ray, deterministic pinch probe
and portal projection. On device, gesture and portal eye queries share the
tracked-device-anchor path. The 1.45 m portal placement height is unchanged.
No optional lazy-mesh experiment was implemented.

78 focused tests and the Release build pass. Candidate executable SHA-256:
`2d669f868a6c05b05636f8acea23a63bf5d871b906da0bcda6810f18bc26a874`.
Control is landed E's executable,
`d08b291820d537f3dd9b3ee850a0155cf5a3e2ef4fa721eb527af57338707a04`.
Evidence: `/tmp/LM-Explorer-OneZoom-2026-09-07/Wrapup/B/`.

All six journeys passed their integration stages. The complete performance
comparison fails the outside-texture callback gate: candidate median 135.880 ms
exceeds the control maximum 130.310 ms by 5.570 ms. Lifetime peak and hitch
count pass. B is parked without another attempt; reported-only metrics do not
change that decision.

| Run | Footprint MiB | Peak MiB | Max mean ms | Max p99 ms | Largest ms / outside texture | Hitches >25 ms | Texture ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Control 1 | 116.5–322.4 | 618.831 | 19.56 | 84.09 | 540.140 / 103.923 | 19 | 460.750 |
| Candidate 1 | 119.4–326.0 | 623.393 | 19.75 | 113.79 | 646.130 / 135.880 | 14 | 423.678 |
| Control 2 | 117.1–323.4 | 620.284 | 19.19 | 117.52 | 452.910 / 130.310 | 16 | 309.094 |
| Candidate 2 | 112.6–319.4 | 615.768 | 19.15 | 112.50 | 454.580 / 134.284 | 19 | 413.057 |
| Control 3 | 117.5–322.9 | 619.222 | 19.43 | 101.52 | 421.330 / 130.002 | 17 | 510.094 |
| Candidate 3 | 120.5–326.8 | 623.237 | 19.28 | 116.68 | 542.500 / 183.554 | 17 | 554.561 |

| Metric | Control min / median / max | Candidate min / median / max | Gate limit | Result |
|---|---:|---:|---:|---|
| footprint_min_mib | 116.500 / 117.100 / 117.500 | 112.600 / 119.400 / 120.500 | — | Reported |
| footprint_max_mib | 322.400 / 322.900 / 323.400 | 319.400 / 326.000 / 326.800 | — | Reported |
| lifetime_peak_mib | 618.831 / 619.222 / 620.284 | 615.768 / 623.237 / 623.393 | 644.222 | Pass |
| max_window_mean_ms | 19.190 / 19.430 / 19.560 | 19.150 / 19.280 / 19.750 | — | Reported |
| max_window_p99_ms | 84.090 / 101.520 / 117.520 | 112.500 / 113.790 / 116.680 | — | Reported |
| largest_callback_ms | 421.330 / 452.910 / 540.140 | 454.580 / 542.500 / 646.130 | — | Reported |
| largest_callback_excluding_texture_ms | 103.923 / 130.002 / 130.310 | 134.284 / 135.880 / 183.554 | 130.310 | Fail |
| hitches_over_25ms | 16.000 / 17.000 / 19.000 | 14.000 / 17.000 / 19.000 | 19.550 | Pass |


Inspected `journey/Candidate-1/disk.png`: the globe is free-standing in the
room with no black rectangle or frame, and the flag, site markers and selected
label remain visible. Inspected `Switch/switch-before.png` and
`Switch/switch-after.png`, widths 4,211,610.403 and 4,203,195.597 m: room remains
visible around the limb, no black corners appear, and there is no visible
position/scale pop beyond the expected small zoom. Still images do not qualify
stereo or tracked-head motion. The performance failure remains decisive.

Resume here on `onezoom/B`: first attribute the callbacks outside texture
loading to portal/aperture realization versus terrain/imagery publication,
using the retained phase logs and the worst callback intervals. The smallest
next implementation experiment is to defer initial portal mesh realization
until frame contact if that work is implicated. No causal attribution or
improvement is claimed yet. Rerun the same named gates after that isolated
change. No new B soak, highland dive or device test was run in this wrap-up;
the requested scope was the journey comparison, threshold pair and Apollo
ladder. Do not treat E's owner exception as an exception for B.

All eleven fresh Apollo PNGs are byte-identical, and eleven resource hashes
plus five protected-body comparisons pass. The final 90-second wait produced
zero missed callbacks and 16.67 ms p99/max in the inspected final windows,
but the strict exact-mean checker rejected a 16.61 ms mean window. This is
recorded as an additional failed hard check, not retried or silently rounded
into a pass. See `Apollo/final-settled.json` and `B-validation.log`.

## Parked branches: resume here

These hashes identify the source revisions that were built and tested before
the final documentation-only rebase. Final resolved refs, including the closure
commit, are preserved in `Wrapup/final-state.json`; their runtime trees must
match these qualified revisions exactly.

| Branch | Qualified source commit | Build/tests | Next work |
|---|---|---|---|
| `onezoom/B` | `dbbc048f24d5b7d609a80b708046998d9b0ba3b3` | Release build, 78 tests; one failed acceptance attempt documented above | Attribute the outside-texture callback excess; no second attempt this run |
| `onezoom/D` | `9a23a600f13d81374b8442bc9322399e3ca58ccb` | Release build, 97 tests; eleven resources and five protected bodies pass | Concurrency 1/2/4, three warm highland dives each, regional ready time |
| `onezoom/F` | Final landing head, no unique commits | Not started; no build-specific change | Sliding region after D acceptance; 100 km pan/contact gate not run |

D is parked, with no performance iteration in this wrap-up. It implements
coarse-first 512 m publication and prefetch below about 600 km, followed by
finer generations; allocation-free source selection and the immutable parent
resolution table are retained. The historical diagnostic showed the coarse
generation ready before the 240 km crossing, but that is not fresh acceptance
of the final rebased branch.

Resume with the exact next experiment: expose sibling concurrency as 1, 2 and
4; run three warm highland dives at each setting, coordinate −42°, 120°;
compare source-start-to-16-tile-ready time and per-generation ready times,
not sums of overlapping intervals. Ship the fastest measured setting, including
serial if it wins. Then run the matched journey/soak and warm/cold dive gates,
Apollo ladder, settled check and contract audit. None of those performance or
visual gates was run on the final parked D revision in this wrap-up.


D's rebase conflict in `stopStepping()` retained both E's imagery suspension
and D's prefetch cancellation. Its final parked tests include the resolver and
refinement suites, including serial/concurrent parent-sampling equality.
No new D benchmark or capture was started. B already has the final landed
runtime baseline as its parent; no runtime change was made after its tests.
The final rebases add documentation only, verified by comparing runtime trees,
so their existing build/test evidence applies without repeating it. Nothing
was pushed.

## Run closed

The final landed **runtime head** is
`7be191bed566bad76a9e2f93b0eabea069c1bb2e`. The closure report and the owner's
pending package-plan documents are the only commits added after it. The exact
final branch head SHA and all rebased `onezoom/*` refs are recorded after those
commits in `/tmp/LM-Explorer-OneZoom-2026-09-07/Wrapup/final-state.json` and in
the final handoff. This avoids describing a parked candidate as the landing
head or embedding a self-referential commit hash in its own tree.

Accepted runtime for the closed run: A `ceac6fc` supplies relief lighting and
sun-dependent radiance; C `f9e7b14` removes the retained triangle index and
uses measured height-field gesture anchors; E `7be191b` supplies tiled imagery
with the owner's documented performance acceptance. A was already landed at
the opening checkpoint; C and E landed in this wrap-up. B remains parked
because its single attempt missed the callback gate and strict settled mean.
D is parked, F is parked without implementation, and E1/E2 are not started.

The landed executable SHA-256 is
`d08b291820d537f3dd9b3ee850a0155cf5a3e2ef4fa721eb527af57338707a04`,
archived as `Wrapup/E/Candidate.app`. It is also the frozen control in the last
complete alternating set, `Wrapup/B/journey/Control-1` through `Control-3`.
The current baseline from that set is:

| Metric | Control min | Control median | Control max |
|---|---:|---:|---:|
| lifetime_peak_mib | 618.831 | 619.222 | 620.284 |
| hitches_over_25ms | 16.000 | 17.000 | 19.000 |
| largest_callback_excluding_texture_ms | 103.923 | 130.002 | 130.310 |
| largest_callback_ms | 421.330 | 452.910 | 540.140 |
| texture_interval_ms | 309.094 | 460.750 | 510.094 |


The raw callback includes the texture interval and is reported only. The
619.222 MiB journey peak median is not a universal lifetime ceiling: the
retained E soak triplicates reached 919.144 MiB median. Existing E performance
exceptions and pending imagery follow-ups remain visible above.

All wrap-up work used serial Xcode 26.6 Release tests/builds and the visionOS
26.5 Simulator `8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`. C and E pass all eleven
byte-identical Apollo captures and the settled checks. B's exact images pass
but its named failures remain failures. All terrain resources, residual caps,
contact geometry and source ordering remain unchanged; no AGC change was
made. Only the authorized radiance lookup differs among protected bodies.
All complete and failed evidence remains under
`/tmp/LM-Explorer-OneZoom-2026-09-07/Wrapup/`; previous evidence and the earlier
interrupted C soak are preserved separately.

Physical Vision Pro gates remain open: stereo and crossfade perception,
tracked head/hand/gaze behavior and gesture comfort, physical CPU/GPU pacing,
memory pressure, thermals and immersive-space lifecycle. Simulator evidence
does not qualify those gates. D's coarse handoff and F's 100 km sliding-region
acceptance are also still outstanding.

The next run starts `Docs/LunarMapPackagePlan.md` on the closed landing branch.
No package extraction, new app target or other package-plan implementation was
started here. The owner's package plan and its two cross-reference documents
are committed unchanged as `docs: add LunarMap package plan and cross-references`.
Both scheme-user files remain modified and outside commits. All other work
is committed; parked candidates remain reviewable and rebased onto the closure
head. The final state artifact records the verified status and runtime-tree
comparisons after that last documentation-only rebase.


### B landed under the permanent gate correction, 2026-09-08

The owner added a ten-percent callback margin and an upper-bound settled rule
in the protocol section above. Re-evaluating the completed B journey set,
without recapturing it, gives a callback limit of
max(130.310, 130.002125 × 1.10) = 143.0023375 ms. The candidate median
135.880 ms passes; peak 623.237 MiB and 17 hitches already pass their limits.
All twelve recorded final Apollo windows have mean 16.61–16.67 ms,
p99/max 16.67 ms and zero misses, so the ≤16.70 ms settled gate passes too.
The eleven byte-identical Apollo images and switch-pair inspection remain
valid. The historical parked decision above is superseded, not erased.

`onezoom/B` at `4c5e2e0` was compared again with qualified source `dbbc048`:
its non-documentation tree is identical. The fresh ordinary Release build
also reproduces executable SHA-256
`2d669f868a6c05b05636f8acea23a63bf5d871b906da0bcda6810f18bc26a874`.
All 78 focused tests and 13 gate-tool tests pass. B is landed as one commit,
with no new runtime adjustment. Evidence and the recalculated gate records
are in `/tmp/LM-LunarMap-2026-09-08/B/`. D and F remain parked and are rebased
onto this landing before package work; physical-device gates remain open.
