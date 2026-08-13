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
        case stopped
        case error(String)
    }

    static let maxFrameDelta = 1.0 / 15.0
    static let targetFrameDuration = 1.0 / 60.0
    static let rhcDeflection = 0o2000

    private(set) var status: Status = .unloaded
    private(set) var isRunning = false
    private(set) var snapshot: LMSimulationSnapshot?
    private(set) var loadMessage = "Luminary 099 not loaded"

    var rhcPitch = 0
    var rhcYaw = 0
    var rhcRoll = 0
    var descendPlus = false
    var descendMinus = false

    @ObservationIgnored private var runtime: LMSimulationRuntime?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var dskyTask: Task<Void, Never>?
    @ObservationIgnored private var runID = UUID()

    var dsky: DSKYSnapshot? { snapshot?.agc.dsky }
    var vehicleState: LMVehicleStateSnapshot? { snapshot?.vehicleState }
    var vehicleCommands: LMVehicleSnapshot? { snapshot?.vehicleCommands }

    var canStart: Bool { runtime != nil && !isRunning }
    var canStop: Bool { isRunning }
    var canReset: Bool { runtime != nil }

    init() {
        loadProgram()
    }

    func loadProgram() {
        stop()
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
        isRunning = true
        status = .running
        loopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if (self.snapshot?.agc.cycle ?? 0) < 1_000_000 {
                self.loadMessage = "Booting Luminary 099 and keying V37E63E…"
                let prepared = await runtime.bootAndEnterP63()
                guard self.runID == runID else { return }
                self.snapshot = prepared
                self.loadMessage = "Luminary 099 · V37E63E keyed"
            }
            var last = CACurrentMediaTime()
            while !Task.isCancelled, self.runID == runID {
                let now = CACurrentMediaTime()
                let delta = min(max(now - last, 1.0 / 240.0), Self.maxFrameDelta)
                last = now
                let snap = await runtime.step(deltaTime: delta, input: self.makeFrameInput())
                guard self.runID == runID else { return }
                self.snapshot = snap
                let elapsed = CACurrentMediaTime() - now
                let remaining = Self.targetFrameDuration - elapsed
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                } else {
                    await Task.yield()
                }
            }
            guard self.runID == runID else { return }
            self.isRunning = false
            self.loopTask = nil
            if self.status == .running {
                self.status = .stopped
            }
        }
    }

    func stop() {
        runID = UUID()
        loopTask?.cancel()
        loopTask = nil
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

    private func makeFrameInput() -> LMFrameInput {
        let altitude = snapshot?.vehicleState.altitudeMeters
            ?? LMPoweredDescentScenario.apollo11SourceBacked.initialState.altitudeMeters
        return LMFrameInput(
            radarInput: .measurement(LMRadarMeasurementInput(altitudeMeters: max(0, altitude))),
            rotationalHandControllerInput: LMRotationalHandControllerInput(
                pitch: rhcPitch,
                yaw: rhcYaw,
                roll: rhcRoll
            ),
            descentRateInput: LMDescentRateControlInput(
                descendPlus: descendPlus,
                descendMinus: descendMinus
            ),
            rawChannelInputs: LMPoweredDescentPanel.channelInputs
        )
    }
}
