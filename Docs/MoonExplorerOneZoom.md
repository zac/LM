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
