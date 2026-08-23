import RealityKit
import SwiftUI
import OSLog

struct TerminalDescentCockpitView: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var station = LMCommanderStationScene()
    @State private var didStart = false
    @State private var terrainStatus = "Loading Apollo 11 terrain…"
    @State private var acaGestureOrigin: SIMD3<Float>?
    @State private var rodGestureOrigin: SIMD3<Float>?
    @State private var showsFallbackControls = false
    @State private var trainingOverlayEnabled = true
    @State private var audioEnabled = true
    @State private var experienceDirector = LMCockpitExperienceDirector()
    @State private var activeCue: LMCockpitCue?
    @State private var cuePresentationTask: Task<Void, Never>?
    @State private var audioController = LMCockpitAudioController()
    @GestureState private var acaGestureIsActive = false
    @GestureState private var rodGestureIsActive = false

    private let controlMapper = LMSpatialControlMapper()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.positron.LM",
        category: "TerminalDescentCockpit"
    )

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
                        restartExperience()
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
                        trainingOverlayEnabled.toggle()
                    } label: {
                        Label(
                            trainingOverlayEnabled ? "Training on" : "Training off",
                            systemImage: trainingOverlayEnabled ? "scope" : "scope"
                        )
                    }

                    Button {
                        audioEnabled.toggle()
                        audioController.isEnabled = audioEnabled
                    } label: {
                        Label(
                            audioEnabled ? "Audio on" : "Audio off",
                            systemImage: audioEnabled ? "speaker.wave.2" : "speaker.slash"
                        )
                    }

                    Button {
                        leaveCockpit()
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
        .ornament(attachmentAnchor: .scene(.top)) {
            if let activeCue {
                VStack(spacing: 4) {
                    Text(activeCue.title)
                        .font(.title3.weight(.bold).monospaced())
                        .foregroundStyle(cueColor(activeCue))
                    if trainingOverlayEnabled {
                        Text(activeCue.detail)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassBackgroundEffect()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(activeCue.title)
                .accessibilityValue(trainingOverlayEnabled ? activeCue.detail : "")
            }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            appModel.session.setSceneActive(scenePhase == .active)
            audioController.isEnabled = audioEnabled
            audioController.start()
            if appModel.session.canStart {
                appModel.session.start(from: .p65TerminalDescent)
            }
            updateExperience()
            do {
                try await station.loadApollo11Terrain()
                terrainStatus = "LROC NAC DTM · 2.05 km · true vertical scale"
                logger.info("Apollo 11 LROC terrain loaded")
            } catch {
                terrainStatus = "Terrain unavailable · \(error.localizedDescription)"
                logger.error("Apollo 11 terrain failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        .onChange(of: appModel.session.snapshot?.agc.cycle) { _, _ in
            updateExperience()
        }
        .onChange(of: scenePhase) { _, phase in
            appModel.session.setSceneActive(phase == .active)
            if phase != .active {
                releaseSpatialControls()
            }
        }
        .onChange(of: acaGestureIsActive) { wasActive, isActive in
            if wasActive && !isActive {
                releaseACAControl()
            }
        }
        .onChange(of: rodGestureIsActive) { wasActive, isActive in
            if wasActive && !isActive {
                releaseRODControl()
            }
        }
        .onDisappear {
            releaseSpatialControls()
            appModel.session.setSceneActive(false)
            cuePresentationTask?.cancel()
            audioController.stop()
            openWindow(id: appModel.descentConsoleWindowID)
        }
    }

    private var acaGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(station.acaHandle)
            .updating($acaGestureIsActive) { _, isActive, _ in
                isActive = true
            }
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
                releaseACAControl()
            }
    }

    private var rodGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(station.rodSwitch)
            .updating($rodGestureIsActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { value in
                let sceneLocation = value.convert(value.location3D, from: .local, to: .scene)
                if rodGestureOrigin == nil {
                    rodGestureOrigin = sceneLocation
                }
                guard let origin = rodGestureOrigin else { return }
                applyROD(controlMapper.rodPosition(for: sceneLocation.y - origin.y))
            }
            .onEnded { _ in
                releaseRODControl()
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
        station.updateDust(
            state: appModel.session.vehicleState,
            commands: appModel.session.vehicleCommands
        )
    }

    private func applyROD(_ position: PoweredDescentSession.RODSwitchPosition) {
        appModel.session.setROD(.descendPlus, held: position == .descendPlus)
        appModel.session.setROD(.descendMinus, held: position == .descendMinus)
        station.setRODVisual(position)
    }

    private func releaseSpatialControls() {
        releaseACAControl()
        releaseRODControl()
    }

    private func releaseACAControl() {
        acaGestureOrigin = nil
        appModel.session.releaseACA()
        station.setACAVisual(.neutral)
    }

    private func releaseRODControl() {
        rodGestureOrigin = nil
        applyROD(.neutral)
    }

    private func updateExperience() {
        let session = appModel.session
        audioController.update(
            commands: session.vehicleCommands,
            outcome: session.vehicleState?.flightOutcome
        )
        let cues = experienceDirector.consume(
            program: session.programNumber,
            altitudeMeters: session.vehicleState?.altitudeMeters,
            outcome: session.vehicleState?.flightOutcome,
            hasSurfaceContact: session.vehicleState?.surfaceContact != nil
        )
        guard !cues.isEmpty else { return }
        for cue in cues {
            logger.notice("Cockpit event: \(cue.id.rawValue, privacy: .public)")
        }

        cuePresentationTask?.cancel()
        cuePresentationTask = Task { @MainActor in
            for cue in cues {
                guard !Task.isCancelled else { return }
                activeCue = cue
                audioController.play(cue)
                try? await Task.sleep(for: .seconds(2.4))
            }
            guard !Task.isCancelled else { return }
            activeCue = nil
        }
    }

    private func restartExperience() {
        cuePresentationTask?.cancel()
        activeCue = nil
        experienceDirector.reset()
        appModel.session.restart()
    }

    private func leaveCockpit() {
        appModel.session.stop()
        Task { await dismissImmersiveSpace() }
    }

    private func cueColor(_ cue: LMCockpitCue) -> Color {
        switch cue.kind {
        case .phase, .altitude:
            return .white
        case .contact:
            return .yellow
        case .success:
            return .green
        case .warning:
            return .orange
        case .failure:
            return .red
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
