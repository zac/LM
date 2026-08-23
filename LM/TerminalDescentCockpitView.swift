import RealityKit
import SwiftUI

struct TerminalDescentCockpitView: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase
    @State private var station = LMCommanderStationScene()
    @State private var didStart = false
    @State private var terrainStatus = "Loading Apollo 11 terrain…"
    @State private var acaGestureOrigin: SIMD3<Float>?
    @State private var rodGestureOrigin: SIMD3<Float>?
    @State private var showsFallbackControls = false

    private let controlMapper = LMSpatialControlMapper()

    var body: some View {
        RealityView { content, attachments in
            content.add(station.root)
            if let instruments = attachments.entity(for: "commander-instruments") {
                station.mountInstruments(instruments)
            }
            applySceneState()
        } update: { _, attachments in
            if let instruments = attachments.entity(for: "commander-instruments") {
                station.mountInstruments(instruments)
            }
            applySceneState()
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
        .gesture(acaGesture)
        .simultaneousGesture(rodGesture)
        .simultaneousGesture(attitudeModeGesture)
        .ornament(attachmentAnchor: .scene(.bottom)) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        appModel.session.restart()
                    } label: {
                        Label("Restart P65", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!appModel.session.canStop && !appModel.session.canStart)

                    Button {
                        showsFallbackControls.toggle()
                    } label: {
                        Label(
                            showsFallbackControls ? "Hide fallback" : "Fallback controls",
                            systemImage: "slider.horizontal.3"
                        )
                    }

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
                        Text("Grip ACA · drag ROD · tap MODE CONTROL")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                if showsFallbackControls {
                    CrewControlPanel(session: appModel.session)
                        .frame(width: 620)
                }
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                releaseSpatialControls()
            }
        }
        .onDisappear {
            releaseSpatialControls()
        }
    }

    private var acaGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(station.acaHandle)
            .onChanged { value in
                let sceneLocation = value.convert(value.location3D, from: .local, to: .scene)
                if acaGestureOrigin == nil {
                    acaGestureOrigin = sceneLocation
                }
                guard let origin = acaGestureOrigin else { return }
                let input = controlMapper.acaInput(for: sceneLocation - origin)
                appModel.session.setACA(
                    pitch: input.pitch,
                    yaw: input.yaw,
                    roll: input.roll
                )
                station.setACAVisual(input)
            }
            .onEnded { _ in
                acaGestureOrigin = nil
                appModel.session.releaseACA()
                station.setACAVisual(.neutral)
            }
    }

    private var rodGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(station.rodSwitch)
            .onChanged { value in
                let sceneLocation = value.convert(value.location3D, from: .local, to: .scene)
                if rodGestureOrigin == nil {
                    rodGestureOrigin = sceneLocation
                }
                guard let origin = rodGestureOrigin else { return }
                applyROD(controlMapper.rodPosition(for: sceneLocation.y - origin.y))
            }
            .onEnded { _ in
                rodGestureOrigin = nil
                applyROD(.neutral)
            }
    }

    private var attitudeModeGesture: some Gesture {
        TapGesture()
            .targetedToEntity(station.attitudeModeSwitch)
            .onEnded { _ in
                let selectsP66 = appModel.session.attitudeMode != .attitudeHold
                appModel.session.attitudeMode = selectsP66 ? .attitudeHold : .automatic
                station.setAttitudeHoldVisual(selectsP66)
            }
    }

    private func applySceneState() {
        station.apply(appModel.session.vehicleState)
        station.setACAVisual(appModel.session.aca)
        station.setRODVisual(appModel.session.rodSwitchPosition)
        station.setAttitudeHoldVisual(appModel.session.attitudeMode == .attitudeHold)
    }

    private func applyROD(_ position: PoweredDescentSession.RODSwitchPosition) {
        appModel.session.setROD(.descendPlus, held: position == .descendPlus)
        appModel.session.setROD(.descendMinus, held: position == .descendMinus)
        station.setRODVisual(position)
    }

    private func releaseSpatialControls() {
        acaGestureOrigin = nil
        rodGestureOrigin = nil
        appModel.session.releaseACA()
        applyROD(.neutral)
        station.setACAVisual(.neutral)
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
