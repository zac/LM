import Foundation
import Darwin
import QuartzCore
import AGC
import LMCore

@MainActor
@Observable
final class PoweredDescentSession {
    /// Where a live run begins. `.ignition` boots Luminary fresh and flies the
    /// automatic P63 approach; checkpoint starts restore the real AGC, vehicle,
    /// radar, and crew-control state at a validated program/display boundary.
    enum StartPoint: Equatable {
        case ignition
        case p64Approach
        case p65TerminalDescent

        /// Apollo cockpit defaults to the validated late-descent checkpoint.
        /// The longer P64 approach remains available through an explicit launch option.
        static func cockpitLaunch(arguments: [String]) -> Self {
            arguments.contains("--cockpit-start-p64") ? .p64Approach : .p65TerminalDescent
        }

        var programLabel: String {
            switch self {
            case .ignition: "P63"
            case .p64Approach: "P64"
            case .p65TerminalDescent: "P65"
            }
        }
    }

    enum RODSwitchPosition: Equatable {
        case descendPlus
        case neutral
        case descendMinus
    }

    enum Status: Equatable {
        case unloaded
        case idle
        case running
        case replaying
        case stopped
        case error(String)
    }

    /// Nominal full-scale ACA deflection is 42 counter increments at 10°.
    static let rhcDeflection = 42

    private(set) var status: Status = .unloaded
    private(set) var isRunning = false
    @ObservationIgnored private(set) var eventTimer = LMEventTimerState()
    private(set) var eventTimerTimeline: UInt64 = 0
    private(set) var eventTimerInteractionGeneration: UInt64 = 0

    func synchronizeEventTimer() {
        eventTimer.update(.init(timelineID: eventTimerTimeline, elapsedSeconds: snapshot?.timeSeconds,
            isPaused: isPaused || !isRunning, isReplay: replayFrame != nil))
    }
    @discardableResult
    func sendEventTimer(_ command: LMEventTimerState.Command, generation: UInt64) -> Bool {
        guard generation == eventTimerInteractionGeneration, isRunning, !isPaused,
              isSceneActive, replayFrame == nil else { return false }
        synchronizeEventTimer()
        return eventTimer.send(command)
    }
    func releaseEventTimerControls() {
        eventTimer.cancelSlew()
        eventTimerInteractionGeneration &+= 1
    }

    private(set) var isPaused = false
    private(set) var snapshot: LMSimulationSnapshot?
    private(set) var replayFrame: LMFlightReplayFrame?
    private(set) var recording: LMFlightRecording?
    private(set) var loadMessage = "Luminary 099 not loaded"
    private(set) var scenario = LMPoweredDescentScenario.apollo11SourceBacked

    func selectLandingSite(_ site: LMLunarLandingSite?) {
        terrainBindingID = UUID()
        scenario = site.map(LMPoweredDescentScenario.lunarSite) ?? .apollo11SourceBacked
        landingSurface = nil
        terrainReady = nil
        vehicleDidAdvance = nil
        terrainCaptureMetrics = nil
        lastCaptureSecond = -1
        loadProgram()
    }

    var attitudeMode = LMPoweredDescentAttitudeMode.automatic
    var rhcPitch = 0
    var rhcYaw = 0
    var rhcRoll = 0
    /// A direct gesture holds this generation until release. Late samples from
    /// a stopped/deactivated/released interaction can never reacquire control.
    func beginACAInteraction() -> UUID? {
        guard isRunning, !isPaused, isSceneActive else { return nil }
        return acaInteractionGeneration
    }

    @discardableResult
    func updateACAInteraction(_ input: LMACANormalizedInput, generation: UUID) -> Bool {
        guard generation == acaInteractionGeneration, isRunning, !isPaused, isSceneActive else { return false }
        setACA(pitch: input.pitch, yaw: input.yaw, roll: input.roll)
        return true
    }

    /// Continuous analog ACA axes (-1…1). Buttons add discrete ±42-count
    /// commands on top; the combined deflection clamps at ±57 counts.
    var aca = LMACANormalizedInput.neutral
    private var acaInteractionGeneration = UUID()
    private(set) var rodSwitchPosition = RODSwitchPosition.neutral
    private var rodInteractionGeneration = UUID()

    /// Physical momentary input uses a generation so a late drag sample cannot
    /// reassert DES RATE after pause, release, stop, or scene deactivation.
    func beginRODInteraction() -> UUID? {
        guard isRunning, !isPaused, isSceneActive, replayFrame == nil else { return nil }
        return rodInteractionGeneration
    }

    @discardableResult
    func updateRODInteraction(_ position: RODSwitchPosition, generation: UUID) -> Bool {
        guard generation == rodInteractionGeneration, isRunning, !isPaused,
              isSceneActive, replayFrame == nil else { return false }
        setROD(.descendPlus, held: position == .descendPlus)
        setROD(.descendMinus, held: position == .descendMinus)
        return true
    }

    func releaseRODInteraction() {
        rodInteractionGeneration = UUID()
        rodSwitchPosition = .neutral
    }

    @discardableResult
    func selectPhysicalAttitudeMode(_ mode: LMPoweredDescentAttitudeMode) -> Bool {
        guard isRunning, !isPaused, isSceneActive, replayFrame == nil else { return false }
        attitudeMode = mode
        return true
    }


    let terrainSimulationGate = LMTerrainSimulationGate()
    @ObservationIgnored var terrainReady: (() -> Bool)?
    @ObservationIgnored var vehicleDidAdvance: ((LMVehicleStateSnapshot) -> Void)?
    @ObservationIgnored var terrainCaptureMetrics: (() -> [String: Double])?
    @ObservationIgnored private var captureExport: Task<Void, Never>?
    @ObservationIgnored private var lastCaptureSecond = -1
    @ObservationIgnored private var captureStartSimulationSeconds: Double?
    @ObservationIgnored private var captureStartWallSeconds: Double?
    @ObservationIgnored private var terrainWaitSeconds = 0.0
    @ObservationIgnored private var publicationWaitSeconds = 0.0
    @ObservationIgnored private var maximumPublicationWaitSeconds = 0.0
    @ObservationIgnored private var realtimeClampedSeconds = 0.0
    @ObservationIgnored private var terrainBindingID = UUID()

    func contactPublisher() -> (LMTerrainContactSurface) -> Void {
        let binding = terrainBindingID
        return { [weak self] surface in
            guard let self, self.terrainBindingID == binding else { return }
            self.landingSurface = surface
        }
    }
    @ObservationIgnored private var landingSurface: (any LMLandingSurfaceModel)?
    @ObservationIgnored private var runtime: LMSimulationRuntime?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var replayTask: Task<Void, Never>?
    @ObservationIgnored private var dskyTask: Task<Void, Never>?
    @ObservationIgnored private let dskyInputQueue = LMDSKYInputQueue()
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var recordedFrames: [LMFlightFrame] = []
    @ObservationIgnored private var runID = UUID()
    @ObservationIgnored private var isSceneActive = true
    @ObservationIgnored private var p64Checkpoint: LMSimulationCheckpoint?
    @ObservationIgnored private var p65Checkpoint: LMSimulationCheckpoint?
    @ObservationIgnored private var lastStartPoint: StartPoint = .ignition

    var dsky: DSKYSnapshot? { snapshot?.agc.dsky }
    var programNumber: Int? { replayFrame?.programNumber ?? dsky?.programNumber }
    var vehicleState: LMVehicleStateSnapshot? { replayFrame?.vehicleState ?? snapshot?.vehicleState }
    var vehicleCommands: LMVehicleSnapshot? { replayFrame?.vehicleCommands ?? snapshot?.vehicleCommands }
    var isLandingPointDisplayActive: Bool {
        replayFrame == nil
            && programNumber == 64
            && dsky?.verb == "06"
            && dsky?.noun == "64"
    }
    var isLandingPointRedesignationEnabled: Bool {
        isLandingPointDisplayActive
            && dsky?.verbNounFlash == false
            && (landingPointRedesignationTimeRemainingSeconds ?? 0) > 0
    }
    /// Luminary's FUNNYDSP packs TREDES and LOOKANGL into N64 register 1 as
    /// `TT AA`: two time digits, a deliberately blank center position, and two
    /// integer landing-point-designator angle digits.
    var landingPointLookAngleDegrees: Int? {
        guard isLandingPointDisplayActive,
              let digits = dsky?.r1.filter(\.isNumber), digits.count == 4 else {
            return nil
        }
        return Int(digits.suffix(2))
    }

    var landingPointRedesignationTimeRemainingSeconds: Int? {
        guard isLandingPointDisplayActive,
              let digits = dsky?.r1.filter(\.isNumber), digits.count == 4 else {
            return nil
        }
        return Int(digits.prefix(2))
    }
    var radarAltitudeMeters: Double? {
        guard replayFrame == nil,
              case .measurement(let measurement)? = snapshot?.sensorState.radarInput else {
            return nil
        }
        return measurement.altitudeMeters
    }

    /// Install the terrain the landing gear touches. The cockpit scene calls
    /// this whenever clipmap residency changes, so the physics surface is always
    /// the surface currently being drawn.
    func setLandingSurface(_ surface: (any LMLandingSurfaceModel)?) {
        landingSurface = surface
    }

    var canStart: Bool { runtime != nil && !isRunning && replayTask == nil }
    var canStop: Bool { isRunning || replayTask != nil }
    var canPause: Bool { isRunning || replayTask != nil }
    var canReset: Bool { runtime != nil }
    var canReplay: Bool { recording?.frames.isEmpty == false && !isRunning && replayTask == nil }

    init() {
        loadProgram()
    }

    nonisolated static func bundledP66Recording(
        in bundle: Bundle = .main
    ) throws -> LMFlightRecording {
        guard let url = bundle.url(forResource: "P66TerminalDescent", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try LMFlightRecording.decode(Data(contentsOf: url))
    }

    nonisolated static func bundledAutomaticRecording(
        in bundle: Bundle = .main
    ) throws -> LMFlightRecording {
        guard let url = bundle.url(
            forResource: "P65AutomaticTerminalDescent",
            withExtension: "json"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try LMFlightRecording.decode(Data(contentsOf: url))
    }

    /// Decode and fully validate a bundled powered-descent checkpoint against
    /// the bundled Luminary099.bin and scenario identity.
    nonisolated private static func bundledCheckpoint(
        named resource: String,
        in bundle: Bundle
    ) throws -> LMSimulationCheckpoint {
        guard let checkpointURL = bundle.url(forResource: resource, withExtension: "bplist") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let checkpoint = try LMSimulationCheckpoint.decodeFixture(Data(contentsOf: checkpointURL))
        guard let binURL = bundle.url(forResource: "Luminary099", withExtension: "bin") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try checkpoint.validate(
            coreImageSHA256: AGCRuntimeCheckpoint.coreImageSHA256(of: Data(contentsOf: binURL)),
            scenarioID: LMPoweredDescentScenario.apollo11SourceBacked.id
        )
        return checkpoint
    }

    nonisolated static func bundledP64Checkpoint(
        in bundle: Bundle = .main
    ) throws -> LMSimulationCheckpoint {
        try bundledCheckpoint(named: "P64ApproachCheckpoint", in: bundle)
    }

    nonisolated static func bundledP65Checkpoint(
        in bundle: Bundle = .main
    ) throws -> LMSimulationCheckpoint {
        try bundledCheckpoint(named: "P65TerminalDescentCheckpoint", in: bundle)
    }

    func loadProgram() {
        stop()
        recording = nil
        replayFrame = nil
        recordedFrames.removeAll()
        guard let url = Bundle.main.url(forResource: "Luminary099", withExtension: "bin") else {
            runtime = nil
            snapshot = nil
            status = .error("Bundled Luminary099.bin is missing.")
            loadMessage = "Luminary099.bin is missing from the app bundle."
            return
        }
        do {
            let loaded = try LMSimulationRuntime(binFile: url, scenario: scenario)
            runtime = loaded
            do {
                p64Checkpoint = try Self.bundledP64Checkpoint()
            } catch {
                p64Checkpoint = nil
                loadMessage = "P64 checkpoint unavailable: \(error.localizedDescription)"
            }
            do {
                p65Checkpoint = try Self.bundledP65Checkpoint()
            } catch {
                p65Checkpoint = nil
                loadMessage = "P65 checkpoint unavailable: \(error.localizedDescription)"
            }
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--replay-automatic") {
                recording = try? Self.bundledAutomaticRecording()
            } else if arguments.contains("--replay-p66") {
                recording = try? Self.bundledP66Recording()
            } else {
                recording = try? Self.bundledP66Recording()
            }
            if scenario.initialState.landingSite != nil {
                p64Checkpoint = nil
                p65Checkpoint = nil
                recording = nil
            }
            loadMessage = "Luminary 099 · \(scenario.title)"
            status = .idle
            snapshotTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let snap = await loaded.snapshot()
                guard !Task.isCancelled else { return }
                self.snapshot = snap
                self.synchronizeEventTimer()
                self.snapshotTask = nil
            }
        } catch {
            runtime = nil
            snapshot = nil
            status = .error(error.localizedDescription)
            loadMessage = error.localizedDescription
        }
    }

    func start() {
        start(from: .ignition)
    }

    /// Begin a live run. `.ignition` boots Luminary and flies P63; checkpoint
    /// starts restore directly into the running runtime with no replay frames.
    func start(from startPoint: StartPoint) {
        guard canStart, let runtime else { return }
        let checkpoint: LMSimulationCheckpoint?
        switch startPoint {
        case .ignition:
            checkpoint = nil
        case .p64Approach:
            checkpoint = p64Checkpoint
        case .p65TerminalDescent:
            checkpoint = p65Checkpoint
        }
        if startPoint != .ignition && checkpoint == nil {
            status = .error("The \(startPoint.programLabel) checkpoint is unavailable.")
            return
        }
        loopTask?.cancel()
        snapshotTask?.cancel()
        snapshotTask = nil
        lastCaptureSecond = -1
        terrainWaitSeconds = 0
        publicationWaitSeconds = 0
        maximumPublicationWaitSeconds = 0
        realtimeClampedSeconds = 0
        eventTimerTimeline &+= 1
        releaseEventTimerControls()
        let runID = UUID()
        self.runID = runID
        captureStartSimulationSeconds = nil
        captureStartWallSeconds = nil
        lastStartPoint = startPoint
        replayFrame = nil
        recordedFrames.removeAll(keepingCapacity: true)
        isPaused = false
        isRunning = true
        status = .running
        loopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if startPoint != .ignition {
                guard let checkpoint else {
                    self.status = .error("The \(startPoint.programLabel) checkpoint is unavailable.")
                    self.isRunning = false
                    return
                }
                do {
                    let restored = try await runtime.restore(from: checkpoint)
                    guard self.runID == runID else { return }
                    self.snapshot = restored
                    self.synchronizeEventTimer()
                    self.record(restored)
                    self.loadMessage = "Live · restored \(startPoint.programLabel) at "
                        + Self.altitudeText(restored.vehicleState.altitudeMeters)
                } catch {
                    guard self.runID == runID else { return }
                    self.isRunning = false
                    self.loopTask = nil
                    self.status = .error(error.localizedDescription)
                    return
                }
            } else {
                self.loadMessage = "Auto-land · booting Luminary 099…"
                do {
                    // Ignition always starts a fresh flight. Serialize reset
                    // and boot with any cancelled run's outstanding step.
                    let prepared = try await self.terrainSimulationGate.withAccess {
                        try Task.checkCancellation()
                        _ = try await runtime.reset()
                        try Task.checkCancellation()
                        await runtime.setLandingSurface(self.landingSurface)
                        return await runtime.bootAndEnterP63()
                    }
                    guard !Task.isCancelled, self.runID == runID else { return }
                    self.snapshot = prepared
                    self.synchronizeEventTimer()
                    self.record(prepared)
                    self.loadMessage = self.autoLandMessage(program: prepared.agc.dsky.programNumber, accelerated: true)
                } catch {
                    guard self.runID == runID else { return }
                    self.isRunning = false
                    self.loopTask = nil
                    self.status = .error(error.localizedDescription)
                    return
                }
            }
            var last = CACurrentMediaTime()
            while !Task.isCancelled, self.runID == runID {
                if !self.isSceneActive || self.isPaused {
                    try? await Task.sleep(for: .milliseconds(100))
                    last = CACurrentMediaTime()
                    continue
                }
                if self.terrainReady?() == false {
                    let waitStart = CACurrentMediaTime()
                    try? await Task.sleep(for: .milliseconds(100))
                    last = CACurrentMediaTime()
                    self.terrainWaitSeconds += last - waitStart
                    continue
                }
                let now = CACurrentMediaTime()
                let wallDelta = now - last
                last = now
                let pace = LMSimulationPace.pace(programNumber: self.snapshot?.agc.dsky.programNumber)
                let delta = pace.simulationDelta(wallDelta: wallDelta)
                if pace == .realtime {
                    self.realtimeClampedSeconds += max(0, wallDelta - delta)
                }
                let publicationWaitStart = CACurrentMediaTime()
                let result = await self.terrainSimulationGate.withAccess { () -> LMSimulationSnapshot? in
                    let wait = CACurrentMediaTime() - publicationWaitStart
                    self.publicationWaitSeconds += wait
                    self.maximumPublicationWaitSeconds = max(self.maximumPublicationWaitSeconds, wait)
                    guard !Task.isCancelled, self.runID == runID else { return nil }
                    // Publication may have changed coverage while this step
                    // waited for the gate. Check the installed generation again.
                    guard self.terrainReady?() != false else { return nil }
                    await runtime.setLandingSurface(self.landingSurface)
                    return await runtime.step(deltaTime: delta, input: self.makeFrameInput())
                }
                guard self.runID == runID else { return }
                guard let snap = result else { continue }
                self.snapshot = snap
                self.synchronizeEventTimer()
                self.vehicleDidAdvance?(snap.vehicleState)
                self.record(snap)
                if snap.vehicleState.flightOutcome.isTerminal {
                    break
                }
                if pace == .accelerated {
                    self.loadMessage = self.autoLandMessage(program: snap.agc.dsky.programNumber, accelerated: true)
                    try? await Task.sleep(for: .milliseconds(2))
                    continue
                }
                self.loadMessage = self.autoLandMessage(program: snap.agc.dsky.programNumber, accelerated: false)
                let elapsed = CACurrentMediaTime() - now
                let remaining = LMSimulationPace.realtimeTargetFrameSeconds - elapsed
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                } else {
                    await Task.yield()
                }
            }
            guard self.runID == runID else { return }
            self.isRunning = false
            self.loopTask = nil
            self.finishRecording()
            if self.status == .running {
                self.status = .stopped
            }
        }
    }

    func stop() {
        eventTimerTimeline &+= 1
        releaseEventTimerControls()
        captureExport?.cancel()
        captureExport = nil
        runID = UUID()
        loopTask?.cancel()
        loopTask = nil
        replayTask?.cancel()
        replayTask = nil
        dskyTask?.cancel()
        dskyTask = nil
        dskyInputQueue.cancelPendingAndRelease()
        snapshotTask?.cancel()
        snapshotTask = nil
        replayFrame = nil
        isPaused = false
        releaseCrewControls()
        if isRunning {
            finishRecording()
        }
        isRunning = false
        switch status {
        case .unloaded, .error:
            break
        default:
            if runtime != nil {
                status = .stopped
            }
        }
    }

    func reset() {
        guard let runtime else { return }
        stop()
        attitudeMode = .automatic
        snapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await runtime.reset()
                guard !Task.isCancelled else { return }
                self.snapshot = snapshot
                self.synchronizeEventTimer()
                self.status = .idle
            } catch {
                guard !Task.isCancelled else { return }
                self.status = .error(error.localizedDescription)
            }
            self.snapshotTask = nil
        }
    }

    /// Rapid restart: cancel the live run and re-establish the last start point.
    /// A checkpoint start re-restores in well under a second — no boot cycle.
    func restart() {
        stop()
        start(from: lastStartPoint)
    }

    func pause() {
        guard canPause else { return }
        synchronizeEventTimer()
        isPaused = true
        releaseEventTimerControls()
        releaseCrewControls()
    }

    func resume() {
        guard canPause else { return }
        isPaused = false
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    func sendDSKYKey(_ key: DSKYKeyCode) {
        guard let runtime else { return }
        dskyTask?.cancel()
        dskyTask = nil
        enqueueDSKYKey(key, runtime: runtime)
    }

    private func enqueueDSKYKey(_ key: DSKYKeyCode, runtime: LMSimulationRuntime) {
        dskyInputQueue.enqueue(
            key,
            sendKey: { await runtime.sendDSKYKey($0) },
            sendPRO: { await runtime.sendPRO(pressed: $0) },
            didSend: { [weak self] in
                guard let self, !self.isRunning else { return }
                let snap = await runtime.snapshot()
                guard !Task.isCancelled else { return }
                self.snapshot = snap
                self.synchronizeEventTimer()
            }
        )
    }

    func sendDSKYScript(_ script: DSKYScript) {
        guard let runtime else { return }
        dskyTask?.cancel()
        dskyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.dskyInputQueue.waitUntilIdle()
            for key in script.keys {
                if Task.isCancelled { break }
                self.enqueueDSKYKey(key, runtime: runtime)
                await self.dskyInputQueue.waitUntilIdle()
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .milliseconds(180))
            }
            guard !Task.isCancelled else { return }
            self.dskyTask = nil
        }
    }

    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        if !active {
            releaseCrewControls()
        }
    }

    /// Neutralize every momentary crew input. This is the fail-safe path for
    /// gesture cancellation, scene deactivation, tracking interruption, and stop.
    func releaseCrewControls() {
        releaseEventTimerControls()
        rhcPitch = 0
        rhcYaw = 0
        rhcRoll = 0
        releaseACA()
        releaseRODInteraction()
    }

    func setROD(_ position: RODSwitchPosition, held: Bool) {
        if held {
            rodSwitchPosition = position
        } else if rodSwitchPosition == position {
            rodSwitchPosition = .neutral
        }
    }

    func setRHC(pitch: Bool? = nil, yaw: Bool? = nil, roll: Bool? = nil) {
        if let pitch {
            rhcPitch = pitch ? Self.rhcDeflection : 0
        }
        if let yaw {
            rhcYaw = yaw ? Self.rhcDeflection : 0
        }
        if let roll {
            rhcRoll = roll ? Self.rhcDeflection : 0
        }
    }

    /// Continuous analog ACA axes, clamped to -1…1 per axis.
    func setACA(pitch: Double? = nil, yaw: Double? = nil, roll: Double? = nil) {
        if let pitch {
            aca.pitch = LMACANormalizedInput.clamp(pitch)
        }
        if let yaw {
            aca.yaw = LMACANormalizedInput.clamp(yaw)
        }
        if let roll {
            aca.roll = LMACANormalizedInput.clamp(roll)
        }
    }

    /// Handle released or hand tracking lost: every axis returns to neutral
    /// before the next simulation frame is built.
    func releaseACA() {
        acaInteractionGeneration = UUID()
        aca = .neutral
    }

    /// Combined RHC counts fed to the AGC this frame: discrete button commands
    /// plus mapped analog deflection, clamped at the ±57-count mechanical stops.
    var effectiveRHCPitch: Int {
        LMACAInputMapper().combined(buttonCounts: rhcPitch, normalizedAxis: aca.pitch)
    }

    var effectiveRHCYaw: Int {
        LMACAInputMapper().combined(buttonCounts: rhcYaw, normalizedAxis: aca.yaw)
    }

    var effectiveRHCRoll: Int {
        LMACAInputMapper().combined(buttonCounts: rhcRoll, normalizedAxis: aca.roll)
    }

    /// AGC channel words for the effective ACA deflection. The computer uses
    /// 15-bit ones'-complement, so negative Swift integers must be encoded
    /// rather than truncated directly into channel 0166-0170.
    var effectiveRHCInput: LMRotationalHandControllerInput {
        .signedCounts(
            pitch: effectiveRHCPitch,
            yaw: effectiveRHCYaw,
            roll: effectiveRHCRoll
        )
    }

    func replay(speed: Double = 8) {
        guard canReplay, let recording else { return }
        stop()
        let replay = LMFlightReplay(recording: recording)
        let rate = max(0.25, speed)
        let modeLabel = recording.controlMode == .astronautP66 ? "P66 crew" : "automatic"
        status = .replaying
        isPaused = false
        loadMessage = "Replay · " + modeLabel + " · " + rate.formatted() + "×"
        replayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var elapsed = 0.0
            var last = CACurrentMediaTime()
            while !Task.isCancelled {
                if !self.isSceneActive || self.isPaused {
                    try? await Task.sleep(for: .milliseconds(100))
                    last = CACurrentMediaTime()
                    continue
                }
                let now = CACurrentMediaTime()
                elapsed += (now - last) * rate
                last = now
                self.replayFrame = replay.frame(at: elapsed)
                if elapsed >= recording.durationSeconds { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            self.replayFrame = replay.frame(at: recording.durationSeconds)
            self.replayTask = nil
            self.status = .stopped
            self.loadMessage = "Replay complete · "
                + (recording.flightOutcome?.rawValue ?? "inFlight")
        }
    }

    private func makeFrameInput() -> LMFrameInput {
        let state = snapshot?.vehicleState
            ?? scenario.initialState
        let controller = effectiveRHCInput
        let descendPlus = rodSwitchPosition == .descendPlus
        let descendMinus = rodSwitchPosition == .descendMinus
        switch attitudeMode {
        case .automatic:
            return .autoLand(
                from: state,
                rotationalHandController: controller,
                descendPlus: descendPlus,
                descendMinus: descendMinus
            )
        case .attitudeHold:
            return .astronautLand(
                from: state,
                panelState: .p66AttitudeHold,
                attitudeController: controller,
                descendPlus: descendPlus,
                descendMinus: descendMinus
            )
        }
    }

    private func record(_ snapshot: LMSimulationSnapshot) {
        if captureStartSimulationSeconds == nil {
            captureStartSimulationSeconds = snapshot.timeSeconds
            captureStartWallSeconds = CACurrentMediaTime()
        }
        recordedFrames.append(LMFlightFrame(snapshot: snapshot))
        guard ProcessInfo.processInfo.arguments.contains("--cockpit-mission-capture"),
              Int(snapshot.timeSeconds) != lastCaptureSecond || snapshot.vehicleState.flightOutcome.isTerminal else { return }
        lastCaptureSecond = Int(snapshot.timeSeconds)
        let state = snapshot.vehicleState
        var report: [String: Any] = ["timeSeconds": snapshot.timeSeconds,
            "program": snapshot.agc.dsky.programNumber ?? 0, "scenarioID": scenario.id,
            "startProgram": lastStartPoint.programLabel,
            "elapsedSimulationSeconds": snapshot.timeSeconds - (captureStartSimulationSeconds ?? snapshot.timeSeconds),
            "elapsedWallSeconds": CACurrentMediaTime() - (captureStartWallSeconds ?? CACurrentMediaTime()),
            "terminal": state.flightOutcome.isTerminal,
            "probeContact": state.landingGear.map { $0.isProbeContact as Any } ?? NSNull(),
            "footpadContact": state.surfaceContact != nil,
            "altitudeMeters": state.altitudeMeters, "outcome": state.flightOutcome.rawValue,
            "northMeters": state.positionMeters.x, "eastMeters": state.positionMeters.y,
            "terrain": terrainCaptureMetrics?() ?? [:],
            "streaming": ["terrainWaitSeconds": terrainWaitSeconds,
                          "publicationWaitSeconds": publicationWaitSeconds,
                          "maximumPublicationWaitSeconds": maximumPublicationWaitSeconds,
                          "realtimeClampedSeconds": realtimeClampedSeconds]]
        if let contact = state.surfaceContact {
            report["contactVerticalSpeed"] = contact.verticalSpeedMetersPerSecond
            report["contactHorizontalSpeed"] = contact.horizontalSpeedMetersPerSecond
            report["contactTiltDegrees"] = contact.tiltRadians * 180 / .pi
            if let normal = contact.surfaceNormal {
                report["contactSurfaceNormalSiteENU"] = [normal.x, normal.y, normal.z]
                report["contactSurfaceSlopeToSiteUpDegrees"] = acos(min(1, max(-1, normal.z))) * 180 / .pi
            }
        }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("CockpitMissionLatest.json"), options: .atomic)
        }
        if state.flightOutcome.isTerminal {
            let recording = LMFlightRecording(scenarioID: scenario.id, controlMode: .automatic, frames: recordedFrames)
            let recordingRunID = runID
            captureExport?.cancel()
            captureExport = Task { @MainActor [weak self] in
                let temporary = directory.appendingPathComponent("CockpitMission-\(UUID()).partial")
                defer { try? FileManager.default.removeItem(at: temporary) }
                let worker = Task.detached(priority: .utility) {
                    try LMLunarTerrainTiming.measure("cockpit-recording-export") {
                        try Task.checkCancellation()
                        LMLunarTerrainTiming.memory("cockpit-recording-before")
                        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        let handle = try FileHandle(forWritingTo: temporary)
                        do {
                            try recording.writeJSON(to: handle)
                            try handle.close()
                        } catch {
                            try? handle.close()
                            throw error
                        }
                        LMLunarTerrainTiming.memory("cockpit-recording-after")
                    }
                }
                do {
                    try await withTaskCancellationHandler(operation: { try await worker.value },
                                                          onCancel: { worker.cancel() })
                    guard !Task.isCancelled, self?.runID == recordingRunID else { return }
                    // Only the atomic rename runs on the main actor. A stopped
                    // or restarted flight cannot publish an older recording.
                    let destination = directory.appendingPathComponent("CockpitMissionRecording.json")
                    let publication = LMLunarTerrainTiming.begin("cockpit-recording-publication")
                    defer { LMLunarTerrainTiming.end(publication) }
                    guard rename(temporary.path, destination.path) == 0 else { return }
                } catch { /* Capture failure leaves no partial final recording. */ }
            }
        }
    }

    private func finishRecording() {
        guard !recordedFrames.isEmpty else { return }
        recording = LMFlightRecording(
            scenarioID: scenario.id,
            controlMode: recordedFrames.contains { $0.panelState.attitudeMode == .attitudeHold }
                ? .astronautP66
                : .automatic,
            frames: recordedFrames
        )
    }

    private func autoLandMessage(program: Int?, accelerated: Bool) -> String {
        let prog = program.map { "P\($0)" } ?? "P63"
        if accelerated {
            return "Auto-land · \(prog) accelerated GET"
        }
        return "Auto-land · \(prog) at 1×"
    }

    nonisolated static func altitudeText(_ meters: Double) -> String {
        String(format: "%.0f ft", meters * 3.280_839_895)
    }
}

extension LMVehicleSnapshot {
    /// The command snapshot can still contain Luminary's final engine-on bit on
    /// the exact frame where the dynamics model declares contact. Terminal
    /// vehicle states no longer propagate thrust, so presentation and audio must
    /// resolve that latched command as a physically stopped engine.
    func isMainEngineProducingThrust(outcome: LMFlightOutcome?) -> Bool {
        outcome?.isTerminal != true && mainEngineOn && !mainEngineOff
    }

    /// Once the vehicle is settled on its gear the dynamics stop propagating
    /// thrust, and once a footpad is loaded the descent engine is no longer
    /// flying the vehicle. Presentation and audio follow the state, not the
    /// latched command bit.
    func isMainEngineProducingThrust(state: LMVehicleStateSnapshot?) -> Bool {
        guard isMainEngineProducingThrust(outcome: state?.flightOutcome) else {
            return false
        }
        // The dynamics stop the descent engine at footpad contact, modeling the
        // crew's ENGINE STOP. Presentation and audio follow the state.
        return state?.surfaceContact == nil
    }
}
