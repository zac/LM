# Event timer state handoff

`LMEventTimerState` is app-owned event-instrument state. It exposes MM:SS from 00:00 through 59:59, start/stop/reset, maintained count direction, and independently held minute/second TENS/UNITS slew. It consumes supplied simulation time only. It neither changes flight dynamics nor supplies mission elapsed time (GET).

## Source qualification

- TRW Systems prepared the **LM G&C Data Book, revision 2, 15 July 1967** for NASA MSC under NAS 9-4810. The original cover and preface establish that provenance. Printed **4-62–4-63** (PDF pages 89–90, one based) describe 9-S-11 RESET/COUNT, 9-S-12 START/STOP, 9-S-13 MIN SLEW, and 9-S-14 SEC SLEW. Reset clears/stops; START begins timing; STOP freezes it. Count-up wraps at the display limit. Held slew increments individual digits twice per second independently of count direction. This earlier source describes countdown wrapping through zero to 59:59.
- **NASA Apollo 13 Mission Report MSC-02680, September 1970**, Appendix A.2, printed **A-2** (PDF page 139) explicitly identifies a later LM change: countdown reaches zero and then automatically counts upward. This implementation deliberately adopts that later behavior. It is a documented mission hybrid, not Apollo 11 hardware qualification.
- Sources: [1967 Data Book original scan](https://www.ibiblio.org/apollo/Documents/102789076-05-01-acc.pdf), [Apollo 13 report original scan](https://www.ibiblio.org/apollo/Documents/19710003598.pdf). Cover/control pages were visually inspected. The timer component worker owns retained source-page evidence in LMKit.
- Full PDF SHA-256: Data Book `c5ec44b1d94736a9d6db63baa6ea98a30775ffe0a4a6d7b602f689e2c017d5a2`; Apollo 13 report `f6941eaeabf8d611d3da88853923d7e85a8f578c577b02b7e65ba9d92bb54988`.

## Coordinator API and lifecycle

Construct one `LMEventTimerState` per cockpit session. Before each command, and for every displayed frame, call:

```swift
timer.update(.init(timelineID: generation,
                   elapsedSeconds: simulationElapsedSeconds,
                   isPaused: isPaused,
                   isReplay: isReplay))
timer.send(.start) // Bool reports acceptance
```

`Context.timelineID` is a coordinator-owned UInt64 generation. Change it whenever the simulation restarts, a checkpoint is restored, or the session/timeline changes, even if the timestamp does not move backward. A different generation or backward timestamp resets the timer to zero, stopped, UP selected, with slew released. Repeated/equal timestamps do not advance it.

`displayedSeconds: Int?` and `digits: [Int]?` are nil until a valid live time sample arrives, and throughout replay. Bind nil to the asset's unavailable presentation, never a plausible zero. `availability` distinguishes `.live`, `.missingTime`, and `.replay`. `seconds`, `isRunning`, `selectedDirection`, `countingDirection`, `minuteSlew`, and `secondSlew` are read-only externally.

Commands are `.start`, `.stop`, `.reset`, `.selectDirection(.up/.down)`, `.minuteSlew(.tens/.units/nil)`, and `.secondSlew(.tens/.units/nil)`. Nil releases a spring-centered slew switch. State owns the two-digit-per-second repeat; the view must not generate its own repeat pulses. Call `cancelSlew()` on cancelled gestures, focus loss, or dismissal. This releases held switches without stopping a running count. A validated `.set(minutes:seconds:)` is available for coordinator presets; invalid values reject atomically. Physical setting should use the slew switches.

Pause freezes counting and held slew. Paused updates and the first resumed sample rebase the timestamp without catch-up. Preserve state across ordinary pause; the simulation clock need not be started/stopped by timer controls. Stop freezes count phase; held slew can still set digits. START resumes the current effective direction. RESET clears to zero and stops, restores the selected direction, releases slew, and requires another START. Selecting a direction changes the effective direction but does not independently start a stopped timer. Automatic countdown reversal changes `countingDirection` while leaving the maintained `selectedDirection` unchanged; do not animate the selector when the counter reverses.

Entering replay clears/stops/releases the instrument and makes it unavailable. Commands are rejected there. Returning live initializes zero/stopped and requires START; the implementation does not invent recorded timer control history. Missing, negative, nonfinite, or arithmetic-overflow time also clears/stops/blanks; recovery rebases at zero/stopped without catch-up. Finite large gaps are processed with bounded cycle skipping.

## Explicit reconstruction limits

The sources establish display/control functions, not complete electrical edge timing. This app uses a deterministic half-second phase; no immediate slew step occurs on press. Each second counts first, then simultaneous slew updates its digits. Slew affects one digit without carrying into adjacent digits; tens wrap modulo six, units modulo ten. Changes to either held-slew position, preset, reset, or cancellation restart this shared fractional phase. START/STOP preserve effective direction and phase; explicit direction selection changes direction without starting the timer. These are stated app control/phase conventions, not qualification of oscillator phase, switch bounce, power interruptions, internal relay behavior, or post-reversal hardware latch operation. No countdown-zero alarm is invented.

Mission timer remains unavailable until an independent verified preset/epoch is supplied. Runtime boot/descent elapsed time is not GET, and this state must not be reused as a mission timer by adding an arbitrary mission offset.

## Validation and ownership

Only `LM/LMEventTimerState.swift`, `LMTests/LMEventTimerStateTests.swift`, and this handoff are owned by this delivery. No app wiring, scene, AGC, LMCore, project settings, or assets changed.

Native macOS Swift Testing: **12 tests passed**, using Swift 6.3.3 in a temporary SwiftPM module containing the exact source and tests. Tests cover fractional timing, stop/pause, both range boundaries, automatic reversal, no selector motion, reset, replay, backwards/new timelines, unavailable data, invalid presets, independent held digit slew, cancellation, bounded large-gap equivalence to 40,000 individual half ticks, and huge finite offsets. No simulator/headset or app-integration acceptance is claimed.

Reproduce the isolated harness by copying the two Swift files into a temporary package with a target named `LM` and a test target depending on it; use Swift tools version 6.0 or later. Local validation scratch: `/private/tmp/lm-event-timer-validation`. Run `swift test --package-path /private/tmp/lm-event-timer-validation --scratch-path /private/tmp/lm-event-timer-validation/build --disable-sandbox` with `CLANG_MODULE_CACHE_PATH` and `SWIFTPM_MODULECACHE_OVERRIDE` pointed into that scratch directory if the default caches are sandbox-restricted.
