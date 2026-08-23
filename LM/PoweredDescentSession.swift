import Foundation
import QuartzCore
import AGC
import LMCore

@MainActor
@Observable
final class PoweredDescentSession {
    /// Where a live run begins. `.ignition` boots Luminary fresh and flies the
    /// automatic P63 approach; `.p65TerminalDescent` restores the validated
    /// bundled checkpoint so the cockpit is controllable within seconds.
    enum StartPoint: Equatable {
        case ignition
        case p65TerminalDescent
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
    private(set) var snapshot: LMSimulationSnapshot?
    private(set) var replayFrame: LMFlightReplayFrame?
    private(set) var recording: LMFlightRecording?
    private(set) var loadMessage = "Luminary 099 not loaded"

    var attitudeMode = LMPoweredDescentAttitudeMode.automatic
    var rhcPitch = 0
    var rhcYaw = 0
    var rhcRoll = 0
    /// Continuous analog ACA axes (-1…1). Buttons add discrete ±42-count
    /// commands on top; the combined deflection clamps at ±57 counts.
    var aca = LMACANormalizedInput.neutral
    private(set) var rodSwitchPosition = RODSwitchPosition.neutral

    @ObservationIgnored private var runtime: LMSimulationRuntime?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var replayTask: Task<Void, Never>?
    @ObservationIgnored private var dskyTask: Task<Void, Never>?
    @ObservationIgnored private var dskyKeyTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var recordedFrames: [LMFlightFrame] = []
    @ObservationIgnored private var runID = UUID()
    @ObservationIgnored private var isSceneActive = true
    @ObservationIgnored private var p65Checkpoint: LMSimulationCheckpoint?
    @ObservationIgnored private var lastStartPoint: StartPoint = .ignition

    var dsky: DSKYSnapshot? { snapshot?.agc.dsky }
    var programNumber: Int? { replayFrame?.programNumber ?? dsky?.programNumber }
    var vehicleState: LMVehicleStateSnapshot? { replayFrame?.vehicleState ?? snapshot?.vehicleState }
    var vehicleCommands: LMVehicleSnapshot? { replayFrame?.vehicleCommands ?? snapshot?.vehicleCommands }
    var radarAltitudeMeters: Double? {
        guard replayFrame == nil,
              case .measurement(let measurement)? = snapshot?.sensorState.radarInput else {
            return nil
        }
        return measurement.altitudeMeters
    }

    var canStart: Bool { runtime != nil && !isRunning && replayTask == nil }
    var canStop: Bool { isRunning || replayTask != nil }
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

    /// Decode and fully validate the bundled P65 terminal-descent checkpoint
    /// against the bundled Luminary099.bin and scenario identity.
    nonisolated static func bundledP65Checkpoint(
        in bundle: Bundle = .main
    ) throws -> LMSimulationCheckpoint {
        guard let checkpointURL = bundle.url(
            forResource: "P65TerminalDescentCheckpoint",
            withExtension: "bplist"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let checkpoint = try LMSimulationCheckpoint.decodeFixture(
            Data(contentsOf: checkpointURL)
        )
        guard let binURL = bundle.url(forResource: "Luminary099", withExtension: "bin") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try checkpoint.validate(
            coreImageSHA256: AGCRuntimeCheckpoint.coreImageSHA256(of: Data(contentsOf: binURL)),
            scenarioID: LMPoweredDescentScenario.apollo11SourceBacked.id
        )
        return checkpoint
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
            let loaded = try LMSimulationRuntime(binFile: url, scenario: .apollo11SourceBacked)
            runtime = loaded
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
            loadMessage = "Luminary 099 · Apollo 11 powered-descent foundation"
            status = .idle
            snapshotTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let snap = await loaded.snapshot()
                guard !Task.isCancelled else { return }
                self.snapshot = snap
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

    /// Begin a live run. `.ignition` boots Luminary and flies the automatic
    /// approach from P63; `.p65TerminalDescent` restores the bundled checkpoint
    /// into the running runtime, which needs no boot or replay frames.
    func start(from startPoint: StartPoint) {
        guard canStart, let runtime else { return }
        if startPoint == .p65TerminalDescent && p65Checkpoint == nil {
            status = .error("P65 terminal-descent checkpoint is unavailable.")
            return
        }
        loopTask?.cancel()
        let runID = UUID()
        self.runID = runID
        lastStartPoint = startPoint
        replayFrame = nil
        recordedFrames.removeAll(keepingCapacity: true)
        isRunning = true
        status = .running
        loopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if startPoint == .p65TerminalDescent {
                guard let checkpoint = self.p65Checkpoint else {
                    self.status = .error("P65 terminal-descent checkpoint is unavailable.")
                    self.isRunning = false
                    return
                }
                do {
                    let restored = try await runtime.restore(from: checkpoint)
                    guard self.runID == runID else { return }
                    self.snapshot = restored
                    self.record(restored)
                    self.loadMessage = "Live · restored P65 at "
                        + Self.altitudeText(restored.vehicleState.altitudeMeters)
                } catch {
                    guard self.runID == runID else { return }
                    self.isRunning = false
                    self.loopTask = nil
                    self.status = .error(error.localizedDescription)
                    return
                }
            } else if (self.snapshot?.agc.cycle ?? 0) < 1_000_000 {
                self.loadMessage = "Auto-land · booting Luminary 099…"
                let prepared = await runtime.bootAndEnterP63()
                guard self.runID == runID else { return }
                self.snapshot = prepared
                self.record(prepared)
                self.loadMessage = self.autoLandMessage(program: prepared.agc.dsky.programNumber, accelerated: true)
            }
            var last = CACurrentMediaTime()
            while !Task.isCancelled, self.runID == runID {
                if !self.isSceneActive {
                    try? await Task.sleep(for: .milliseconds(100))
                    last = CACurrentMediaTime()
                    continue
                }
                let now = CACurrentMediaTime()
                let wallDelta = now - last
                last = now
                let pace = LMSimulationPace.pace(programNumber: self.snapshot?.agc.dsky.programNumber)
                let delta = pace.simulationDelta(wallDelta: wallDelta)
                let snap = await runtime.step(deltaTime: delta, input: self.makeFrameInput())
                guard self.runID == runID else { return }
                self.snapshot = snap
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
        runID = UUID()
        loopTask?.cancel()
        loopTask = nil
        replayTask?.cancel()
        replayTask = nil
        dskyTask?.cancel()
        dskyTask = nil
        dskyKeyTask?.cancel()
        dskyKeyTask = nil
        snapshotTask?.cancel()
        snapshotTask = nil
        replayFrame = nil
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

    func sendDSKYKey(_ key: DSKYKeyCode) {
        guard let runtime else { return }
        dskyTask?.cancel()
        dskyTask = nil
        dskyKeyTask?.cancel()
        dskyKeyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await runtime.sendDSKYKey(key)
            guard !Task.isCancelled else { return }
            if !self.isRunning {
                let snap = await runtime.snapshot()
                guard !Task.isCancelled else { return }
                self.snapshot = snap
            }
            self.dskyKeyTask = nil
        }
    }

    func sendDSKYScript(_ script: DSKYScript) {
        guard let runtime else { return }
        dskyKeyTask?.cancel()
        dskyKeyTask = nil
        dskyTask?.cancel()
        dskyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for key in script.keys {
                if Task.isCancelled { break }
                await runtime.sendDSKYKey(key)
                guard !Task.isCancelled else { break }
                if !self.isRunning {
                    self.snapshot = await runtime.snapshot()
                }
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
        rhcPitch = 0
        rhcYaw = 0
        rhcRoll = 0
        releaseACA()
        rodSwitchPosition = .neutral
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
            aca.pitch = min(max(pitch, -1), 1)
        }
        if let yaw {
            aca.yaw = min(max(yaw, -1), 1)
        }
        if let roll {
            aca.roll = min(max(roll, -1), 1)
        }
    }

    /// Handle released or hand tracking lost: every axis returns to neutral
    /// before the next simulation frame is built.
    func releaseACA() {
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

    func replay(speed: Double = 8) {
        guard canReplay, let recording else { return }
        stop()
        let replay = LMFlightReplay(recording: recording)
        let rate = max(0.25, speed)
        let modeLabel = recording.controlMode == .astronautP66 ? "P66 crew" : "automatic"
        status = .replaying
        loadMessage = "Replay · " + modeLabel + " · " + rate.formatted() + "×"
        replayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let start = CACurrentMediaTime()
            while !Task.isCancelled {
                let elapsed = (CACurrentMediaTime() - start) * rate
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
            ?? LMPoweredDescentScenario.apollo11SourceBacked.initialState
        let controller = LMRotationalHandControllerInput(
            pitch: effectiveRHCPitch,
            yaw: effectiveRHCYaw,
            roll: effectiveRHCRoll
        )
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
        recordedFrames.append(LMFlightFrame(snapshot: snapshot))
    }

    private func finishRecording() {
        guard !recordedFrames.isEmpty else { return }
        recording = LMFlightRecording(
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
}
