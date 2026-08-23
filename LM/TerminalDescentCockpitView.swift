import RealityKit
import SwiftUI

struct TerminalDescentCockpitView: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var station = LMCommanderStationScene()
    @State private var didStart = false
    @State private var terrainStatus = "Loading Apollo 11 terrain…"

    var body: some View {
        RealityView { content, attachments in
            content.add(station.root)
            if let instruments = attachments.entity(for: "commander-instruments") {
                station.mountInstruments(instruments)
            }
            station.apply(appModel.session.vehicleState)
        } update: { _, attachments in
            if let instruments = attachments.entity(for: "commander-instruments") {
                station.mountInstruments(instruments)
            }
            station.apply(appModel.session.vehicleState)
        } attachments: {
            Attachment(id: "commander-instruments") {
                HStack(alignment: .top, spacing: 12) {
                    FDAIPanel(session: appModel.session)
                        .frame(width: 230)
                    DSKYPanel(session: appModel.session, showsScripts: false)
                        .frame(width: 430)
                }
                .padding(8)
                .background(Color.black.opacity(0.94))
            }
        }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            HStack(spacing: 10) {
                Button {
                    appModel.session.restart()
                } label: {
                    Label("Restart P65", systemImage: "arrow.counterclockwise")
                }
                .disabled(!appModel.session.canStop && !appModel.session.canStart)

                Button {
                    appModel.session.stop()
                    Task { await dismissImmersiveSpace() }
                } label: {
                    Label("Leave cockpit", systemImage: "rectangle.portrait.and.arrow.right")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(cockpitStatus)
                        .font(.caption.monospacedDigit())
                    Text(terrainStatus)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .padding(10)
            .glassBackgroundEffect()
        }
        .task {
            guard !didStart else { return }
            didStart = true
            if appModel.session.canStart {
                appModel.session.start(from: .p65TerminalDescent)
            }
            do {
                try await station.loadApollo11Terrain()
                terrainStatus = "LROC NAC DTM · 2.05 km · true vertical scale"
            } catch {
                terrainStatus = "Terrain unavailable · \(error.localizedDescription)"
            }
        }
        .onDisappear {
            appModel.session.releaseACA()
            appModel.session.setROD(.descendPlus, held: false)
            appModel.session.setROD(.descendMinus, held: false)
        }
    }

    private var cockpitStatus: String {
        let program = appModel.session.programNumber.map { "P\($0)" } ?? "P--"
        let feet = (appModel.session.vehicleState?.altitudeMeters ?? 0) * 3.280_839_895
        return String(format: "%@ · %.0f ft", program, feet)
    }
}

#Preview(immersionStyle: .full) {
    TerminalDescentCockpitView()
        .environment(MainMenuViewModel())
}
