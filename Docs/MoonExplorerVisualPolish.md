# Moon Explorer visual refinement

This continues Stage 2 item 6. The owner rejected the visual result of the
native-controls overhaul and asked for closer adherence to the supplied
mockup, while retaining the Apollo flag. This pass supersedes the Explore
layout in `MoonExplorerOverhaul.md`; the navigation and terrain contracts stay
in force.

## Visual decisions

The actual Simulator capture exposed three problems: toolbar search collapsed
into a small truncated capsule, plain rows lost their visual grouping, and
the destination footer consumed space without a clear primary action.

- Explore now has a prominent Moon heading, full-width search, visible filter
  chips and rounded place cards. Four featured places fit at the normal text
  size. A fine blue outline and restrained fill identify the selected card.
- The destination footer groups the title and copyable coordinates, with a
  blue Explore site action and secondary information/save controls. Explore
  site calls the same guarded mode transition as the Globe / Surface picker.
- Native text fields replace collapsed toolbar search in Explore and Saved.
  This deliberately revises the earlier literal `.searchable` requirement in
  response to the owner's visual feedback. Text entry, keyboard submission,
  clear-search and coordinate entry remain available.
- Saved uses the same rounded card spacing and a plain empty state, replacing
  its large default list blocks. The capture run seeds an isolated bookmark
  library to review both empty and populated states without changing saved
  user views.
- Typography uses semantic styles. Normal width remains 560 points; height
  is 800. Accessibility width remains 720, with destination and results on
  one scroll surface. Rows wrap instead of shrinking their text.
- A 22% black content tint improves contrast over the system glass in bright
  surroundings. The system continues to render the window material. This
  does not attempt to reproduce the generated mockup's room or lighting.
- The native tab rail, Globe / Surface ornament, Lighting sheet, Exit surface
  control, placement and accessible zoom remain. Apollo's flag, its attachment
  geometry, the globe and terrain rendering are untouched.

The regional subtitles use NASA's descriptions of
[Apollo 11 in the Sea of Tranquility](https://nssdc.gsfc.nasa.gov/planetary/lunar/apollo11.html),
[Apollo 17 at Taurus–Littrow](https://www.nasa.gov/mission/apollo-17/), and
[Tycho in the southern highlands](https://science.nasa.gov/photojournal/the-floor-of-tycho/).
These are presentation labels; the pinned coordinates and source catalog are
unchanged.

## Validation

Evidence root: `/tmp/LM-Explorer-Visual-Polish-2026-09-06`.
Environment: Xcode 26.6, visionOS 26.5 Simulator,
`8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`.

`Selected-1` and `Accessibility-1` record the initial card layout before the
contrast tint. `Selected-2` records the tint before the final coordinate hit
target and Saved-search adjustments. These are iteration captures, not the
final binary's acceptance set.

`Browser-Final` is also an intermediate run: review caught the remaining dark
default blocks in Saved. The capture pipeline was stopped for that refinement;
`Browser-Accepted` is its replacement.

The browser capture script now supports focused selected-place and search
runs, in addition to its existing Lighting and full-panel modes. These opt-in
probes drive production view state and retain the ten-second settle interval;
they do not synthesize keyboard or pointer input.

`Browser-Accepted` completed all eight panel stages: selected destination,
mission information, empty Saved, populated Saved, Settings, placement,
Lighting and far-side selection. Each was visually inspected. `Search-Final`
completed the result, no-result, valid-coordinate and coordinate-selected
states. The final state displays 12.5000° N, 45.2500° W and its globe marker.
`Accessibility-Final/selected.png` records the largest Dynamic Type size;
search, filters and destination actions fit, with results continuing below in
the scroll view. The Simulator text-size setting was restored to `large`.

`Focused.xcresult` passed the existing 42 tests in five suites in 4.784 seconds.
This run preceded the final Saved-card layout and capture-fixture adjustment;
the session/navigation implementation was unchanged. The final normal Release
build is recorded in `build-accepted.log`. No new layout-mirroring unit tests
were added. The passing test run emitted the existing Simulator AXLoading
warning for the missing SpringBoardUIServices accessibility bundle.

Final executable SHA-256:
`ce2a35d414e02124e90d881e9b8495cee0708e6f11ec17c0b62b14b76ca4c0c9`.

`Journey-Final` completed all five stages, including surface entry, return to
the globe and saved-view restoration. All five images were inspected. Its
`camera-and-sunlight.json` contains exactly equal saved and restored values;
the run reports `cameraAndSunlightExact=true persistenceReload=true`.

The browser run's frame windows peak at 112.8 MiB, with a 179.04 ms longest
frame and 15 missed frames across the run. The terrain journey peaks at
326.3 MiB in frame windows, with a 308.48 ms longest frame and 33 missed frames.
Their separately sampled process lifetime peaks are 1597.21 and 1596.10 MiB.
These are different workloads from the item 0 ladder; they are not evidence
of a terrain performance improvement. Transient publication/startup hitches
and memory variation remain open.

`Apollo-Final` completed all eleven accepted 64 ppd ladder stops. Every PNG is
byte-identical to `/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2`. Every final
quiet frame window has mean/p95/p99/max 16.67 ms and zero missed frames. The
short capture protocol measures quiet windows, not sustained hardware load.

| Ladder measurement | Item 0 baseline | This run |
| --- | ---: | ---: |
| Frame-window physical-memory peak | 406.5 MiB | 364.6 MiB |
| Longest frame including startup | 643.77 ms | 493.49 ms |
| Missed frames including startup | 82 | 81 |
| Process lifetime physical-memory peak | Not recorded | 1603.19 MiB |

The source of this table is `Apollo-Final/baseline-comparison.json`, with
accepted PIDs scoped by the ladder manifest. `performance.tsv` and
`profile-runs.tsv` retain per-stop evidence. Treat the lower observed peaks as
run variation; this pass does not establish a performance optimization.

The final Release build, 18 product-state captures and eleven terrain image
comparisons passed. Direct UI interaction and physical-device acceptance remain
open below. The two pre-existing scheme-user file modifications retain their
original hashes, and no AGC source or flag drawing changed.

## Remaining device checks

Computer Use could not interact with the Simulator because the Mac was locked.
Actual keyboard focus/submission, scrolling, hover and tap targets still need
manual validation. State-driven screenshots are not evidence of those inputs.
Physical Vision Pro remains necessary for glanceability, stereo, real-room
contrast, gaze/pinch comfort, placement and sustained performance. Existing
terrain/flight acceptance limitations remain in the controlling plan.
