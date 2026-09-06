# Moon Explorer native controls

This continues item 6 of `LandAnywhereMoonPlan.md` and supersedes the browser
layout in `MoonExplorerExperience.md` and `MoonExplorerHIGReview.md`. Terrain
sources, residuals, contact geometry and Apollo inspection rendering retain
their existing contracts.

The owner subsequently rejected this browser's visual appearance. The
[visual refinement](MoonExplorerVisualPolish.md) supersedes its toolbar search,
plain place rows and destination layout while retaining the navigation work.

## Changes

- Native Explore, Saved and Settings tabs replace the custom browser shell.
  Explore and Saved use system search; place rows use native list selection.
  The custom close button and duplicate selected-row checkmark are removed.
  Settings also has a top-trailing toolbar shortcut.
- A bottom window ornament contains Globe / Surface and Lighting, with a
  60-point lighting target and help labels. Its width is 440 points inside a
  560-point window, or 620 inside 720 at accessibility text sizes. Zoom buttons
  are removed. Pinch remains available, with a native adjustable scale slider
  in Settings for people who cannot use that gesture.
- Lighting opens a centered native sheet with a Done control. At the largest
  text size, the earlier wide popover extended behind the Moon and obscured its
  date/time controls. The sheet uses the window's placement and avoids that
  initial-view overlap. The mode help text is shortened to fit its tooltip.
- Surface explicitly opens immersive terrain. A top Exit surface ornament
  returns to mixed immersion using the existing fade. The window's native
  close control dismisses the Explorer space through the window lifecycle.
- The detail card copies coordinates on tap and confirms the copy. Mission
  information opens a native sheet with launch/splashdown dates, crew, a NASA
  photograph and source links. Facts are bundled text; photographs load on
  demand and have an offline failure state. No image is added to the bundle.
- All 18 catalog locations have small 3D markers, native hover and accessibility
  labels; the selected marker is enlarged. The Apollo flag drawing is retained
  unchanged, as requested. Its name uses a glass attachment and the flag's foot
  is aligned to the geographic point. Rotation preserves the selected place
  and Surface navigates to that place, even if it has rotated out of view.

The earlier marker code assumed 1 mm per SwiftUI point. Actual RealityKit
attachment bounds measured 191.176 by 58.824 mm for the 260 by 80 point view,
about 0.735294 mm per point. That assumption visibly separated the flag foot
from the new site dot. Placement now derives the glyph's (24, 76) foot from
the actual attachment bounds, including text scaling. Earlier claims of exact
marker alignment in the HIG pass should be read with this correction.

Automatic rotation is optional and off by default. It advances at 0.35 degrees
per second, pauses during drag/scale and is disabled by Reduce Motion. It does
not claim to pause on gaze hover: the app uses system hover feedback without
reading gaze. Keeping motion off initially also follows Apple's advice to
minimize unnecessary peripheral motion.

Marker visibility uses a conservative horizon test in the initial viewer's
placement frame, plus ordinary depth testing. Rotating the Moon hides the
selected flag when it reaches the far side. Walking around the globe after
placement still requires physical validation; this is not head-pose-aware
label culling. No tracking permission or head-pose session was added.

## Sources and scope

The native controls follow Apple's [ornaments](https://developer.apple.com/design/human-interface-guidelines/ornaments),
[windows](https://developer.apple.com/design/human-interface-guidelines/windows)
and [spatial layout](https://developer.apple.com/design/human-interface-guidelines/spatial-layout/)
guidance. The mission dates, crew and photographs come from NASA's
[Apollo 11](https://www.nasa.gov/mission/apollo-11/),
[Apollo 12](https://www.nasa.gov/mission/apollo-12/),
[Apollo 14](https://www.nasa.gov/mission/apollo-14/),
[Apollo 15](https://www.nasa.gov/mission/apollo-15/),
[Apollo 16](https://www.nasa.gov/mission/apollo-16/) and
[Apollo 17](https://www.nasa.gov/mission/apollo-17/) pages.

The mixed globe still uses a Full Space, rather than a Shared Space volume.
Separate app packaging and Shared Space coexistence remain a distinct milestone.
This pass does not establish comprehensive HIG compliance or physical comfort.

## Validation

Evidence is under `/tmp/LM-Explorer-Overhaul`, on visionOS 26.5 Simulator
`8F38C0E7-6366-4DAC-9372-DCF6F9151DCB` with Xcode 26.6.

`Final-Focused.xcresult` passed 42 tests in five suites in 4.946 seconds, including
selected-place persistence through rotation and surface entry, automatic
rotation guards, globe directions at the poles/dateline and horizon visibility.
The remaining suites cover Explorer lifecycle, persistence, navigation and
terrain arrival, plus unchanged-diagnostic observation. The initial
`Focused.xcresult` passed 41 tests before the restoration fixes. No full-suite
pass is claimed. Existing Simulator AXLoading messages about the missing
SpringBoardUIServices accessibility bundle were emitted during the passing run.

`accepted-build.log` records the normal Release build after those tests and
before the final Lighting sheet/help adjustment.
Executable SHA-256:
`82d3719db991389f3606e9ed2d883bf9e65b9569163b49bad61a79deafd05c5d`.
Only the existing texture API deprecation, Sendable conversion and App Intents
metadata warnings remain; the new marker uses `accessibilityLabelKey`.

The initial `Journey` and `Browser` captures exposed the attachment alignment
error and are retained as intermediate evidence. `Browser` also confirmed that
the Apollo 11 photograph loads, and that native Saved, Settings, placement and
Lighting panels render. The other five remote photographs were sourced from
NASA but were not individually loaded in the Simulator.

`Journey-Final` confirmed the corrected flag foot but stalled during saved-view
restoration and is rejected. Its `restore-hang.sample.txt` shows repeated
SwiftUI/RealityKit layout updates. Attachment layout work was limited to a new
attachment or changed Dynamic Type scale, but `Journey-Verified` still stalled.
That second sample disproves attachment measurement as the sufficient cause.
The remaining synchronous terrain diagnostics were modifying an observed
struct field by field, even when no resident terrain value changed. They now
publish one snapshot only when it differs. A regression checks that unchanged
diagnostics do not fire an observation callback while changed values do.

The next `Journey-Acceptance` attempt was cancelled at startup after the forced
termination. Restored controls had opened the Explorer before the console's
automation handler ran; the console then reconfigured and toggled the open
space closed. Automated launch now uses the configuration already performed by
`MainMenuViewModel` and only opens a closed space. It leaves a restored window's
open or opening space alone. This correction is confined to explicit Explorer
launch arguments; the user's normal toggle keeps its existing behavior.

`Journey-Complete` passes all five stages after the diagnostics correction.
All five screenshots were inspected. The flag foot meets the selected site
dot, the bottom ornament fits inside the window width, and Surface exposes the
top Exit control. Saved and restored camera/sunlight JSON objects match exactly;
the final return restores mixed immersion. The run records a 724.44 ms largest
callback, 31 misses, 346.3 MiB frame-window footprint peak and 1,622.82 MiB Mach
lifetime peak. This is a single product journey with 25-second stage holds,
not the 90-second global terrain performance protocol or a hitch improvement.

`Browser-Accessibility` completed seven stages at the largest accessibility
text size. Its selected, mission, Saved, Settings, placement and far-side views
were inspected; the Lighting view was rejected for globe occlusion. The first
`Apollo` ladder was stopped after six captures to rebuild the Lighting fix;
it is incomplete evidence, not the final baseline comparison.

The intermediate `lighting-sheet-build.log` passes Release, executable SHA-256
`fd49caf090fedb143587582a9178b9bb6362c6413af8d84e746a3dd327ec89ab`.
The completed journey and 42-test run precede only the Lighting sheet/help
presentation adjustment; no navigation, persistence or terrain code changed
after them. The flag/pin glyph implementation also matches `b3e4f2e` exactly.

`Browser-Final` completed all seven stages, but its first sheet prototype is
also rejected: NavigationStack's default sheet width clipped the wider body.
The sheet now declares its outer width explicitly, matching the tested mission
sheet. `LUNAR_BROWSER_CAPTURE_LIGHTING_ONLY=1` selects a focused native-state
capture for checking that panel without repeating unrelated tabs.

The final `lighting-size-build.log` passes Release, executable SHA-256
`257507134a5e377d579ef4ed844e327cd3594b8923c9d82bc426db890ce082ec`.
`Lighting-Accessibility` passes and its screenshot was inspected: all controls
fit horizontally and vertically, with no Moon occlusion. The other six
`Browser-Final` views were also inspected. That sequence confirms far-side
marker hiding while the selected destination remains in the native list.
`Lighting-Normal` also passes with all controls visible. The Simulator text
size was restored to its original `large` setting before the final Apollo run.

The two unrelated scheme-user files retain their starting hashes:
`e193e5884cecfbe7a2a938adf71bb1205b621d1d18c8dcd0c533b437d40275a6`
and `a045fadc0d776acc2eeda45d58f3b10ef1d1d2fc1f6e0f226e7586e261c973d5`.
The separate AGC pad-load edit remains
`9a2a31a38b024e4f1bf92e34a499d146a16a1583ba33908f5db3f1b9a8b165c0`.
All eleven pinned terrain-resource hashes still match in `apollo-assets.json`.

`Apollo-Final` completes the full eleven-stop ladder with the final binary,
the pinned 64 ppd globe tier and the established 20-second Apollo wait. Every
PNG is byte-identical to `/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2`.
All eleven final quiet windows report p95/p99/max 16.67 ms and zero misses.
Every stop passed on its first attempt. `baseline-comparison.json` retains the
per-stop comparison and metrics, scoped to accepted process IDs in this run.

| Metric | Item 0 | Final overhaul |
|---|---:|---:|
| Frame-window peak physical footprint | 406.5 MiB | 366.0 MiB |
| Largest cold callback interval | 643.77 ms | 457.28 ms |
| Misses across all cold runs | 82 | 91 |
| Mach process lifetime peak | Not recorded | 1,604.18 MiB |

Cold timings and transient memory vary between runs. These results preserve
settled pacing and image invariance; they do not establish a sustained hitch
or memory improvement. Global corridor, Highland slope/crash and flight
integration tests were not rerun for this controls/diagnostics change. Their
previous results and open failures remain controlling.

The capture scripts exercise production model actions and native view state,
not synthesized taps. The Mac remained locked during Computer Use validation.
Manual search, copy, tab selection, pin acquisition, popover scrolling,
drag/pinch and native close/reopen therefore remain unverified. The prior
generated SwiftUI preview failure is separate from successful Simulator builds
and rendering.

Physical Vision Pro validation remains required for gaze/pinch and VoiceOver
navigation, actual head movement and marker occlusion, window/globe placement,
recentring, stereo continuity, text readability, EDR, GPU time and sustained
memory/thermal behavior. Known cold publication hitches and transient memory
peaks are still open. No terrain or AGC failures are closed by this UI pass.
