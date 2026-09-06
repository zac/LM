# Moon Explorer HIG improvements

This follows the Explorer milestone in `LandAnywhereMoonPlan.md`. It addresses
the implementation gaps identified against Apple's [designing for visionOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-visionos),
[immersive experiences](https://developer.apple.com/design/human-interface-guidelines/immersive-experiences/),
[spatial layout](https://developer.apple.com/design/human-interface-guidelines/spatial-layout/)
and [accessibility guidance](https://developer.apple.com/documentation/visionos/improving-accessibility-support-in-your-app).
It does not close physical-device acceptance or claim comprehensive HIG compliance.

## Changes

- Product navigation fades content out, changes the camera while hidden, waits
  for terrain readiness, then fades in. It no longer flies or zooms the camera
  automatically. Return to globe also fades. Reduce Motion uses shorter opacity
  transitions, with no simulated travel in either setting. Explicit renderer
  inspection and capture launches retain the legacy camera path.
- Opening and closing reset the product to mixed immersion and cancel pending
  transitions. Reopening cannot inherit a full-immersion arrival in progress.
- The globe starts relative to the viewer using a one-time head anchor. It
  remains stationary as the viewer moves. Native position sliders adjust its
  horizontal position, height and distance; reset creates a new one-time anchor.
  This uses RealityKit's privacy-preserving anchor without reading head poses.
- Toolbar labels and close/source controls have 60-point target frames. Toolbar
  spacing is 8 points, giving at least 68-point center separation. Place rows
  have a 60-point minimum height and explicit hover feedback.
- The browser grows from 520 to 680 points at accessibility text sizes and
  scrolls as a whole. The selected destination precedes the results at those
  sizes. Place filtering becomes a menu. Descriptions wrap; the duplicate
  descriptive paragraph is omitted from the compact terrain card. The Sun and
  placement panels scroll, and the Sun offset slider has an accessibility label.
- The selected-place attachment scales with Dynamic Type, including the offset
  that keeps the foot at the geographic coordinate. The Apollo cloth now has a
  thin dark silhouette and curved free edge. The white support bar and mast
  remain. Removing the thick double outline eliminates the rectangle-like frame;
  the place name uses a capsule background.

The default globe center is 1.05 m right, level with the initial head anchor and
2.0 m forward. Its allowed physical radius remains 0.334–0.491 m. These values
are provisional starting placement, not a headset comfort measurement. The
native window moves independently. Users can adjust both placements.

## Validation

Evidence is under `/tmp/LM-Explorer-HIG`. The first `Journey` passed its state
checks but its globe overlapped the controls. `Journey-Spaced` increased lateral
separation but pushed the place label to the view edge. Both are rejected as
final layout evidence and retained for comparison.

The focused Release Simulator run in `Focused.xcresult` passed 38 tests in four
suites in 4.794 seconds. The added regression verifies reduced-motion fades,
constant camera width during those fades, terrain arrival, and cancellation
when reopening during a return transition. No full-suite pass is claimed.

The final normal Release build is `accepted-build.log`; executable SHA-256 is
`457dde8767c38b00ad595c5a5ce0494e108c567b05b4b6eebaa9eabee4d25979`.
The destination is visionOS 26.5 Simulator
`8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`, built with Xcode 26.6.

`Journey-Accessibility` passed with the Simulator's largest accessibility text
size and `LUNAR_CAPTURE_REDUCE_MOTION=1`. All five screenshots were inspected.
The selected card and Explore action fit before the scrolling results; terrain
details can extend below the scroll viewport. The enlarged marker remains at
its geographic anchor and clear of the panel. Saved and restored camera/time
JSON objects match exactly. The Simulator text size was restored to `large`.
The flag drawing is committed separately as `1692cca`.

That journey recorded a 412.09 ms largest callback, 25 misses, a 329.1 MiB
frame-window footprint peak and a 1,587.49 MiB Mach lifetime peak. This is a
single product journey with 25-second stage holds, not the 90-second global
terrain performance protocol or evidence that the known hitches improved.

`Journey-Accepted` also passed all five stages at the original text size, with
each screenshot inspected and exact saved/restored camera/time equality. Its
largest callback was 405.34 ms, with 23 misses, a 322.0 MiB frame-window peak
and a 1,588.14 MiB Mach lifetime peak. The final globe and selected-place views
have clear separation between the globe, panel and label. These captures check
the initial stationary Simulator view, not arbitrary user window placement.

`Apollo` completed the full eleven-stop ladder with the established 20-second
Apollo wait, pinned globe tier and profiling enabled. All eleven PNGs are
byte-identical to `/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2`. All eleven
final windows report p95/p99/max 16.67 ms and zero misses. No attempts were
rejected. `Apollo/baseline-comparison.json` retains per-stop evidence.

| Metric | Item 0 | Previous Explorer ladder | HIG pass |
|---|---:|---:|---:|
| Frame-window peak physical footprint | 406.5 MiB | 366.8 MiB | 365.8 MiB |
| Largest cold callback interval | 643.77 ms | 640.50 ms | 608.14 ms |
| Misses across all cold runs | 82 | 94 | 92 |
| Mach process lifetime peak | Not recorded | 1,604.27 MiB | 1,602.38 MiB |

Cold timings and transient memory vary between runs. These measurements
preserve settled behavior; they do not establish a hitch or memory improvement.
All eleven pinned terrain-resource hashes match in `apollo-assets.json`.
Highland slope/crash, global corridor and flight-integration tests were not
rerun for this presentation-only change. Their prior results and open failures
remain controlling. The Release build retains existing texture API deprecation,
Sendable conversion and App Intents metadata warnings.

The two unrelated Xcode scheme-user files retain their starting SHA-256 hashes,
`e193e5884cecfbe7a2a938adf71bb1205b621d1d18c8dcd0c533b437d40275a6`
and `a045fadc0d776acc2eeda45d58f3b10ef1d1d2fc1f6e0f226e7586e261c973d5`.
The separate AGC pad-load edit retains
`9a2a31a38b024e4f1bf92e34a499d146a16a1583ba33908f5db3f1b9a8b165c0`.

## Remaining validation and scope

Computer Use reports the Mac is locked. The integration capture invokes
production session actions; it does not tap UI controls. Manual search/filter,
popover scrolling, placement/reset, drag/pinch, hover and close/reopen checks
remain open. The earlier generated SwiftUI preview failure remains separate
from successful Simulator rendering.

On Vision Pro, validate seated and standing placement, recentering, stereo
continuity, gaze/pinch target acquisition, VoiceOver navigation, largest text,
Reduce Motion, sunlight readability, EDR, GPU timing and sustained thermal and
memory behavior. The known cold publication hitches and transient texture
memory peaks remain unresolved.

The mixed globe still occupies a Full Space. Other apps do not coexist there
as they would with a Shared Space volume. Converting the browser/globe to a
volume and creating a separately packaged app remain a distinct lifecycle and
distribution milestone. No terrain data, residual limits, contact geometry or
AGC implementation changes belong to this HIG pass.
