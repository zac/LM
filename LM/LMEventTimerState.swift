/// App-owned reconstruction of the four-digit event timer, driven only by simulation time.
/// Controls: TRW/NASA LM G&C Data Book, revision 2 (1967), p. 4-63.
/// Countdown reversal: Apollo 13 Mission Report MSC-02680 (1970), p. A-2.
/// This later-mission behavior is not an Apollo 11 hardware qualification or a GET source.
struct LMEventTimerState: Equatable, Sendable {
    enum Direction: Equatable, Sendable { case up, down }
    enum SlewPosition: Equatable, Sendable { case tens, units }
    enum Availability: Equatable, Sendable { case live, missingTime, replay }

    struct Context: Equatable, Sendable {
        /// Change this generation for every restart, restored checkpoint, or new session.
        var timelineID: UInt64
        var elapsedSeconds: Double?
        var isPaused: Bool = false
        var isReplay: Bool = false
    }

    enum Command: Equatable, Sendable {
        case start, stop, reset
        case selectDirection(Direction)
        /// Validated coordinator preset; physical setting uses the two slew switches below.
        case set(minutes: Int, seconds: Int)
        /// nil is the spring-return center position; no immediate step on press.
        case minuteSlew(SlewPosition?)
        case secondSlew(SlewPosition?)
    }

    private(set) var availability: Availability = .missingTime
    private(set) var seconds = 0
    private(set) var isRunning = false
    private(set) var selectedDirection: Direction = .up
    /// May differ from the maintained selector after the later timer reverses at zero.
    private(set) var countingDirection: Direction = .up
    private(set) var minuteSlew: SlewPosition?
    private(set) var secondSlew: SlewPosition?
    var displayedSeconds: Int? { availability == .live ? seconds : nil }
    var digits: [Int]? {
        guard availability == .live else { return nil }
        return [seconds / 600, seconds / 60 % 10, seconds / 10 % 6, seconds % 10]
    }

    private var timelineID: UInt64?
    private var lastTime: Double?
    private var wasPaused = false
    private var halfTickFraction = 0.0
    private var nextTickCounts = false

    /// Call with the current frame immediately before dispatching a control command.
    /// Pause rebases the clock; the first resumed sample also rebases, never catching up.
    mutating func update(_ context: Context) {
        let changedTimeline = timelineID != context.timelineID
        timelineID = context.timelineID
        if context.isReplay {
            clearInstrument()
            lastTime = nil
            availability = .replay
            wasPaused = context.isPaused
            return
        }
        guard let time = context.elapsedSeconds, time.isFinite, time >= 0 else {
            clearInstrument()
            lastTime = nil
            availability = .missingTime
            wasPaused = context.isPaused
            return
        }
        let oldTime = lastTime
        let mustReset = changedTimeline || availability != .live || oldTime.map { time < $0 } == true
        if mustReset { clearInstrument() }
        let skipElapsed = mustReset || context.isPaused || wasPaused || oldTime == nil
        lastTime = time
        wasPaused = context.isPaused
        availability = .live
        guard !skipElapsed, let oldTime else { return }
        guard isRunning || minuteSlew != nil || secondSlew != nil else { return }
        let delta = time - oldTime
        let ticks = delta * 2 + halfTickFraction
        guard ticks.isFinite else {
            clearInstrument()
            lastTime = nil
            availability = .missingTime
            return
        }
        let wholeTicks = ticks.rounded(.down)
        halfTickFraction = ticks - wholeTicks
        advance(halfTicks: wholeTicks)
    }

    /// Returns false for unavailable time/replay or an invalid preset, without changing state.
    @discardableResult
    mutating func send(_ command: Command) -> Bool {
        guard availability == .live else { return false }
        switch command {
        case .start:
            isRunning = true
        case .stop:
            isRunning = false
        case .reset:
            seconds = 0
            isRunning = false
            countingDirection = selectedDirection
            minuteSlew = nil
            secondSlew = nil
            resetPhase()
        case .selectDirection(let direction):
            selectedDirection = direction
            countingDirection = direction
        case .set(let minutes, let seconds):
            guard (0...59).contains(minutes), (0...59).contains(seconds) else { return false }
            self.seconds = minutes * 60 + seconds
            countingDirection = selectedDirection
            resetPhase()
        case .minuteSlew(let position):
            if minuteSlew != position { resetPhase() }
            minuteSlew = position
        case .secondSlew(let position):
            if secondSlew != position { resetPhase() }
            secondSlew = position
        }
        return true
    }

    /// Release held switches on scene dismissal, focus loss, or cancelled gestures.
    mutating func cancelSlew() {
        minuteSlew = nil
        secondSlew = nil
        resetPhase()
    }

    private mutating func resetPhase() {
        halfTickFraction = 0
        nextTickCounts = false
    }

    private mutating func clearInstrument() {
        seconds = 0
        isRunning = false
        selectedDirection = .up
        countingDirection = .up
        minuteSlew = nil
        secondSlew = nil
        resetPhase()
    }

    /// A deterministic half-second phase is an application timing convention, not an
    /// electrical oscillator model. Coincident events count first, then slew each digit.
    /// Cycle skipping bounds work even for very large finite elapsed intervals.
    private mutating func advance(halfTicks: Double) {
        guard isRunning || minuteSlew != nil || secondSlew != nil else { return }
        var remaining = halfTicks
        var completed = 0
        var visited: [Int: Int] = [:]
        while remaining >= 1 {
            let key = seconds * 4 + (countingDirection == .up ? 0 : 2) + (nextTickCounts ? 1 : 0)
            if let earlier = visited[key] {
                let cycle = Double(completed - earlier)
                // Subtract modulo the cycle: subtracting individual ticks from a huge
                // Double would otherwise lose the leading, nonperiodic countdown.
                remaining = (halfTicks.truncatingRemainder(dividingBy: cycle)
                    - Double(completed).truncatingRemainder(dividingBy: cycle) + cycle)
                    .truncatingRemainder(dividingBy: cycle)
                visited.removeAll(keepingCapacity: true)
                if remaining < 1 { break }
            }
            visited[key] = completed
            if nextTickCounts && isRunning {
                if countingDirection == .down {
                    if seconds > 0 {
                        seconds -= 1
                        if seconds == 0 { countingDirection = .up }
                    } else {
                        seconds = 1
                        countingDirection = .up
                    }
                } else {
                    seconds = (seconds + 1) % 3600
                }
            }
            if let minuteSlew { slewMinute(minuteSlew) }
            if let secondSlew { slewSecond(secondSlew) }
            nextTickCounts.toggle()
            remaining -= 1
            completed += 1
        }
    }

    private mutating func slewMinute(_ position: SlewPosition) {
        let minutes = seconds / 60
        let replacement = position == .tens
            ? ((minutes / 10 + 1) % 6) * 10 + minutes % 10
            : minutes / 10 * 10 + (minutes % 10 + 1) % 10
        seconds = replacement * 60 + seconds % 60
    }

    private mutating func slewSecond(_ position: SlewPosition) {
        let value = seconds % 60
        let replacement = position == .tens
            ? ((value / 10 + 1) % 6) * 10 + value % 10
            : value / 10 * 10 + (value % 10 + 1) % 10
        seconds = seconds / 60 * 60 + replacement
    }
}
