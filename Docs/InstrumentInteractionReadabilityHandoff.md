# Instrument interaction and readability

Worker branch: `cockpit/instrument-interaction-readability`. Source baseline: `acff0aeac62fc3c009831f0234d56205d36011e4`. LMKit: `75bdea77b57e0ae4971bb4ffbee21c4643e3b4cf`. AGC/LMCore: `b3f15533db335ee882dc07401790c93010809e8f`.

Both dependencies are isolated hydrated archives of the exact canonical repository revisions, reached through untracked sibling links. No shared source or branch was changed. All eight LM LFS resources were hydrated from verified SHA-256 local objects. The worktree was clean before implementation. Historical InstrumentVisual evidence retains its original c75d379 dependency label; it is not relabeled as this run.

## Changes

- `LMInstrumentInteraction.completedTap` is the production completion boundary used by `SpatialTapGesture.onEnded`. It resolves the actual entity identity using the station's existing ancestor lookup, animates the existing key and calls the existing session FIFO exactly once. It does not handle hover, generate synthetic pinches or change PRO pulse semantics.
- DSKY native PBR keycap materials retain authored base colors and receive a modest emissive floor and increased roughness. Dark legend ink remains dark. Unpowered lamp lenses receive a smaller floor; live on colors and off-state restoration remain independent. This is an appearance choice, not historical photometry, simulated electrical backlighting or bloom.
- FDAI fixed surround/mask/bezel use matte PBR treatment. The ball texture, its orientation mapping, glass, fixed transforms and hidden unsupported needles are preserved.
- Opt-in DEBUG trace records actual inverse observer transforms and completed spatial callbacks separately from programmatic input. New capture manifests record source/dependency provenance, simulator ID and both launcher and Debug implementation hashes. Observation-only capture mode does not inject keys.

## Validation ledger

Dedicated simulator: `31D2A5CF-B052-42BC-86B3-590CABDDDA49`, LM Interaction 3d13, Apple Vision Pro 4K, visionOS 26.5 (23O470). Xcode 26.6 (17F113), visionOS 26.5 SDK. XCTest may create its own isolated clone; its ID is recorded with final results.

- Original baseline generic visionOS simulator build: passed.
- Original baseline P64/V16N36/PRO/V35/RSET captures: completed under `Docs/Validation/InstrumentInteraction/before/`. All successful inputs here are programmatic session FIFO events.
- Physical Vision Pro `00008112-000A41DC1A78A01E`: reported unavailable. No device test performed or settings changed.
- AXe accessibility translation: failed with the exact error retained under `native/`.
- Native Simulator interaction-mode click: first attempt did not produce a `Physical DSKY key` log. Not acceptance.
- Concurrent visionOS XCTest clones caused runtime contention and simulator shutdowns. Workers coordinated serial simulator validation; no other worker's processes were stopped by this task.
- Final source: `f1f612ed6e4440fb8977c0776b3cc335ee7791e9`. Final serial simulator build/test: **12 passed, 0 failed, 0 skipped**, confirmed by xcresulttool (`tests.json`). Initial test failure (11/1) caught duplicate cosmetic FDAI transform/mesh names and was fixed without weakening semantic identity contracts. `readabilitySurfaceCount == 3` now verifies the intended native surfaces.
- Final programmatic capture process 143: P64, V16N36E, PRO return, V35 lamp test and RSET. See before/after images and adjacent state in the evidence report.
- Final native observation process 1532: 164 trace samples, zero completed spatial callbacks. Native interaction-mode clicks near VERB with pointer capture off/on did not complete key selection. AXe cannot obtain a visionOS translation. This tool path therefore did not establish OS gesture acceptance; no general claim that Simulator cannot support pinch is made.
- Tests call the actual production completion adapter with actual imported entities, reach the FIFO, preserve VERB/NOUN/digit/ENTR and adjacent 7/8 ordering, reject impostors, and release repeated PRO pulses. The real Luminary session test reaches V16N36 then V06N64 after PRO. Existing ten regression tests remain passing, including active-PRO cancellation and queue teardown.
- Test runner's initial clone was `4B88E6CA-D195-46B5-8CFA-18B43B426005`; final serial run used dedicated simulator directly. All this worker's runtime commands finished and dedicated simulator was shut down before releasing the slot to assembly. No other simulator was shut down.
- Full LM suite, Release build, hardware, stereo and frame-time checks were not run.

## Scope and remaining gates

No station placement, mounting geometry, calibration, cabin assembly, PoweredDescentSession, FIFO implementation, terrain or LMKit source asset was edited. Any lighting change remains a coordinator/assembly proposal. No enlargement of physical geometry or overlapping key targets is introduced.

Photometry, actual headset gaze/pinch, stereo, ergonomic reach and frame-time qualification remain separate gates. The screenshots are adjacent to runtime samples, not atomic frame/state pairs. A synthetic adapter test is not proof of OS gesture recognition.


## Reproduce and coordinator handoff

See [evidence and exact observer transform](Validation/InstrumentInteraction/README.md), [commands](Validation/InstrumentInteraction/commands.txt), and [headset checklist](Validation/InstrumentInteraction/HeadsetChecklist.md). No mount or assembly patch is requested. Cabin lighting remains a future coordinator-owned investigation: small fine print and bright FDAI ball-edge areas persist despite improved keycap contrast and matte fixed housing treatment. Do not infer lamp photometry or all-reflection removal from this pass.

Memory note: older PDI-relative FDAI guidance conflicts with the current integration handoff. The current site-local stable-frame mapping was preserved; no historical reset recommendation was applied.
