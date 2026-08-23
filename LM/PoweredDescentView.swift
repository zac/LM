import SwiftUI
import LMCore

struct PoweredDescentView: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase
    @State private var didLaunchReplayFixture = false

    var body: some View {
        @Bindable var session = appModel.session
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 18) {
                            FDAIPanel(session: session)
                            controls
                        }
                        .frame(width: 220)

                        DSKYPanel(session: session)
                            .frame(maxWidth: .infinity)

                        telemetry
                            .frame(width: 230)
                    }

                }
                .frame(maxWidth: 1180)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .contentMargins(.bottom, 120, for: .scrollContent)
            .navigationTitle("Powered Descent")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink("RCS sandbox") {
                        LunarLanderSimulationView()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Full cockpit") {
                        Task { await enterFullCockpit() }
                    }
                    .disabled(appModel.fullDescentSpaceState == .inTransition)
                }
            }
            .ornament(attachmentAnchor: .scene(.bottom)) {
                CrewControlPanel(session: session)
                    .frame(width: 620)
            }
        }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard !didLaunchReplayFixture,
                  arguments.contains("--replay-p66")
                    || arguments.contains("--replay-automatic")
                    || arguments.contains("--full-cockpit") else { return }
            didLaunchReplayFixture = true
            if arguments.contains("--full-cockpit") {
                await enterFullCockpit()
            } else {
                appModel.session.replay(speed: 2)
                await toggleDescentSpace()
            }
        }
        .onAppear {
            appModel.session.setSceneActive(scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            appModel.session.setSceneActive(phase == .active)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appModel.session.loadMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(statusLabel)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button { appModel.session.start() } label: {
                        Image(systemName: "arrow.down.to.line")
                    }
                        .disabled(!appModel.session.canStart)
                        .accessibilityLabel("Auto-land")
                        .help("Auto-land")
                    Button { appModel.session.stop() } label: {
                        Image(systemName: "stop.fill")
                    }
                        .disabled(!appModel.session.canStop)
                        .accessibilityLabel("Stop")
                        .help("Stop")
                    Button { appModel.session.reset() } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                        .disabled(!appModel.session.canReset)
                        .accessibilityLabel("Reset")
                        .help("Reset")
                    Button { appModel.session.replay() } label: {
                        Image(systemName: "play.square.stack")
                    }
                        .disabled(!appModel.session.canReplay)
                        .accessibilityLabel("Replay last flight")
                        .help("Replay last flight at 8×")
                }
                Button(appModel.descentSpaceState == .open ? "Leave table" : "Table") {
                    Task { await toggleDescentSpace() }
                }
                .disabled(appModel.descentSpaceState == .inTransition)
                .accessibilityLabel(appModel.descentSpaceState == .open ? "Leave table" : "Auto-land on table")
            }
            .buttonStyle(.borderedProminent)

            Label("Luminary 099 · P63 → P64 → P65", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Auto-land boots Luminary, keys V37E63E, and answers V06N61 / V50N25 / V50N18 / V99 so P63→P64→P65 run closed-loop. P63 GET is accelerated; P64 onward is 1×. The range bead is the map until the last few kilometers; the LM stays over the pad until then. Body rates still come only from DPS gimbal and RCS jets.")
        }
    }

    private var telemetry: some View {
        let state = appModel.session.vehicleState
        let commands = appModel.session.vehicleCommands
        return VStack(alignment: .leading, spacing: 6) {
            Text("Vehicle")
                .font(.headline)
            Group {
                labeled("Altitude", feetAndMeters(state?.altitudeMeters))
                labeled("H-dot", String(format: "%+.2f m/s", state?.verticalSpeedMetersPerSecond ?? 0))
                labeled("H-vel", String(format: "%.1f m/s", {
                    let vx = state?.velocityMetersPerSecond.x ?? 0
                    let vy = state?.velocityMetersPerSecond.y ?? 0
                    return (vx * vx + vy * vy).squareRoot()
                }()))
                labeled("Range", rangeLabel(state?.downrangeMeters))
                labeled("Gimbal", String(
                    format: "P %+0.2f°  R %+0.2f°",
                    (state?.dpsPitchGimbalRadians ?? 0) * 180 / .pi,
                    (state?.dpsRollGimbalRadians ?? 0) * 180 / .pi
                ))
                labeled("Mass", state?.massKilograms.map { String(format: "%.0f kg", $0) } ?? "—")
                labeled("Landed", (state?.isLanded ?? false) ? "yes" : "no")
                labeled("Engine", engineLabel(commands))
                labeled("RCS jets", "\(commands?.rcsJets.count ?? 0)")
                labeled("Radar alt", feetAndMeters(appModel.session.radarAltitudeMeters))
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private var statusLabel: String {
        switch appModel.session.status {
        case .unloaded: return "Not loaded"
        case .idle: return "Idle"
        case .running: return "Running"
        case .replaying: return "Replaying"
        case .stopped: return "Stopped"
        case .error(let message): return "Error: \(message)"
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func rangeLabel(_ downrangeMeters: Double?) -> String {
        guard let downrangeMeters else { return "—" }
        let meters = abs(downrangeMeters)
        let nauticalMiles = meters / 1852.0
        let magnitude = String(format: "%.1f nmi  (%.1f km)", nauticalMiles, meters / 1000)
        if downrangeMeters > 50 {
            return "past \(magnitude)"
        }
        return magnitude
    }

    private func feetAndMeters(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        let feet = meters / 0.3048
        return String(format: "%.0f ft  (%.1f m)", feet, meters)
    }

    private func engineLabel(_ commands: LMVehicleSnapshot?) -> String {
        guard let commands else { return "—" }
        let on = commands.mainEngineOn && !commands.mainEngineOff
        if let newtons = commands.dps.commandedThrustNewtons, on {
            return String(format: "ON %.0f N", newtons)
        }
        return on ? "ON" : "OFF"
    }

    private func toggleDescentSpace() async {
        switch appModel.descentSpaceState {
        case .open:
            appModel.descentSpaceState = .inTransition
            await dismissImmersiveSpace()
        case .closed:
            appModel.descentSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.descentSpaceID) {
            case .opened:
                if appModel.session.canStart {
                    appModel.session.start()
                }
            case .userCancelled, .error:
                fallthrough
            @unknown default:
                appModel.descentSpaceState = .closed
            }
        case .inTransition:
            break
        }
    }

    /// Leave the tabletop theater and enter the life-size full-immersion
    /// cockpit, resuming from the bundled P65 checkpoint so the scene is
    /// controllable within seconds of launch.
    private func enterFullCockpit() async {
        if appModel.descentSpaceState == .open {
            appModel.descentSpaceState = .inTransition
            await dismissImmersiveSpace()
        }
        appModel.fullDescentSpaceState = .inTransition
        switch await openImmersiveSpace(id: appModel.fullDescentSpaceID) {
        case .opened:
            if appModel.session.canStart {
                appModel.session.start(from: .p65TerminalDescent)
            }
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            appModel.fullDescentSpaceState = .closed
        }
    }
}

#Preview(windowStyle: .automatic) {
    PoweredDescentView()
        .environment(MainMenuViewModel())
}
