import Testing
@testable import LM

struct LMEventTimerStateTests {
    private func context(_ time: Double?, timeline: UInt64 = 1,
                         paused: Bool = false, replay: Bool = false) -> LMEventTimerState.Context {
        .init(timelineID: timeline, elapsedSeconds: time, isPaused: paused, isReplay: replay)
    }

    @Test func unavailableUntilValidTimeAndInvalidPresetsAreAtomic() {
        var timer = LMEventTimerState()
        #expect(timer.displayedSeconds == nil)
        let startAccepted = timer.send(.start)
        #expect(!startAccepted)
        timer.update(context(100))
        #expect(timer.displayedSeconds == 0 && !timer.isRunning)
        timer.send(.set(minutes: 12, seconds: 34))
        #expect(timer.digits == [1, 2, 3, 4])
        let before = timer
        for pair in [(-1, 0), (60, 0), (0, -1), (0, 60), (Int.max, Int.max)] {
            let accepted = timer.send(.set(minutes: pair.0, seconds: pair.1))
            #expect(!accepted)
            #expect(timer == before)
        }
    }

    @Test func fractionalCountPauseAndStopNeverCatchUp() {
        var timer = LMEventTimerState()
        timer.update(context(0))
        timer.send(.start)
        timer.update(context(0.75))
        #expect(timer.seconds == 0)
        timer.update(context(1.25))
        #expect(timer.seconds == 1)
        timer.update(context(10, paused: true))
        timer.update(context(20, paused: true))
        timer.update(context(30))
        #expect(timer.seconds == 1)
        timer.update(context(30.75))
        #expect(timer.seconds == 2)
        timer.send(.stop)
        timer.update(context(100))
        #expect(timer.seconds == 2)
        timer.send(.start)
        timer.update(context(101))
        #expect(timer.seconds == 3)
    }

    @Test func upWrapsAndLaterCountdownReversesAtZeroWithoutMovingSelector() {
        var timer = LMEventTimerState()
        timer.update(context(0))
        timer.send(.set(minutes: 59, seconds: 59))
        timer.send(.start)
        timer.update(context(1))
        #expect(timer.seconds == 0)
        timer.send(.selectDirection(.down))
        timer.send(.set(minutes: 0, seconds: 2))
        timer.update(context(2))
        #expect(timer.seconds == 1 && timer.countingDirection == .down)
        timer.update(context(3))
        #expect(timer.seconds == 0 && timer.countingDirection == .up)
        #expect(timer.selectedDirection == .down)
        timer.update(context(4))
        #expect(timer.seconds == 1)
        timer.send(.stop)
        timer.update(context(10))
        timer.send(.start)
        timer.update(context(11))
        #expect(timer.seconds == 2 && timer.countingDirection == .up)
    }

    @Test func zeroCountdownStartsUpAndResetHoldsUntilStart() {
        var timer = LMEventTimerState()
        timer.update(context(0))
        timer.send(.selectDirection(.down))
        timer.send(.start)
        timer.update(context(1))
        #expect(timer.seconds == 1 && timer.countingDirection == .up)
        timer.send(.reset)
        timer.update(context(10))
        #expect(timer.seconds == 0 && !timer.isRunning)
        #expect(timer.selectedDirection == .down)
        timer.send(.start)
        timer.update(context(11))
        #expect(timer.seconds == 1)
    }

    @Test func replayHasNoInventedHistoryAndReturningLiveRequiresStart() {
        var timer = LMEventTimerState()
        timer.update(context(0))
        timer.send(.start)
        timer.update(context(5))
        timer.update(context(2, replay: true))
        #expect(timer.availability == .replay && timer.digits == nil)
        let presetAccepted = timer.send(.set(minutes: 10, seconds: 0))
        #expect(!presetAccepted)
        let startAccepted = timer.send(.start)
        #expect(!startAccepted)
        timer.update(context(100))
        #expect(timer.seconds == 0 && !timer.isRunning)
        timer.update(context(110))
        #expect(timer.seconds == 0)
    }

    @Test func backwardTimeOrNewTimelineResetsIncludingHeldControls() {
        var timer = LMEventTimerState()
        timer.update(context(10))
        timer.send(.start)
        timer.send(.minuteSlew(.tens))
        timer.update(context(11))
        timer.update(context(9))
        #expect(timer.seconds == 0 && !timer.isRunning && timer.minuteSlew == nil)
        timer.send(.start)
        timer.update(context(20, timeline: 2))
        #expect(timer.seconds == 0 && !timer.isRunning)
    }

    @Test func invalidTimeBlanksAndStopsWithoutRecoveryCatchUp() {
        for value: Double? in [nil, .nan, .infinity, -.infinity, -1] {
            var timer = LMEventTimerState()
            timer.update(context(0))
            timer.send(.start)
            timer.update(context(5))
            timer.update(context(value))
            #expect(timer.displayedSeconds == nil && !timer.isRunning)
            timer.update(context(100))
            #expect(timer.displayedSeconds == 0 && !timer.isRunning)
        }
    }

    @Test func heldSlewIsTwoHertzIndependentIncreasingDigitsWithNoCarry() {
        var timer = LMEventTimerState()
        timer.update(context(0))
        timer.send(.set(minutes: 59, seconds: 59))
        timer.send(.selectDirection(.down))
        timer.send(.minuteSlew(.units))
        timer.send(.secondSlew(.tens))
        timer.update(context(0.49))
        #expect(timer.seconds == 3599)
        timer.update(context(0.5))
        #expect(timer.digits == [5, 0, 0, 9])
        timer.update(context(1))
        #expect(timer.digits == [5, 1, 1, 9])
        timer.send(.minuteSlew(nil))
        timer.send(.secondSlew(nil))
        timer.update(context(10))
        #expect(timer.digits == [5, 1, 1, 9])
    }

    @Test func pauseAndCancellationFreezeHeldSlew() {
        var timer = LMEventTimerState()
        timer.update(context(0))
        timer.send(.minuteSlew(.tens))
        timer.update(context(0.5))
        #expect(timer.seconds == 600)
        timer.update(context(10, paused: true))
        timer.update(context(20))
        #expect(timer.seconds == 600)
        timer.update(context(20.5))
        #expect(timer.seconds == 1200)
        timer.cancelSlew()
        timer.update(context(30))
        #expect(timer.seconds == 1200 && timer.minuteSlew == nil)
    }

    @Test func largeJumpsAreBoundedAndAgreeWithSmallStepsIncludingSlew() {
        var fast = LMEventTimerState()
        fast.update(context(0))
        fast.send(.set(minutes: 12, seconds: 34))
        fast.send(.selectDirection(.down))
        fast.send(.start)
        fast.send(.minuteSlew(.units))
        fast.send(.secondSlew(.tens))
        var slow = fast
        fast.update(context(20000.25))
        for halfTick in 1...40000 { slow.update(context(Double(halfTick) / 2)) }
        slow.update(context(20000.25))
        #expect(fast == slow)
        fast.update(context(1e100))
        #expect(fast.availability == .live && (0...3599).contains(fast.seconds))
        fast.update(context(.greatestFiniteMagnitude))
        #expect(fast.availability == .missingTime && !fast.isRunning)
    }
    @Test func enormousIntervalPreservesCountdownOffsetModuloTheDisplayRange() {
        var timer = LMEventTimerState()
        timer.update(context(0))
        timer.send(.set(minutes: 0, seconds: 10))
        timer.send(.selectDirection(.down))
        timer.send(.start)
        let time = 1e100
        timer.update(context(time))
        let expected = (Int(time.truncatingRemainder(dividingBy: 3600)) - 10 + 3600) % 3600
        #expect(timer.seconds == expected && timer.countingDirection == .up)
    }

    @Test func stoppedFractionalPhaseIsPreservedWithoutIdleTimeLeakingIntoStart() {
        var timer = LMEventTimerState()
        timer.update(context(0))
        timer.send(.start)
        timer.update(context(0.75))
        timer.send(.stop)
        timer.update(context(100.1))
        timer.send(.start)
        timer.update(context(100.225))
        #expect(timer.seconds == 0)
        timer.update(context(100.475))
        #expect(timer.seconds == 1)
    }

}
