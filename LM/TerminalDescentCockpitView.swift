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
    @State private var showsValidationChecklist = false
    @State private var showsEyeAlignmentGuide = true
    @State private var trainingOverlayEnabled = true
    @State private var audioEnabled = true
    @State private var experienceDirector = LMCockpitExperienceDirector()
    @State private var activeCue: LMCockpitCue?
    @State private var cuePresentationTask: Task<Void, Never>?
    @State private var audioController = LMCockpitAudioController()
    @State private var validationRecorder = LMCockpitValidationRecorder()
    @GestureState private var acaGestureIsActive = false
    @GestureState private var rodGestureIsActive = false

    private let controlMapper = LMSpatialControlMapper()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.positron.LM",
        category: "TerminalDescentCockpit"
    )

    var body: some View {
        RealityView { content, attachments in
            content.add(station.commanderEntryAnchor)
            if let fdai = attachments.entity(for: "commander-fdai") {
                station.mountFDAI(fdai)
            }
            if let dskyDisplay = attachments.entity(for: "commander-dsky-display") {
                station.mountDSKYDisplay(dskyDisplay)
            }
            applySceneState()
        } update: { _, attachments in
            if let fdai = attachments.entity(for: "commander-fdai") {
                station.mountFDAI(fdai)
            }
            if let dskyDisplay = attachments.entity(for: "commander-dsky-display") {
                station.mountDSKYDisplay(dskyDisplay)
            }
            applySceneState()
        } attachments: {
            Attachment(id: "commander-fdai") {
                FDAIPanel(session: appModel.session)
                    .frame(width: 230)
                    .padding(8)
                    .background(Color.black.opacity(0.94))
            }
            Attachment(id: "commander-dsky-display") {
                DSKYPanel(
                    session: appModel.session,
                    showsScripts: false,
                    showsKeypad: false,
                    presentsFlightFace: true
                )
                .frame(width: 420, height: 250)
                .background(Color.black.opacity(0.94))
            }
        }
        .gesture(acaGesture)
        .simultaneousGesture(rodGesture)
        .simultaneousGesture(attitudeModeGesture)
        .simultaneousGesture(dskyGesture)
        .ornament(attachmentAnchor: .scene(.bottom)) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        restartExperience()
                    } label: {
                        Label("Restart P64", systemImage: "arrow.counterclockwise")
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
                        if !trainingOverlayEnabled {
                            showsEyeAlignmentGuide = false
                        }
                    } label: {
                        Label(
                            trainingOverlayEnabled ? "Training on" : "Training off",
                            systemImage: trainingOverlayEnabled ? "scope" : "scope"
                        )
                    }

                    Button {
                        showsEyeAlignmentGuide.toggle()
                    } label: {
                        Label(
                            showsEyeAlignmentGuide ? "Hide eye guide" : "Eye alignment",
                            systemImage: "viewfinder"
                        )
                    }
                    .disabled(!trainingOverlayEnabled)

                    Button {
                        showsValidationChecklist.toggle()
                    } label: {
                        Label(
                            "Validation \(validationRecorder.completedCount)/\(validationRecorder.totalCount)",
                            systemImage: validationRecorder.isComplete
                                ? "checkmark.seal.fill"
                                : "checklist"
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
                        Text(crewControlHint)
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
            } else if trainingOverlayEnabled && showsEyeAlignmentGuide {
                VStack(spacing: 4) {
                    Text("COMMANDER DESIGN EYE")
                        .font(.title3.weight(.bold).monospaced())
                    Text("Settle into position, then fine-adjust until the magenta and green LPD scales overlap.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassBackgroundEffect()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Commander design eye alignment")
                .accessibilityValue(
                    "Fine-adjust until the magenta and green Landing Point Designator scales overlap"
                )
            }
        }
        .ornament(attachmentAnchor: .scene(.trailing)) {
            if showsValidationChecklist {
                validationChecklist
            }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            appModel.session.setSceneActive(scenePhase == .active)
            audioController.isEnabled = audioEnabled
            audioController.start()
            if appModel.session.canStart {
                appModel.session.start(from: .p64Approach)
            }
            updateExperience()
            do {
                let artistCabinLoaded = try await station.loadArtistCabinIfAvailable()
                try await station.loadApollo11Terrain()
                terrainStatus = "LROC 2 m near · SLDEM 59 m / 237 m horizon · 0.5 m terminal synthesis"
                recordValidation { $0.observeTerrainLoaded() }
                logger.info("Apollo 11 LROC/SLDEM terrain loaded; artist cabin: \(artistCabinLoaded)")
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
                recordValidation { $0.observeDirectACA(input) }
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
                let position = controlMapper.rodPosition(
                    for: sceneLocation - origin,
                    along: LMCommanderStationGeometry.rodActuationAxis
                )
                recordValidation { $0.observeDirectROD(position) }
                applyROD(position)
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
                if selectsP66 {
                    recordValidation { $0.observeDirectAttitudeHold() }
                }
            }
    }

    private var dskyGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                guard let key = station.dskyKeyCode(for: value.entity) else { return }
                station.animateDSKYKeyPress(key)
                appModel.session.sendDSKYKey(key)
                recordValidation { $0.observeDirectDSKY(key) }
            }
    }

    private func applySceneState() {
        station.apply(appModel.session.vehicleState)
        station.setACAVisual(appModel.session.aca)
        station.setRODVisual(appModel.session.rodSwitchPosition)
        station.setAttitudeHoldVisual(appModel.session.attitudeMode == .attitudeHold)
        station.setLandingPointCalledAngle(
            appModel.session.landingPointLookAngleDegrees.map(Double.init),
            trainingOverlayVisible: trainingOverlayEnabled
                && appModel.session.isLandingPointDisplayActive
        )
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
        recordValidation { $0.observeDirectACARelease() }
    }

    private func releaseRODControl() {
        rodGestureOrigin = nil
        applyROD(.neutral)
        recordValidation { $0.observeDirectROD(.neutral) }
    }

    private func updateExperience() {
        let session = appModel.session
        audioController.update(
            commands: session.vehicleCommands,
            outcome: session.vehicleState?.flightOutcome
        )
        let cues = experienceDirector.consume(
            program: session.programNumber,
            landingPointDisplayActive: session.isLandingPointDisplayActive,
            altitudeMeters: session.vehicleState?.altitudeMeters,
            verticalSpeedMetersPerSecond: session.vehicleState?.verticalSpeedMetersPerSecond,
            downrangeSpeedMetersPerSecond: session.vehicleState?.velocityMetersPerSecond.y,
            outcome: session.vehicleState?.flightOutcome,
            hasSurfaceContact: session.vehicleState?.surfaceContact != nil
        )
        guard !cues.isEmpty else { return }
        recordValidation { $0.observe(events: cues.map(\.id)) }
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
        audioController.resetCallouts()
        experienceDirector.reset()
        validationRecorder.resetForRun()
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

    private var crewControlHint: String {
        if appModel.session.isLandingPointDisplayActive {
            let angle = appModel.session.landingPointLookAngleDegrees.map { "LPD \($0)°" }
                ?? "N64 LPD"
            if appModel.session.landingPointRedesignationTimeRemainingSeconds == 0 {
                return "\(angle) · redesignation window closed"
            }
            if appModel.session.isLandingPointRedesignationEnabled {
                return "\(angle) · ACA redesignation enabled"
            }
            return "\(angle) · press PRO to enable ACA redesignation"
        }
        return "Grip ACA · drag ROD · tap MODE CONTROL"
    }

    private var validationChecklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("HEADSET VALIDATION", systemImage: "visionpro")
                    .font(.headline.monospaced())
                Spacer()
                Text("\(validationRecorder.completedCount)/\(validationRecorder.totalCount)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(validationRecorder.isComplete ? .green : .secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                ForEach(
                    Array(LMCockpitValidationRecorder.Requirement.allCases.enumerated()),
                    id: \.element
                ) { index, requirement in
                    if index.isMultiple(of: 2) {
                        GridRow {
                            validationRequirement(requirement)
                            if index + 1 < LMCockpitValidationRecorder.Requirement.allCases.count {
                                validationRequirement(
                                    LMCockpitValidationRecorder.Requirement.allCases[index + 1]
                                )
                            }
                        }
                    }
                }
            }

            Button {
                recordValidation { $0.confirmComfort() }
            } label: {
                Label(
                    validationRecorder.completed.contains(.comfortConfirmed)
                        ? "Fit, reach, and comfort confirmed"
                        : "Confirm fit, reach, and comfort",
                    systemImage: validationRecorder.completed.contains(.comfortConfirmed)
                        ? "checkmark.circle.fill"
                        : "hand.tap"
                )
            }
            .disabled(validationRecorder.completed.contains(.comfortConfirmed))

            Text(validationFooter)
                .font(.caption2.monospaced())
                .foregroundStyle(validationRecorder.isComplete ? .green : .secondary)
        }
        .frame(width: 430)
        .padding(14)
        .glassBackgroundEffect()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Headset validation checklist")
    }

    private func validationRequirement(
        _ requirement: LMCockpitValidationRecorder.Requirement
    ) -> some View {
        let isComplete = validationRecorder.completed.contains(requirement)
        return Label(
            requirement.title,
            systemImage: isComplete ? "checkmark.circle.fill" : "circle"
        )
        .font(.caption.monospaced())
        .foregroundStyle(isComplete ? .green : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var validationFooter: String {
        if validationRecorder.isComplete {
            return "PASS · on-head controls, comfort, and soft landing observed"
        }
        switch validationRecorder.terminalResult {
        case .hardLanding:
            return "RUN ENDED · hard landing · restart P64"
        case .crashed:
            return "RUN ENDED · vehicle lost · restart P64"
        default:
            return "Direct spatial gestures only · fallback controls excluded"
        }
    }

    private func recordValidation(
        _ update: (inout LMCockpitValidationRecorder) -> Void
    ) {
        let previous = validationRecorder.completed
        update(&validationRecorder)
        let additions = validationRecorder.completed.subtracting(previous)
        for requirement in additions.sorted(by: { $0.rawValue < $1.rawValue }) {
            logger.notice("Validation gate: \(requirement.rawValue, privacy: .public)")
        }
        if validationRecorder.isComplete && previous.count != validationRecorder.totalCount {
            logger.notice("Headset validation pass: \(validationRecorder.summary(), privacy: .public)")
        }
    }
}

#Preview(immersionStyle: .full) {
    TerminalDescentCockpitView()
        .environment(MainMenuViewModel())
}
