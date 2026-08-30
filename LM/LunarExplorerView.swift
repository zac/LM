import RealityKit
import SwiftUI

struct LunarExplorerView: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @State private var scene = LunarExplorerScene()
    @State private var orbitStart: SIMD2<Double>?
    @State private var panStart: SIMD2<Double>?
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
    }

    private func orbitGesture(_ session: LunarExplorerSession) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(scene.interactionSurface)
            .onChanged { value in
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
            }
    }

    private func zoomGesture(_ session: LunarExplorerSession) -> some Gesture {
        MagnifyGesture()
            .targetedToEntity(scene.interactionSurface)
            .onChanged { value in
                if zoomStartMetersAcross == nil {
                    zoomStartMetersAcross = session.metersAcross
                }
                guard let start = zoomStartMetersAcross else { return }
                session.zoom(by: Double(value.magnification), from: start)
            }
            .onEnded { _ in
                zoomStartMetersAcross = nil
            }
    }
}

struct LunarExplorerControls: View {
    @Bindable var session: LunarExplorerSession
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lunar Explorer")
                        .font(.title2.weight(.semibold))
                    Text("Apollo 11 site, production terrain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: close)
            }

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
        .padding(20)
        .frame(width: 390)
        .glassBackgroundEffect()
    }

    private var diagnosticRows: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            diagnosticRow("State", session.diagnostics.loadMessage)
            diagnosticRow("Source", session.diagnostics.sourceDescription)
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
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        LunarExplorerControls(session: appModel.lunarExplorerSession) {
            Task { @MainActor in
                await dismissImmersiveSpace()
                dismissWindow(id: appModel.lunarExplorerControlsWindowID)
            }
        }
    }
}

#Preview(immersionStyle: .full) {
    LunarExplorerView()
        .environment(MainMenuViewModel())
}
