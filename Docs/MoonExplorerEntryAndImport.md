# Explorer entry and RealityKit mesh import

This follows `MoonExplorerTextureAndPublication.md` on `terrain-realism-and-explorer`.
`LandAnywhereMoonPlan.md` remains the controlling plan. Evidence is in
`/tmp/LM-Entry-Import-2026-09-06/`.

## What the investigation establishes

Explorer decoded the Apollo height field and measured albedo on the main actor.
The new control separates those calls from base mesh preparation. Across four
entries, height decoding takes 12–16 ms per entry and albedo takes 9–11 ms.
This is avoidable main-actor work, but it does not account for the whole first
entry stall, which reaches 233 ms in that control.

The source reads now run in a detached task. Cancellation propagates to that
task and is checked between reads and before installing the results. Height
failure still fails the load; unavailable measured albedo retains the existing
fallback. The original source files, sampling, material import, mesh importer
and publication transaction remain unchanged.
Commit `3f905f6` contains the source-read change and geometry regression test.

The separate `Entry-Sample/sample.txt` identifies main-thread mesh work inside
RealityKit's async descriptor initializer. The sampled call chain is:

```text
Main Thread
  LMTerrainMeshBuilder.meshAsync(from:)
    MeshResource.init(from:)
      REAssetManagerMeshAssetCreateFromModelsWithOptionsNullable
        makeMeshAssetDataHelper
          makeMeshAssetDataFromDescriptor
            makeMeshAssetDataFromGeomScene
              makeConditionedMeshForGPU
                computeTangentsAndBitangents
```

Mesh packing and bounding-box computation also appear beneath that initializer.
The caller being detached and the public async initializer being nonisolated
do not keep all framework work off the main thread. This explains the earlier
import-correlated hitches more precisely than the phase timers alone.

The sample is a separate seven-second capture with a nominal 1 ms sampling
interval, using the frozen control app. It completed and symbolicated. Sampling
substantially perturbed the run, so its callback durations are not performance
acceptance evidence. `Entry-Sample/main-import-excerpt.txt` retains the relevant
stack. The first entry also includes SwiftUI/UIKit layout and the immersion
transition; this investigation does not attribute its entire delay to one call.
In the final journey without sampling, a 180.14 ms callback ends at
15:09:01.323050, before the first source worker starts at 15:09:01.323753.
That gap precedes both source decoding and the first base mesh import. It
must not be counted as CPU time in either of those phases.

## Rejected buffer import

The experiment constructs a `MeshResource.Part` directly from the existing
positions, normals, UVs and triangle indices, then imports `MeshResource.Contents`.
This bypasses descriptor conditioning and reduced the largest base's import
interval in early captures. It does not satisfy the visual contract.

`Contents-Geometry.xcresult` passes the comparison of exposed vertex attributes,
indices, material count and bounds against the original descriptor path.
Nevertheless, `Contents-Apollo/03-crossfade.png` and `04-orbit.png` differ from
item 0. The orbit image has normalized RMSE 0.00227957. The globe-only images
match. The ladder was stopped after the failure; it is not a completed
acceptance run. Exact exposed geometry is insufficient to establish identical
renderer behavior. The specific internal representation difference remains
unproven. The experiment is reverted, with its patch and frozen app retained
outside the repository.

## Validation protocol

The control is `bd22eed` plus two source-read timing intervals. `Control.app`
is frozen before implementation. Release runs use Xcode 26.6, visionOS 26.5
Simulator and device `8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`. The matched journey
uses five acknowledged captures and two repeated Saved-view restorations with
sunlight changes. Builds, tests, sampling and performance runs are separate.
Fresh launches do not purge filesystem or OS caches.

`Focused.xcresult` records 82 passed tests, zero failures and zero skipped tests
across the source-backed terrain, progressive terrain, Explorer, experience and
globe suites. This includes the new sync/async mesh attribute-equivalence check.
The Xcode request timed out; the independently completed result bundle confirms
the pass. No full-suite pass is claimed.

The final Release build passes. `Final.app/LM` has SHA-256
`f17e5c6b1387799799778a82af77b0ee5bccf35617020d253738119db1564d47`.
Both matched journeys complete all five acknowledged capture stages and both
exact Saved camera/sunlight restorations. The final immersive capture was also
inspected visually.

| Two-cycle journey | Control | Source reads on worker |
| --- | ---: | ---: |
| Source height reads, four-entry total | 58.60 ms on main | 57.68 ms on worker |
| Source albedo reads, four-entry total | 38.48 ms on main | 53.29 ms on worker |
| Selection through completion, worst callback | 233.33 ms | 180.14 ms |
| Same interval, callbacks over 100 ms | 16 | 15 |
| Same interval, logged hitches | 59 | 57 |
| Four base-load intervals, total | 1,643.14 ms | 1,601.76 ms |
| Largest ownership import interval | 220.56 ms | 196.05 ms |
| Largest publication transaction | 0.346 ms | 0.314 ms |
| Final returned footprint | 347.41 MiB | 347.27 MiB |
| First-to-second returned footprint drift | +0.078 MiB | −0.266 MiB |

`post-selection-comparison.json` starts at the selected-stage event and ends at
the passed-stage event for each accepted PID. It includes selection, its hold
and the initial entry gap, even when that gap ends before the source worker
starts. Starting at the base-load marker instead would misleadingly exclude
that gap from the final run. This bounded pair supports removal of roughly
24 ms of main-actor source reading per entry, not elimination of entry hitches
or a statistically established improvement in overall pacing.

Whole-run maxima, including unchanged texture startup, are 451.85 and 267.92 ms;
missed callbacks are 64 and 61 across 58 and 59 windows. Maximum window p95
increases from 22.22 to 25.09 ms while p99 decreases from 138.89 to 120.90 ms.
Frame-window footprint peaks are 479.7 and 347.8 MiB. The final kernel lifetime
peak remains 1,621.03 MiB because the original JPEG XL is still in use.
`control-summary.json` and `final-summary.json` retain all phases and memory
checkpoints. No additional persistent mesh cache or bundled resource is added.

`Final-Apollo` completes the eleven-stop Release ladder with 20-second holds.
All eleven PNGs are byte-identical to item 0. Every final quiet window reports
mean/p95/p99/maximum 16.67 ms and zero misses. The complete ladder still has
startup hitches and does not establish overall pacing acceptance.

| Full ladder, including startup | Item 0 | Final source worker build |
| --- | ---: | ---: |
| Worst callback | 643.77 ms | 666.26 ms |
| Missed callbacks | 82 | 90 |
| Frame-window footprint peak | 406.5 MiB | 369.6 MiB |
| Kernel lifetime footprint peak | Not recorded | 1,604.10 MiB |

`Final-Apollo/baseline-comparison.json`, `performance.tsv`, `profile-runs.tsv`
and `timing.json` retain the accepted hashes and PID-scoped measurements. The
larger startup maximum and miss count remain failures against an overall frame
budget, despite the improved post-selection maximum in the matched journey.

The remaining mesh-conditioning and first-entry hitches stay open. Avoiding
them requires an import strategy that passes the full visual contract, or a
framework improvement. The pending texture companion budget is unchanged.
Physical Vision Pro still needs pacing, memory, thermal, stereo and gesture
validation. No AGC source is changed; both unrelated scheme-user files are
preserved.

Physical-device attempt on 2026-09-06 used source `c82fa12` and an Apple Vision
Pro (RealityDevice14,1), visionOS 27.0 build 24M5359a, paired over the local
network with Developer Mode enabled. Evidence is in
`/tmp/LM-Device-Entry-2026-09-06/`. Xcode 26.6 compiled the Release device
product at `/tmp/LM-Device-Entry-DerivedData/Build/Products/Release-xros/LM.app`,
but signing failed. The build wrapper returned zero despite the unsigned
product; a direct Xcode build confirmed exit 65 at CodeSign. Future device
preflight must check both the build result and `codesign --verify --deep
--strict` before installation.

The device rejected installation with `0xe800801c` (no code signature).
Automatic signing, a direct signing attempt and the Xcode app build all failed
with `errSecInternalComponent`; macOS diagnostics identify
`CSSMERR_CSP_OPERATION_AUTH_DENIED` / `errSecAuthFailed` for the configured
development key. No keychain access controls or signing team were changed.
Resolve keychain authorization on the Mac before asking for another headset
session. The existing installed app has unverified source provenance and was
not used as evidence for these changes.

Xcode 27 beta 6 Instruments recognized the physical device. The attempted
three-minute Time Profiler plus os_log recording disconnected before app
launch and saved `Entry.trace`; it contains no current-build entry/import
validation. No on-device app run, visual acceptance, pacing or memory result
is claimed. Resume with verified signing, installation, then a short targeted
capture. The physical validation requirements above remain open.
