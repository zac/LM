import Foundation
import QuartzCore
import AGC
import LMCore

@MainActor
@Observable
final class PoweredDescentSession {
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
    var descendPlus = false
    var descendMinus = false

    @ObservationIgnored private var runtime: LMSimulationRuntime?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var replayTask: Task<Void, Never>?
    @ObservationIgnored private var dskyTask: Task<Void, Never>?
    @ObservationIgnored private var recordedFrames: [LMFlightFrame] = []
    @ObservationIgnored private var runID = UUID()

    var dsky: DSKYSnapshot? { snapshot?.agc.dsky }
    var programNumber: Int? { replayFrame?.programNumber ?? dsky?.programNumber }
    var vehicleState: LMVehicleStateSnapshot? { replayFrame?.vehicleState ?? snapshot?.vehicleState }
    var vehicleCommands: LMVehicleSnapshot? { replayFrame?.vehicleCommands ?? snapshot?.vehicleCommands }

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

    func loadProgram() {
        stop()
        recording = nil
        replayFrame = nil
        recordedFrames.removeAll()
        dskyTask?.cancel()
        dskyTask = nil
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
            if ProcessInfo.processInfo.arguments.contains("--replay-automatic") {
                recording = try? Self.bundledAutomaticRecording()
            } else {
                recording = try? Self.bundledP66Recording()
            }
            loadMessage = "Luminary 099 · Apollo 11 powered-descent foundation"
            status = .idle
            Task { @MainActor [weak self] in
                guard let self else { return }
                let snap = await loaded.snapshot()
                self.snapshot = snap
            }
        } catch {
            runtime = nil
            snapshot = nil
            status = .error(error.localizedDescription)
            loadMessage = error.localizedDescription
        }
    }

    func start() {
        guard canStart, let runtime else { return }
        loopTask?.cancel()
        let runID = UUID()
        self.runID = runID
        replayFrame = nil
        recordedFrames.removeAll(keepingCapacity: true)
        isRunning = true
        status = .running
        loopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if (self.snapshot?.agc.cycle ?? 0) < 1_000_000 {
                self.loadMessage = "Auto-land · booting Luminary 099…"
                let prepared = await runtime.bootAndEnterP63()
                guard self.runID == runID else { return }
                self.snapshot = prepared
                self.record(prepared)
                self.loadMessage = self.autoLandMessage(program: prepared.agc.dsky.programNumber, accelerated: true)
            }
            var last = CACurrentMediaTime()
            while !Task.isCancelled, self.runID == runID {
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
                    await Task.yield()
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
        replayFrame = nil
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
        rhcPitch = 0
        rhcYaw = 0
        rhcRoll = 0
        attitudeMode = .automatic
        descendPlus = false
        descendMinus = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.snapshot = try await runtime.reset()
                self.status = .idle
            } catch {
                self.status = .error(error.localizedDescription)
            }
        }
    }

    func sendDSKYKey(_ key: DSKYKeyCode) {
        guard let runtime else { return }
        Task {
            await runtime.sendDSKYKey(key)
            if !self.isRunning {
                let snap = await runtime.snapshot()
                await MainActor.run { self.snapshot = snap }
            }
        }
    }

    func sendDSKYScript(_ script: DSKYScript) {
        guard runtime != nil else { return }
        dskyTask?.cancel()
        dskyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for key in script.keys {
                if Task.isCancelled { break }
                self.sendDSKYKey(key)
                try? await Task.sleep(for: .milliseconds(180))
            }
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
            pitch: rhcPitch,
            yaw: rhcYaw,
            roll: rhcRoll
        )
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
}
