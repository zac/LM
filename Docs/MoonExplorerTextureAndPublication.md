# Globe texture peak and terrain publication

This follow-up implements the next performance work in
`MoonExplorerPerformance.md`, under the contracts in `LandAnywhereMoonPlan.md`.
Evidence is retained in `/tmp/LM-Texture-Publication-2026-09-06/`.

The subsequent source-read attribution and sampled RealityKit import investigation
are in `MoonExplorerEntryAndImport.md`.

## Protocol

The control starts from `ad9d416` with additional texture-dimension and mesh
timing diagnostics. Release runs use Xcode 26.6, visionOS 26.5 Simulator and
device `8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`. Builds, tests, offline encoding
and captures run separately. Completed XCTest clones are shut down before
performance runs. A fresh launch creates a new process without purging OS
caches. Mach lifetime peak catches allocations between frame windows.

`Control` and `Worker-Soak` use the same acknowledged five-image journey plus
two repeated Saved restorations, sunlight changes and globe returns. This is
a bounded sequential comparison, not a statistical or physical-device test.
Async phase durations include suspension and framework work. A worker-thread
marker does not prove that every internal framework operation avoids the main
thread or that the renderer never waits for resource preparation.

## Texture attribution and candidate

The pinned 64 ppd source contains 23,040 × 11,520 pixels. The current Simulator
importer realizes a 5,760 × 2,880 RGBA8 sRGB texture with 13 mip levels. Both
the browser and fixed capture path report those dimensions.

The matched JPEG XL control takes 1,389.56 ms and reaches a 1,622.13 MiB
lifetime footprint peak during texture loading. Explicit worker-side ImageIO
decode with subsampling still reaches 1,612.36 MiB before texture creation.
This localizes the large transient allocation to ImageIO's JPEG XL decode.
It is not evidence of a resident 1.6 GiB GPU texture.

Several alternatives were prepared only in temporary test apps:

| Candidate | Storage | Texture-load peak | Acceptance |
| --- | ---: | ---: | --- |
| Full-resolution lossless modular JPEG XL | 115.84 MiB | 1,355.00 MiB | Insufficient memory reduction; not selected |
| Full-resolution lossless PNG | 143.85 MiB | 420.44 MiB | Render differs; not selected |
| Subsampled grayscale PNG | 9.5 MiB | 196.10 MiB | Decoded samples match, rendered colors do not; rejected |
| Copied GPU mip chain | About 18 MiB | 230–282 MiB | Whole-globe image differs; rejected |
| Imported base pixels in Display P3 PNG | **15.378381 MiB** | **241.94 MiB** | All three fixed globe/handoff PNGs are byte-identical |

The selected candidate uses the actual imported base-level RGBA pixels with a
Display P3 profile, then runs through the normal color-texture importer to
generate mipmaps. Its texture call takes 240.76 ms in the fixed globe capture.
`GPUBase-P3-Ladder/01-globe.png` and `GPUBase-P3-Handoff/02-global-detail.png`
and `03-crossfade.png` match item 0 byte for byte. Source and candidate hashes,
exact byte count, exporter environment and capture hashes are in
`Texture-Candidate.json`. The candidate SHA-256 is
`840379f0f6cc9311e3674086579bce2a6cc8bd30d822cb1e63e3200e2bc2303e`.

The original full-resolution JPEG XL and 16 ppd fallback remain unchanged.
The candidate is not yet in the production bundle. An owner request for up to
16 MiB is pending because plan section 3 requires sign-off for every further
bundled addition. The earlier 32 MiB approval applies to the elevation base.
Physical Vision Pro effective resolution, color, memory and pacing still need
validation; the Simulator match does not close those gates.

## Terrain change

Commit `679cd6c` contains the terrain preparation change and its regression tests.

The control imports the three base meshes synchronously on the main actor.
Its largest import takes 118.27 ms. Publishing a fine-terrain generation also
filters the million-vertex measured base, taking 75–83 ms, then imports the
replacement mesh in another 111–116 ms on that actor.

Base descriptor preparation and the original async mesh importer now run from
an explicitly detached task. A requested ownership change prepares its base
mask and mesh ahead of publication. The previous generation remains visible
until both the replacement base and all its fine tiles are ready. Their
attachment, removal and base swap form one main-actor transaction.

Cancellation reaches both workers, is checked during the triangle-filter loop
and before resource import, and discards obsolete results using a request token.
The existing synchronous reset for an explicit appearance-mode change remains;
it is outside the repeated surface-entry workload and is still a possible hitch.

The first async-import version retained an additional original mesh for resets.
`Final` is that superseded experiment, not the final accepted binary. It raised
returned footprint from 344.64 to 412.21 MiB and still showed import stalls.
That retained duplicate was removed. A low-level buffer experiment reduced
index publication to about 5 ms but changed nine Apollo images. It was rejected,
and its `Buffers-Apollo` captures are retained as failed acceptance evidence.
The final change keeps the original importer and rendering path.

## Validation and remaining work

The final worker test result, `Worker-Focused.xcresult`, records 81 passed,
zero failed or skipped across source-backed terrain, progressive terrain,
Explorer, experience and globe suites. New regressions check exact surviving
triangles and untouched vertex attributes, plus cancellation before ownership
preparation or mesh import. The Xcode request timed out, but the completed
result bundle independently confirms the pass. No full-suite pass is claimed.

The final Release build succeeds (`build-worker-final.log`). The frozen
`Worker-Final.app/LM` executable SHA-256 is
`2c2c44868cd82cd54d5726faf73a9bc74e28f7c54f7927532cb045e2f7862bc2`.
The completed `Worker-Soak` journey passes both exact camera/sunlight
restorations and all five acknowledged capture stages.

| Matched two-cycle journey | Control | Prepared worker version |
| --- | ---: | ---: |
| Frame windows | 59 | 59 |
| Whole-run worst callback | 352.52 ms | 427.05 ms |
| Reported missed callbacks | 64 | 71 |
| Maximum window p95 / p99 | 23.85 / 132.24 ms | 28.83 / 117.64 ms |
| First surface entry onward: worst callback | 277.78 ms | 267.59 ms |
| First surface entry onward: callbacks over 100 ms | 17 | 15 |
| Four base-load intervals, total | 1,466.00 ms | 1,586.61 ms |
| Frame-window footprint peak | 436.1 MiB | 349.4 MiB |
| Kernel lifetime footprint peak | 1,622.13 MiB | 1,620.02 MiB |
| Final returned footprint | 344.64 MiB | 348.61 MiB |
| First-to-second returned footprint drift | −0.14 MiB | +0.36 MiB |

The five final publication transactions total **0.862 ms**, with a maximum of
**0.243 ms**. Ownership filtering now takes up to 105.68 ms on a worker;
the ownership import interval takes up to 165.83 ms asynchronously. This
removes the synchronous filtering/import sequence from the publication
transaction, but does not establish a whole-experience pacing improvement.
Base-load elapsed time increased about 8% in this pair. The largest whole-run
stall is still during the unchanged JPEG XL startup. First surface entry also
retains a roughly 268 ms callback, and subsequent imports coincide with
callbacks around 140 ms. Framework resource preparation and entry setup remain
open work.

`control-summary.json` and `worker-soak-summary.json` retain the complete
measurements. `surface-entry-comparison.json` counts individual hitch events
from the first `apollo-base-before` checkpoint through the final returned
checkpoint, a roughly 244-second interval in both runs. This includes the
callback spanning that first checkpoint; it is not a claim of isolated mesh
CPU time. The larger number of shorter hitches (57 to 64 in that interval)
also prevents claiming a general frame-budget pass.

`Worker-Apollo` repeats item 0's eleven-stop Release ladder with 20-second
holds and the original pinned 64 ppd source. **All eleven PNGs match item 0
byte for byte.** Every final quiet window has mean/p95/p99/maximum 16.67 ms
and zero misses. Crossfade, immersive journey and surface captures were also
inspected visually.

| Full ladder, including startup | Item 0 | Final worker build |
| --- | ---: | ---: |
| Frame-window footprint peak | 406.5 MiB | 362.3 MiB |
| Worst callback | 643.77 ms | 600.93 ms |
| Missed callbacks | 82 | 94 |
| Kernel lifetime footprint peak | Not recorded | 1,603.41 MiB |

`Worker-Apollo/baseline-comparison.json`, `performance.tsv`, `profile-runs.tsv`
and `timing.json` retain the accepted image hashes and PID-scoped measurements.
Quiet windows and smaller maxima coexist with more startup misses. They do
not close overall performance acceptance or establish a sustained headset
frame rate. The texture candidate's three matching images are separate from
this complete eleven-image validation of the final terrain change.

The texture companion needs its pending storage approval before bundling.
Remaining framework-import stalls, explicit appearance-mode resets and global
terrain arrival/publication need further work. Physical Vision Pro still has
to validate 90 Hz pacing, actual GPU pressure, thermals and stereo/gesture
comfort. No AGC source changed. Both pre-existing scheme-user files retain
their original hashes.
