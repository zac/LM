# Moon Explorer startup and navigation performance

This follow-up uses `LandAnywhereMoonPlan.md` as the controlling plan. All
source, residual, rendered-contact and Apollo image contracts remain intact.
The evidence root is `/tmp/LM-Explorer-Performance-2026-09-06/`.

The subsequent texture-decoder attribution, prepared color companion and
terrain-publication work are recorded in `MoonExplorerTextureAndPublication.md`.
Read that report for the current performance state and pending storage decision.
`MoonExplorerEntryAndImport.md` continues with source decoding and a sampled
main-thread mesh-import call stack.

## Protocol and attribution

Release runs use Xcode 26.6 and the visionOS 26.5 Simulator
`8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`. Captures run serially, without concurrent
builds, tests or video recording. A cold launch means a fresh app process;
the OS and filesystem caches are not purged. Mach lifetime peak and phase
checkpoints complement the original five-second frame-window sampler.
Simulator Metal counters remain unavailable. These are callback timings and
process footprints, not headset GPU pacing or memory-pressure measurements.

The added markers bracket the globe texture call, terminator preparation,
Apollo base loading, synchronous base-grid construction and rock realization.
An async phase's elapsed duration includes suspension. A `main=true` end marker
does not mean its entire duration blocked the main thread. Grid construction
is synchronous, so its interval does measure work occupying that thread.

`LUNAR_PROFILE_SOAK_CYCLES=5 Tools/CaptureMoonExplorerJourney.sh ...` extends
the existing five-stage journey with five Saved restorations, sunlight changes
and globe returns. Each iteration checks exact camera/sunlight restoration,
samples surface memory after arrival and samples returned memory after a
25-second globe hold. The probe uses an isolated temporary Saved library and
restores the original library. It does not synthesize taps, keyboard input or
opening/closing whole app windows.

`Tools/SummarizeMoonExplorerProfile.py <capture-directories...>` scopes each
report to the PID in `stages.tsv`. Missing checkpoints, failed sequences and
incomplete cycle counts return a failing exit status. Its completion field is
sequence validation, not visual acceptance. Five Python tests cover stale PIDs,
missing checkpoints, failure precedence, acknowledged completion and separate
lifetime/returned memory.

## Instrumented control

The initial instrumented binary is
`a2d05b122c43bb8d1fc1be1dbd9f7e9f44dfc2c0fafd338b4d715c206d412cde`.
Xcode MCP and the pinned Release build passed.

| Fresh 64 ppd launch | Texture call | Lifetime peak | Worst callback | Misses |
| --- | ---: | ---: | ---: | ---: |
| Cold-1 | 1,487.5 ms | 1,621.4 MiB | 509.02 ms | 5 |
| Cold-2 | 1,364.1 ms | 1,598.4 MiB | 84.55 ms | 5 |
| Cold-3 | 1,426.2 ms | 1,596.5 MiB | 168.44 ms | 4 |

In every run, the kernel peak jumps during the 64 ppd `TextureResource` load
and the current footprint falls immediately afterward. This localizes the
large allocation to texture decoding/realization. It does not distinguish the
codec's working buffers from RealityKit conversion or driver copies. The
monolithic source is 23,040 by 11,520 pixels. No quality reduction or asset
replacement was made to mask that peak.

The same binary's explicit `Cold-16ppd` control loads the existing pinned base
in 154.94 ms. Lifetime peak increases from 80.03 MiB to 197.36 MiB inside the
texture call. That is a diagnostic comparison of different resolutions and
codecs, not an approved quality change or a way to distinguish their costs.

`Soak-Control` completed all five repeat cycles and exact Saved restoration.
Seven surface loads spent 451.31 ms total constructing base grids on the main
actor, with a 69.85 ms maximum. Rocks took at most 2.77 ms; terminator updates
took at most 13.38 ms. The run had a 427.53 ms worst callback and 90 misses.
Returned footprint was 330.409 MiB after cycle 1 and 330.378 MiB after cycle 5,
a -0.031 MiB change. This bounded run shows no accumulating returned footprint.
The terrain remains resident while browsing, so the return floor should not
be compared with a never-visited globe-only process as a leak test.

The first control's `immersive.png` is invalid: it shows the returned globe,
and is byte-identical to `returned.png`. Its capture timestamp falls after
the return marker. Log-stream delivery lag can let the 25-second stage expire
before the shell takes its screenshot. The other restored-surface image was
visually inspected and does show terrain. The timing record is retained, but
this control is not accepted as a complete five-image visual journey.

The capture protocol now uses a unique per-run stage/acknowledgement file pair.
The app holds each stage for at least 25 seconds and until the shell confirms
the screenshot finished; missing acknowledgements fail after 120 seconds.
The shell checks that the stage is still current before acknowledging it,
then removes its uniquely named files on exit. This avoids treating delayed
logs as proof of the currently displayed view.

## Worker preparation and verification

Base height decoding, grid construction and parent collars now run in a
detached CPU task. The existing operation order and Float32 calculations are
unchanged. Value buffers cross back to the main actor as `Sendable` data;
RealityKit mesh, material and entity creation remain on that actor. Cancellation
propagates to the worker, is checked between bands and is checked again before
resource realization. A regression test cancels before preparation and proves
that cancellation wins over attempting to read a bundle without terrain assets.

The final Release executable is
`61e5352c029089e07545edf253aa3fd402ca78432b04228c428b784120b9399a`.
The ordinary build is in `build-optimized.log`. Xcode's test tool timed out,
but its completed result bundle confirms **86 passed, zero failed or skipped**
across source-backed terrain, progressive terrain, detail streaming, Explorer,
Explorer experience and globe tests. It is retained as
`Xcode-Focused-Passed.xcresult`. An unnecessary fallback was stopped once that
result was available; `Focused.xcresult` is that interrupted attempt and must
not be used as a passing result. A temporary capture-token string escaping
compile error was corrected before the passing build and tests.

The first after-run, `Soak-Optimized`, was interrupted and excluded from the
performance comparison. A process snapshot found several Simulator
`mediaanalysisd` processes near 90% CPU each. Five XCTest clones created by this
task were still booted in the separate `XCTestDevices` set, although the normal
`simctl list devices booted` showed only the primary Simulator. Those five
clones were shut down. The pre-existing preview Simulator was preserved.
`simulator-processes.txt`, `booted-after-tests.json`, `after-run-host-load.txt`
and `clean-run-host-load.txt` record the finding and the clean repeat's context.
All five acknowledged images in the interrupted run were captured; its new
`immersive.png` was inspected and shows the correct surface state.

`asset-hashes.json` confirms all eleven original pinned terrain assets match
`c950d46` byte for byte. Source dimensions, codecs, residual caps, measured posts,
contact and flag artwork are unchanged. The two user scheme files are excluded
from both commits. No AGC source changed.

## Final matched workload

`Soak-Final` completed the acknowledged five-image journey and all five repeat
cycles. Every journey image was checked for the intended presentation. Saved
camera/sunlight values match exactly after persistence reload and each repeat.
`soak-comparison.json` retains both accepted PIDs and all checkpoints.

| Measurement | Instrumented control | Worker preparation |
| --- | ---: | ---: |
| Base-grid CPU time, seven loads | 451.31 ms on main | 450.33 ms on worker |
| Largest base-grid CPU interval | 69.85 ms on main | 70.01 ms on worker |
| Base-load elapsed total, seven loads | 2,706.12 ms | 2,511.59 ms |
| Largest base-load elapsed interval | 444.86 ms | 397.50 ms |
| Returned memory, first cycle | 330.409 MiB | 344.112 MiB |
| Returned memory, fifth cycle | 330.378 MiB | 343.956 MiB |
| Whole-run largest callback | 427.53 ms | 448.28 ms |
| Whole-run missed callbacks | 90 | 107 |

Both returned-memory series are bounded in these five cycles, but the worker
run's retained floor is about 14 MiB higher. Moving CPU work does not eliminate
the startup texture peak or establish an overall footprint improvement.

The whole runs contain 95 and 96 frame windows; acknowledged captures can extend
the initial stage holds. A narrower comparison uses the first returned checkpoint
through the fifth, covering repeat cycles 2 through 5 with no screenshots. Those
intervals last 240.50 and 240.58 seconds. Hitches over 25 ms increase from 49 to 56,
while their maximum falls from 313.58 to 237.88 ms. This is a measured removal of
one synchronous main-actor cost, with mixed aggregate results, not a frame-budget
pass. Single sequential runs do not establish statistical significance. The
interval report is `repeat-interval-comparison.json`.

## Apollo baseline and remaining gates

`Apollo-Final` repeats item 0's eleven-stop Release ladder with 20-second holds
and the pinned 64 ppd texture. **All eleven PNGs are byte-identical to item 0.**
Every final quiet window has mean/p95/p99/maximum 16.67 ms and zero misses.

| Ladder measurement | Item 0 | Final worker build |
| --- | ---: | ---: |
| Frame-window physical-memory peak | 406.5 MiB | 366.2 MiB |
| Worst callback including startup | 643.77 ms | 256.26 ms |
| Missed callbacks including startup | 82 | 96 |
| Kernel lifetime footprint peak | Not recorded | 1,602.94 MiB |

`Apollo-Final/baseline-comparison.json`, `performance.tsv`, `profile-runs.tsv`
and the original captures retain the evidence. Quiet windows are not a sustained
headset load test. Lower maxima coexist with more misses; neither the ladder nor
the journey closes overall performance acceptance.

The next performance work is the 64 ppd texture's transient decode/realization
allocation, preserving resolution, pinned provenance and visual quality. The
remaining surface-entry and publication hitches also need finer attribution
before another scheduling or resource-lifetime change. Global terrain generation
and arrival gates in `Stage2GlobalTerrainValidation.md` remain open; this repeat
uses Apollo 11 and does not constitute a multi-site or whole-app open/close soak.
Physical Vision Pro still has to validate 90 Hz pacing, actual GPU memory pressure,
thermals, stereo continuity and real gesture comfort. No physical-device or full
test-suite pass is claimed.

Diagnostics and capture tooling are committed as `9cabbd3`. The worker preparation,
cancellation regression and this report are a separate focused commit.
