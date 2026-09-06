import OSLog
import RealityKit
import SwiftUI
import UIKit

struct LunarExplorerView: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @State private var scene = LunarExplorerScene()
    @State private var orbitStart: SIMD2<Double>?
    @State private var panStart: SIMD2<Double>?
    @State private var globeDragStart: LMSelenographicCoordinate?
    @State private var zoomStartMetersAcross: Double?

    var body: some View {
        @Bindable var explorer = appModel.lunarExplorerSession

        RealityView { content in
            content.add(scene.root)
            scene.loadIfNeeded(session: explorer)
        } update: { _ in
            scene.apply(explorer)
        }
        .gesture(orbitGesture(explorer))
        .simultaneousGesture(zoomGesture(explorer))
        .onAppear {
            LunarExplorerPerformanceProbe.shared.start(
                arguments: ProcessInfo.processInfo.arguments
            )
        }
        .onDisappear {
            LunarExplorerPerformanceProbe.shared.stop()
            if explorer.isExplorerExperience { explorer.cancelNavigation() }
        }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--lunar-explorer-profile-journey") {
                await LunarExplorerExperienceProbe.run(explorer)
                return
            }
            guard arguments.contains("--lunar-explorer-capture") else { return }
            do {
                if let value = arguments.first(where: { $0.hasPrefix("--lunar-explorer-fly-to=") }),
                   let coordinate = LMLunarNavigation.parse(String(value.dropFirst("--lunar-explorer-fly-to=".count))) {
                    try await waitForSettledTerrain(explorer)
                    explorer.fly(to: coordinate)
                }
                if arguments.contains("--lunar-explorer-transition-probe") {
                    try await waitForSettledTerrain(explorer)
                    for destination in [(35.0, 2.0, 8.0), (35.0, 249.0, 700.0), (0.0, 2.0, 8.0)] {
                        let heading = explorer.headingDegrees
                        let altitude = explorer.altitudeMeters
                        let width = explorer.metersAcross
                        let logger = Logger(subsystem: "io.positron.LM", category: "TerrainTransition")
                        logger.info("Transition probe begin heading=\(destination.0) altitude=\(destination.1)m width=\(destination.2)m")
                        for step in 1...60 {
                            let t = Double(step) / 60
                            let weight = t * t * (3 - 2 * t)
                            explorer.headingDegrees = heading + (destination.0 - heading) * weight
                            explorer.altitudeMeters = exp(log(altitude) * (1 - weight) + log(destination.1) * weight)
                            explorer.metersAcross = exp(log(width) * (1 - weight) + log(destination.2) * weight)
                            try await Task.sleep(for: .milliseconds(33))
                        }
                        try await waitForSettledTerrain(explorer)
                        logger.info("Transition probe settled heading=\(destination.0) altitude=\(destination.1)m width=\(destination.2)m")
                    }
                }
                if arguments.contains("--lunar-explorer-contact-probe") {
                    try await waitForSettledTerrain(explorer)
                    explorer.testLanding()
                }
            } catch { /* Closing the scene cancels the capture sequence. */ }

        }
    }

    private func waitForSettledTerrain(_ session: LunarExplorerSession) async throws {
        for _ in 0..<600 {
            if !session.navigationInProgress && session.diagnostics.loadMessage == "Lunar terrain ready" {
                let prefix = "--lunar-explorer-transition-hold-seconds="
                let hold = ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }
                    .flatMap { Double($0.dropFirst(prefix.count)) } ?? 100
                try await Task.sleep(for: .seconds(hold.isFinite ? max(5, hold) : 100))
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw CancellationError()
    }

    private func orbitGesture(_ session: LunarExplorerSession) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(scene.interactionSurface)
            .onChanged { value in
                guard !session.landingRunning, !session.navigationInProgress else { return }
                if session.isBrowsingGlobe {
                    if globeDragStart == nil { globeDragStart = session.browseCoordinate }
                    if let start = globeDragStart {
                        session.rotateGlobe(from: start, horizontal: Double(value.translation.width),
                                            vertical: Double(value.translation.height))
                    }
                    return
                }
                switch session.navigationMode {
                case .orbit:
                    panStart = nil
                    if orbitStart == nil {
                        orbitStart = SIMD2(session.headingDegrees, session.tiltDegrees)
                    }
                    guard let start = orbitStart else { return }
                    session.setOrbit(
                        headingDegrees: start.x + Double(value.translation.width) * 0.22,
                        tiltDegrees: start.y - Double(value.translation.height) * 0.18
                    )
                case .pan:
                    orbitStart = nil
                    if panStart == nil {
                        panStart = SIMD2(
                            session.focusNorthOffsetMeters,
                            session.focusEastOffsetMeters
                        )
                    }
                    guard let start = panStart else { return }
                    let metersPerPoint = session.metersAcross / 900
                    session.pan(
                        northMeters: start.x
                            + Double(value.translation.height) * metersPerPoint,
                        eastMeters: start.y
                            - Double(value.translation.width) * metersPerPoint
                    )
                }
            }
            .onEnded { _ in
                orbitStart = nil
                panStart = nil
                globeDragStart = nil
            }
    }

    private func zoomGesture(_ session: LunarExplorerSession) -> some Gesture {
        MagnifyGesture()
            .targetedToEntity(scene.interactionSurface)
            .onChanged { value in
                guard !session.landingRunning, !session.navigationInProgress else { return }
                if zoomStartMetersAcross == nil {
                    zoomStartMetersAcross = session.metersAcross
                }
                guard let start = zoomStartMetersAcross else { return }
                if session.isExplorerExperience {
                    session.exploreZoom(by: Double(value.magnification), from: start)
                } else {
                    session.zoom(by: Double(value.magnification), from: start)
                }
            }
            .onEnded { _ in
                zoomStartMetersAcross = nil
            }
    }
}

struct LunarExplorerInspector: View {
    @Bindable var session: LunarExplorerSession
    let close: () -> Void
    var landInCockpit: (() -> Void)? = nil
    @State private var coordinateEntry = ""
    @State private var search = ""
    @State private var navigationExpanded = true
    @State private var places = [LMLunarPOICatalog.Place]()

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lunar Explorer")
                        .font(.title2.weight(.semibold))
                    Text("Explore the Moon at any coordinate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: close)
            }

            Group {
            DisclosureGroup("Navigate", isExpanded: $navigationExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if let coordinate = session.currentCoordinate {
                        HStack {
                            Text(String(format: "%.6f, %.6f", coordinate.latitudeDegrees, coordinate.longitudeDegrees))
                                .font(.caption.monospacedDigit())
                            Button {
                                UIPasteboard.general.string = String(format: "%.6f, %.6f", coordinate.latitudeDegrees, coordinate.longitudeDegrees)
                            } label: { Image(systemName: "doc.on.doc") }
                            .accessibilityLabel("Copy coordinates")
                        }
                    }
                    if !session.usesBundledSite, let floor = session.diagnostics.measuredFloorMeters {
                        Text("Elevation posts are about \(distance(floor)) apart. Finer craters are modeled.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Latitude, longitude (N/E positive)", text: $coordinateEntry)
                        Button("Go") {
                            if let coordinate = LMLunarNavigation.parse(coordinateEntry) { session.fly(to: coordinate) }
                            else { session.navigationMessage = "Enter latitude −90…90, longitude −180…180." }
                        }
                    }
                    HStack {
                        Button("Back") { session.back() }.disabled(session.navigationHistory.isEmpty)
                        Button("Apollo 11") {
                            if let coordinate = try? LMTerrainManifest.load().landingOriginCoordinate { session.fly(to: coordinate) }
                        }
                    }
                    TextField("Search places", text: $search)
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(Array(Set(places.map(\.category))).sorted(), id: \.self) { category in
                                let matches = places.filter { $0.category == category && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
                                if !matches.isEmpty { Text(category.capitalized).font(.caption.weight(.semibold)) }
                                ForEach(matches) { place in
                                HStack {
                                    Button(place.name) { session.fly(to: place.coordinate, altitude: place.suggestedAltitudeMeters, heading: place.suggestedHeadingDegrees) }.help(place.blurb)
                                    Spacer()
                                    Link(destination: place.sourceURL) { Image(systemName: "info.circle") }
                                }
                                }
                            }
                        }
                    }.frame(height: 130)
                    if !session.navigationMessage.isEmpty { Text(session.navigationMessage).font(.caption) }
                    Toggle("Use cached terrain only", isOn: $session.regionOffline)
                    HStack {
                        Button("Download this region") { session.downloadRegion() }.disabled(session.isDownloading)
                        Button("Reload") {
                            if let coordinate = session.currentCoordinate { session.fly(to: coordinate, remember: false) }
                        }
                        if session.isDownloading { Button("Pause") { session.cancelDownload() } }
                    }
                    Text(session.downloadMessage).font(.caption)
                    if !session.usesBundledSite {
                        Button("Test landing here") { session.testLanding() }.disabled(session.landingRunning)
                        if let landInCockpit {
                            Button(session.usesBundledSite ? "Fly Apollo 11 in cockpit" : "Land here in cockpit", action: landInCockpit)
                                .disabled(session.navigationInProgress || session.currentCoordinate == nil)
                        }
                        Text(session.landingMessage).font(.caption)
                        Text("Local gear drop without mission guidance.").font(.caption2).foregroundStyle(.secondary)
                    }
                }.disabled(session.landingRunning)
            }
            .task { places = (try? LMLunarPOICatalog.load().features) ?? [] }

            Picker("View", selection: Binding(
                get: { session.selectedPreset },
                set: { session.select($0) }
            )) {
                ForEach(LunarExplorerSession.Preset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.menu)

            Picker("Navigation", selection: $session.navigationMode) {
                ForEach(LunarExplorerSession.NavigationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Appearance", selection: $session.detailMode) {
                ForEach(LMTerrainDetailMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if !session.usesBundledSite {
                Text("Global terrain currently uses Procedural appearance.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Toggle("Mission shadows", isOn: $session.missionShadowsEnabled)

            Divider()
            lightingControls

            LabeledContent("Virtual altitude") {
                Text(distance(session.altitudeMeters))
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { session.logarithmicAltitude },
                    set: { session.logarithmicAltitude = $0 }
                ),
                in: log10(LunarExplorerSession.minimumAltitudeMeters)...log10(
                    LunarExplorerSession.maximumAltitudeMeters
                )
            )

            LabeledContent("View width") {
                Text(distance(session.metersAcross))
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { session.logarithmicMetersAcross },
                    set: { session.logarithmicMetersAcross = $0 }
                ),
                in: log10(LunarExplorerSession.minimumMetersAcross)...log10(
                    LunarExplorerSession.maximumMetersAcross
                )
            )

            HStack {
                Button("Fit altitude") { session.fitViewToAltitude() }
                Button("Reset view") { session.resetView() }
            }

            Picker("Focus", selection: Binding(
                get: { session.selectedFocus },
                set: { session.focus(on: $0) }
            )) {
                ForEach(LunarExplorerSession.Focus.allCases) { focus in
                    Text(focus.title).tag(focus)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Show diagnostics", isOn: $session.diagnosticsVisible)

            if session.diagnosticsVisible {
                Divider()
                diagnosticRows
            }

            Text(navigationHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .disabled(session.landingRunning || session.navigationInProgress)
        }
        }
        .frame(maxHeight: 900)
        .padding(20)
        .frame(width: 390)
        .glassBackgroundEffect()
    }

    /// Time-driven mission lighting. The date sets the instant and the scrub
    /// sweeps a lunation either side of it, so the terminator can be walked
    /// across the site and returned to the landing in one tap.
    private var lightingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sun")
                    .font(.headline)
                Spacer()
                Button("Apollo 11 landing") {
                    session.sunAnchorDate = LunarExplorerSession.apollo11TouchdownUTC
                    session.sunOffsetHours = 0
                }
                .font(.caption)
            }

            DatePicker(
                "Date (UTC)",
                selection: $session.sunAnchorDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)

            LabeledContent("Time offset") {
                Text(sunOffsetCaption)
                    .monospacedDigit()
            }
            Slider(value: $session.sunOffsetHours, in: Self.sunScrubRange)

            LabeledContent("Sun") {
                Text(sunAngleCaption)
                    .monospacedDigit()
            }

            Picker("Tone", selection: $session.presentationGrade) {
                ForEach(LMTerrainPresentationGrade.allCases) { grade in
                    Text(grade.title).tag(grade)
                }
            }
            .pickerStyle(.segmented)

            if session.presentationGrade == .photographic {
                LabeledContent("Earthshine") {
                    Text(earthshineCaption)
                        .monospacedDigit()
                }
            }
        }
    }

    private static let sunScrubRange =
        -LunarExplorerSession.sunScrubRangeHours
            ... LunarExplorerSession.sunScrubRangeHours

    private var sunOffsetCaption: String {
        let hours = session.sunOffsetHours
        if abs(hours) < 1 {
            return String(format: "%+.0f min", hours * 60)
        }
        if abs(hours) < 48 {
            return String(format: "%+.1f h", hours)
        }
        return String(format: "%+.1f days", hours / 24)
    }

    private var sunAngleCaption: String {
        guard let azimuth = session.diagnostics.sunAzimuthDegrees,
              let elevation = session.diagnostics.sunElevationDegrees else {
            return "pending"
        }
        return String(
            format: "az %.1f°  el %+.1f°%@",
            azimuth,
            elevation,
            elevation < 0 ? "  (night)" : ""
        )
    }

    private var earthshineCaption: String {
        guard let fraction = session.diagnostics.earthIlluminatedFraction else {
            return "pending"
        }
        // Earth and Moon show each other opposite phases, so a full Earth
        // hangs over a lunar night.
        return String(format: "Earth %.0f%% lit", fraction * 100)
    }

    private var diagnosticRows: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            diagnosticRow("State", session.diagnostics.loadMessage)
            diagnosticRow("Source", session.diagnostics.sourceDescription)
            diagnosticRow(
                "Measured floor",
                session.diagnostics.measuredFloorMeters.map(distance) ?? "pending"
            )
            diagnosticRow("Appearance", session.detailMode.title)
            diagnosticRow("Globe tier", session.diagnostics.globeTierState)
            diagnosticRow(
                "Tiles",
                "\(session.diagnostics.activeTileCount) active / "
                    + "\(session.diagnostics.requestedTileCount) requested"
            )
            diagnosticRow(
                "Finest mesh",
                session.diagnostics.finestSpacingMeters.map {
                    String(format: "%.3f m", $0)
                } ?? "measured only"
            )
            diagnosticRow(
                "Last build",
                session.diagnostics.latestGenerationMilliseconds.map { "\($0) ms" }
                    ?? "none"
            )
            diagnosticRow(
                "Build split",
                session.diagnostics.latestGenerationMetrics.map {
                    "mesh \($0.meshMilliseconds) / bake \($0.detailMilliseconds) / "
                        + "GPU \($0.realizationMilliseconds) ms"
                } ?? "none"
            )
            diagnosticRow(
                "Detail source",
                session.diagnostics.latestGenerationMetrics.map {
                    "\($0.detailModelID) / "
                        + "\($0.detailCacheHit ? "cache" : "generated")"
                } ?? "none"
            )
            diagnosticRow(
                "Focus offset",
                String(
                    format: "N %.0f m  E %.0f m",
                    session.focusNorthOffsetMeters,
                    session.focusEastOffsetMeters
                )
            )
        }
        .font(.caption)
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(2)
        }
    }

    private func distance(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km", meters / 1_000)
        }
        if meters >= 10 {
            return String(format: "%.0f m", meters)
        }
        return String(format: "%.1f m", meters)
    }

    private var navigationHelp: String {
        switch session.navigationMode {
        case .orbit:
            "Drag to orbit. Pinch to zoom without changing LOD."
        case .pan:
            "Drag to pan across the site. Pinch to zoom without changing LOD."
        }
    }
}

struct LunarExplorerControlsWindow: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var didRestoreAutomatedSpace = false

    var body: some View {
        LunarExplorerControls(session: appModel.lunarExplorerSession) {
            Task { @MainActor in
                await dismissImmersiveSpace()
                dismissWindow(id: appModel.lunarExplorerControlsWindowID)
            }
        } landInCockpit: {
            appModel.cockpitCoordinate = appModel.lunarExplorerSession.usesBundledSite ? nil
                : appModel.lunarExplorerSession.currentCoordinate
            appModel.session.stop()
            if appModel.cockpitCoordinate == nil { appModel.session.selectLandingSite(nil) }
            Task { @MainActor in
                await dismissImmersiveSpace()
                let result = await openImmersiveSpace(id: appModel.cockpitSpaceID)
                if case .opened = result { dismissWindow(id: appModel.lunarExplorerControlsWindowID) }
            }
        }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--lunar-explorer"),
                  !didRestoreAutomatedSpace,
                  appModel.lunarExplorerSpaceState == .closed else { return }
            didRestoreAutomatedSpace = true
            appModel.lunarExplorerSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.lunarExplorerSpaceID) {
            case .opened:
                if !LunarExplorerSession.presentsControls(arguments: arguments) {
                    dismissWindow(id: appModel.lunarExplorerControlsWindowID)
                }
            case .userCancelled, .error:
                fallthrough
            @unknown default:
                appModel.lunarExplorerSpaceState = .closed
            }
        }
    }
}

#Preview(immersionStyle: .full) {
    LunarExplorerView()
        .environment(MainMenuViewModel())
}

#Preview("Navigation controls") {
    LunarExplorerControls(session: LunarExplorerSession(), close: {})
}
