# Moon Explorer experience

This implements the Explorer navigation and presentation milestone under
`LandAnywhereMoonPlan.md`. The existing terrain engine, source contracts and
Apollo capture path remain shared with LM.

## Presentation decision

The supplied mockup informs the compact place browser, floating globe and
small bottom toolbar. Start in mixed immersion with a bounded globe beside a
native glass window. Globe dragging changes the geographic focus across the
whole Moon. Pinching changes the globe within a modest size range.

An explicit **Explore surface** action opens full immersion and loads terrain.
**Return to globe** restores passthrough. This avoids unexpectedly filling the
room with a giant sphere or an unbounded terrain plane while pinching. Close
terrain is an inspection view, not a claim of a life-size lunar walk.

Apple recommends beginning with mixed immersion or a window, letting people
choose when to increase immersion, and using full/progressive immersion for
content that substantially obscures passthrough:
https://developer.apple.com/design/human-interface-guidelines/immersive-experiences/
Native window ornaments hold the frequent actions:
https://developer.apple.com/design/human-interface-guidelines/ornaments/

## Journey and contracts

Open Moon, find a place or enter coordinates, inspect its location on the
globe, explore terrain, adjust sunlight, save the view and return later.
The product zoom requests matching terrain detail. The inspector and accepted
capture flags retain independent altitude and magnification controls.

Saved views retain the source anchor, local offsets, camera, lighting instant
and appearance settings. Restoration waits for terrain readiness before
applying the camera. Saving the focused coordinate together with the original
pan offsets would apply the pan twice, so those remain explicitly separate.
Invalid persisted entries are rejected. No bookmarks require a network service.

The normal browser defers the Apollo terrain stack until an Explore action.
No new source data, residual budget or synthesis changes are part of this
milestone. Measured source spacing and modeled sub-resolution detail remain
visible in the terrain UI; engineering diagnostics move into an inspector.

## Acceptance

- Release Simulator build and focused navigation, persistence and lifecycle tests.
- Actual browser, selected-place, sunlight and immersive terrain captures.
- Restore a saved view and verify camera, coordinates and sunlight.
- Preserve the eleven accepted Apollo capture images byte for byte.
- Compare startup/settled timing and memory against the existing baseline.
- Physical Vision Pro gates remain open for glanceability, reach, stereo,
  gesture comfort, real-space placement and sustained performance.

Implementation and validation results are recorded below as they complete.

## Implementation notes

The initial placement and marker sizing described below are historical. The
[HIG improvement pass](MoonExplorerHIGReview.md) supersedes them with adjustable
placement relative to the initial viewer position, Dynamic Type, and fades.

The mixed globe has a radius of 0.334-0.491 m across its allowed zoom range,
with its center 0.95 m right, 1.45 m high and 1.8 m forward in the existing
scene frame. The initial overlapping layout was rejected after live Simulator
inspection. `browser-second.png` in `/tmp/LM-Explorer-UX` records the corrected
separation before the final blue primary-action tint. Physical placement and
reach are still provisional until tested on Vision Pro.

Only the mixed cartographic globe gets a 3x linear brightness multiplier for
visibility against passthrough. Immersive radiance matching and the accepted
capture path retain their previous arithmetic. The opening globe chooses a
nearby local-noon time from the analytic ephemeris; Daylight here searches a
30-day interval in six-hour steps. It changes the date, not the lighting model.
The sunlight panel exposes UTC date/time and the scrub offset.

Explicit inspection launch options retain the legacy camera, lighting and
full-immersion defaults. Plain Explorer launches use the new experience.
The initial test run caught two changed invalid-argument fallback assertions;
those contracts were restored, and the next run passed 36 tests in four suites.

The Xcode preview compiler failed in its generated `__designTimeSelection`
code. This is retained in `/tmp/LM-Explorer-UX/preview-failure.txt`; it does not
count as visual acceptance. Live Simulator inspection caught the initial
overlap, then the Mac locked before button-by-button testing could finish.
Computer Use requested an unlock. The Simulator's semantic UI snapshot exposes
no actionable targets for this visionOS scene.

`Tools/CaptureMoonExplorerJourney.sh` runs an explicit opt-in product-state
integration sequence with the production session actions and renderer. It
captures globe, selected place, immersive terrain, returned globe and restored
terrain. It verifies persistence reload and exact camera/time equality in a
temporary isolated bookmark library. This covers renderer/lifecycle behavior;
it does not replace manual UI hit-target and gesture checks.

The first integration run (`/tmp/LM-Explorer-UX/Journey`) was rejected: the
resident globe retained a flight coordinate after Apollo terrain loaded, so
the scene displayed a magnified globe instead of terrain. Restoration also
stalled in a SwiftUI update loop; the process sample is
`/tmp/LM-Explorer-UX/journey-hang.sample.txt`. Arrival now clears the flight
coordinate independently of globe creation, and unchanged sunlight diagnostics
are no longer republished from the observed RealityView update closure.
`Experience-Ready-Tests.xcresult` passes 37 tests in four suites (4.300 seconds),
including a regression for the resident-globe handoff.

## Release validation, 2026-09-05

Implementation commit: `cfecb74` (mixed-space browser, saved views and
integration capture). Validation below used its exact source state.

Normal Release build: `build-ready.log` under `/tmp/LM-Explorer-UX`.
The captured executable SHA-256 is
`52dbba6badc13f95d9a359e5f9f6cba58c47696af26e9e9f7db5fc738e42239f`.
Destination: visionOS 26.5 Simulator
`8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`, built with Xcode 26.6.

`Journey-Ready` passed all five stages, with screenshots inspected individually.
The saved and restored JSON objects in `camera-and-sunlight.json` are exactly
equal: Apollo anchor 0.673433°, 23.473113°; north/east offsets 130/-45 m;
altitude 180 m; width 576 m (floating-point representation retained); heading
27°; tilt 72°; identical UTC lighting instant, grade, detail mode and shadows.
The restored screenshot retains the same terrain framing. The selected-place
description truncates in the compact immersive panel; its complete copy is
visible in the browsing card.

The initial mixed browser settled at 109.0 MiB sampled physical footprint.
After terrain entry, the resident stack remained around 335 MiB when returning
to the globe. Across this journey, the largest callback interval was 331.90 ms,
31 misses were recorded, and the sampled frame-window peak was 335.7 MiB.
The Mach process lifetime peak was 1,611.77 MiB, including transient globe
resource loading; deferring terrain does not eliminate that peak. Quiet
five-second windows reported 16.67 ms p95/p99/max and zero misses. These are
Simulator callback measurements, not headset frame-rate or thermal acceptance.
This journey uses 25-second stage holds and is not the 90-second global-terrain
performance protocol.

### Apollo regression and item 0 comparison

`/tmp/LM-Explorer-UX/Apollo-Ready` contains the complete eleven-stop ladder,
captured with the established 20-second Apollo baseline protocol, pinned
64 ppd globe tier and profiling enabled. Every PNG is byte-identical to
`/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2`. No attempts were rejected.
All eleven final windows report p95/p99/max 16.67 ms and zero misses.
`baseline-comparison.json` retains per-stop evidence and the previous chunk.

| Metric | Item 0 | Previous banding fix | Explorer Release |
|---|---:|---:|---:|
| Frame-window peak physical footprint | 406.5 MiB | 362.8 MiB | 366.8 MiB |
| Largest cold callback interval | 643.77 ms | 516.44 ms | 640.50 ms |
| Misses across all cold runs | 82 | 86 | 94 |
| Mach process lifetime peak | Not recorded | 1,602.60 MiB | 1,604.27 MiB |

The largest current callback occurred at the landing-detail stop. These
single-run cold measurements vary; they do not demonstrate a hitch improvement
or establish its cause. Settled behavior and accepted imagery are preserved.
The earlier intermediate Explorer ladder (`Apollo`) is retained separately;
its lower cold maximum is not substituted for this final-binary result.

All eleven pinned terrain resource hashes in
`/tmp/LM-Explorer-UX/apollo-assets.json` match the prior accepted resource list.
Neither terrain data nor AGC implementation changed in this milestone.

### Highland regression and remaining acceptance

`/tmp/LM-Explorer-UX/Highland-Ready/05-0.5m.png` is byte-identical to
`/tmp/LM-Terrain-Bands/Highland-Photographic-Encoding/05-0.5m.png`.
This uses -42°, 120°, photographic grade, +120-hour sunlight, altitude 249 m,
width 700 m and a 90-second wait after all 38 tiles became ready. Generation
took 13,905 ms. The final settled window reports p95/p99/max 16.67 ms, zero
misses and 141.0 MiB sampled footprint. The whole run peaked at 268.78 ms,
four misses and 148.2 MiB in frame-window samples; Mach lifetime peak was
1,602.46 MiB. The accepted softer outer detail and distant faceting remain.
The prior Highland slope/crash result is unchanged and was not rerun here.

Computer Use still reported a locked Mac on the final retry. Search/filter
buttons, the Sun popover, save alert, context menu, close/reopen and drag/pinch
interaction need a manual Simulator pass. The successful automated sequence
invokes production model actions, not UI taps. The generated-preview compiler
failure also remains open. No full-suite or flight-integration pass is claimed
by the four focused suites used for this UX milestone.

Physical Vision Pro validation remains required for gaze/pinch input, window
and globe placement, stereo continuity during immersion changes, readability,
comfort, EDR, GPU timing and sustained memory/thermal behavior. Cold loading
hitches and transient texture memory remain unresolved. The two unrelated
Xcode scheme-user edits and the separate AGC pad-load edit retain their starting
hashes. This remains an Explorer experience inside the existing LM app; a
separately packaged app target is a later distribution decision.

## Selected-place markers, 2026-09-05

Apollo landing sites use a compact flag symbol with a short mast, horizontal
support bar, simplified stars/stripes and one subtle fold. Other catalog places
and arbitrary coordinates use a conventional blue pin. A dark/white outline
keeps the symbols visible on bright terrain and shadow, and a dark name label
identifies the selected place. These are cartographic symbols, not scale models.

`LunarExplorerPlaceMarker.swift` draws the symbols as SwiftUI vectors. The
80-point glyph and 260-by-80-point label attachment retain their physical size
while the globe zooms. Both glyphs share a foot at (24, 76); the attachment
offset places that foot at the existing geographic marker anchor. A separate
RealityKit billboard turns the symbol and label toward the viewer without
moving the foot. The anchor sits 0.6% above the globe radius to avoid overlap
with the surface. The label has no hit target and does not intercept globe drag.
Markers appear only in the product's mixed globe, never the terrain/capture
presentation. The source catalog's `apollo` category selects the flag; the
catalog is decoded once for marker lookup.

Release build passed. Evidence lives in `/tmp/LM-Explorer-Markers`; executable
SHA-256 `dfa2cd4e5ee56af1264040361be9ee15b556ea58e2f35eeff8e6c6144abc6c6f`.
The `Journey/globe.png` and `Journey/selected.png` Simulator captures were
inspected at normal display size for the pin and flag respectively. Physical
head movement, stereo legibility and gaze/pinch comfort still need Vision Pro.

The five-stage production-session journey passed, including exact persisted
camera/sunlight restoration. All five screenshots were inspected: the marker
is absent in both terrain views and returns with the globe. Across this run,
frame-window footprint peaked at 330.2 MiB, the largest callback was 358.89 ms
and 26 misses were recorded. Mach lifetime peak was 1,587.89 MiB. This is another
single-run observation, not evidence that the unresolved loading hitches or
transient texture memory have improved. No terrain/physics code or data changed;
all eleven pinned resource hashes remain unchanged. Validation for this visual
change uses the Release build and renderer journey rather than new unit tests
that repeat the drawing implementation.

The representative Apollo `01-globe`, `03-crossfade` and `11-surface` captures
in `/tmp/LM-Explorer-Markers/Apollo` are byte-identical to item 0. All three
settled windows report 16.67 ms p95/p99/max with zero misses. This check sampled
three stops; the full eleven-stop ladder was last run for the preceding UX
commit. The unrelated scheme-user files and AGC pad-load edit are preserved.
