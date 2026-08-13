import SwiftUI
import LMCore

struct PoweredDescentView: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        @Bindable var session = appModel.session
        NavigationStack {
            HStack(alignment: .top, spacing: 20) {
                DSKYPanel(session: session)
                    .frame(minWidth: 420)

                VStack(alignment: .leading, spacing: 16) {
                    controls
                    telemetry
                    CrewControlPanel(session: session)
                    Spacer()
                }
                .frame(minWidth: 320)
            }
            .padding(20)
            .navigationTitle("Powered Descent")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink("RCS sandbox") {
                        LunarLanderSimulationView()
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appModel.session.loadMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(statusLabel)
                .font(.headline)

            HStack(spacing: 12) {
                Button("Start") { appModel.session.start() }
                    .disabled(!appModel.session.canStart)
                Button("Stop") { appModel.session.stop() }
                    .disabled(!appModel.session.canStop)
                Button("Reset") { appModel.session.reset() }
                    .disabled(!appModel.session.canReset)
                Button(appModel.descentSpaceState == .open ? "Leave table" : "Place on table") {
                    Task { await toggleDescentSpace() }
                }
                .disabled(appModel.descentSpaceState == .inTransition)
            }
            .buttonStyle(.borderedProminent)

            Text("PDI kinematics are sourced from NASA TN D-6846 and TN D-4131. Start boots Luminary, loads NASA Luminary 99 pad-loads (including RLS/TEPHEM) and MODE CONTROL AUTO, then keys V37E63E. RN is a moon-fixed offset from NASA RLS, still over the site. V50N25 is ENTERed to skip fine-align; V50N18 and V99 PROCEED are held automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                labeled("Gimbal", String(
                    format: "P %+0.2f°  R %+0.2f°",
                    (state?.dpsPitchGimbalRadians ?? 0) * 180 / .pi,
                    (state?.dpsRollGimbalRadians ?? 0) * 180 / .pi
                ))
                labeled("Mass", state?.massKilograms.map { String(format: "%.0f kg", $0) } ?? "—")
                labeled("Landed", (state?.isLanded ?? false) ? "yes" : "no")
                labeled("Engine", engineLabel(commands))
                labeled("RCS jets", "\(commands?.rcsJets.count ?? 0)")
                labeled("Radar alt", feetAndMeters(state?.altitudeMeters))
            }
            .font(.system(.body, design: .monospaced))
        }
    }

    private var statusLabel: String {
        switch appModel.session.status {
        case .unloaded: return "Not loaded"
        case .idle: return "Idle"
        case .running: return "Running"
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
                break
            case .userCancelled, .error:
                fallthrough
            @unknown default:
                appModel.descentSpaceState = .closed
            }
        case .inTransition:
            break
        }
    }
}

#Preview(windowStyle: .automatic) {
    PoweredDescentView()
        .environment(MainMenuViewModel())
}
