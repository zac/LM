import OSLog
import SwiftUI
import UIKit

/// Window navigation and scene controls have separate homes.
struct LunarExplorerControls: View {
    @Bindable var session: LunarExplorerSession
    var close: () -> Void
    var landInCockpit: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var tab = "explore"
    @State private var search = ""
    @State private var savedSearch = ""
    @State private var filter = "All"
    @State private var showsSun = false
    @State private var showsPlacement = false
    @State private var showsInspector = false
    @State private var showsSave = false
    @State private var savedName = ""
    @State private var infoPlace: LMLunarPOICatalog.Place?
    @State private var copied = false

    private var selected: LMLunarPOICatalog.Place? { session.selectedMarkerPlace }
    private var matches: [LMLunarPOICatalog.Place] {
        session.catalogPlaces.filter {
            (filter != "Landings" || $0.category == "apollo")
                && (filter != "Craters" || $0.category == "crater")
                && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }.sorted {
            let featured = ["apollo-11", "apollo-17", "6163", "1296"]
            let a = featured.firstIndex(of: $0.id) ?? 99
            let b = featured.firstIndex(of: $1.id) ?? 99
            return a == b ? $0.name < $1.name : a < b
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                exploreContent
                    .navigationTitle("Moon")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { tab = "settings" } label: { Label("Settings", systemImage: "gearshape") }
                                .help("Settings").hoverEffect()
                        }
                    }
            }
            .tabItem { Label("Explore", systemImage: "moon.fill") }.tag("explore")

            NavigationStack {
                savedContent.navigationTitle("Saved")
                    .searchable(text: $savedSearch, prompt: "Search saved views")
            }
            .tabItem { Label("Saved", systemImage: "bookmark") }.tag("saved")

            NavigationStack { settingsContent.navigationTitle("Settings") }
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag("settings")
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 720 : 560,
               height: dynamicTypeSize.isAccessibilitySize ? 800 : 760)
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) { sceneControls }
        .ornament(visibility: session.isBrowsingGlobe ? .hidden : .visible,
                  attachmentAnchor: .scene(.top), contentAlignment: .bottom) {
            Button { session.returnToGlobeGently() } label: {
                Label("Exit surface", systemImage: "arrow.down.right.and.arrow.up.left")
                    .frame(minHeight: 60)
            }
            .buttonStyle(.borderless).padding(.horizontal, 20)
            .glassBackgroundEffect(in: .capsule)
            .help("Return to the globe in your surroundings").hoverEffect()
            .disabled(session.landingRunning)
        }
        .alert("Save view", isPresented: $showsSave) {
            TextField("Name", text: $savedName)
            Button("Save") { session.library.save(session.savedView(named: savedName)) }
                .disabled(savedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Remembers this location, camera and sunlight.") }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--lunar-explorer-profile-browser") else { return }
            let logger = Logger(subsystem: "io.positron.LM", category: "MoonBrowser")
            func stage(_ name: String) async throws {
                logger.info("Moon browser stage=\(name, privacy: .public)")
                try await Task.sleep(for: .seconds(25))
            }
            do {
                for _ in 0..<240 where session.diagnostics.globeTierState == "pending" {
                    try await Task.sleep(for: .milliseconds(500))
                }
                guard let place = session.catalogPlaces.first(where: { $0.id == "apollo-11" }) else { return }
                session.previewPlace(place)
                if ProcessInfo.processInfo.arguments.contains("--lunar-explorer-profile-browser-lighting") {
                    showsSun = true
                    try await stage("lighting")
                    showsSun = false
                    logger.info("Moon browser stage=passed")
                    return
                }
                try await stage("selected")
                infoPlace = place
                try await stage("mission")
                infoPlace = nil
                tab = "saved"
                try await stage("saved")
                tab = "settings"
                try await stage("settings")
                showsPlacement = true
                try await stage("placement")
                showsPlacement = false
                showsSun = true
                try await stage("lighting")
                showsSun = false
                tab = "explore"
                session.browseCoordinate = .init(latitudeDegrees: -place.latitude,
                                                longitudeDegrees: place.longitude - 180)
                try await stage("far-side")
                session.previewPlace(place)
                logger.info("Moon browser stage=passed")
            } catch {}
        }
        .sheet(item: $infoPlace) { LunarExplorerPlaceDetails(place: $0) }
        .sheet(isPresented: $showsSun) {
            NavigationStack {
                LunarExplorerSunPanel(session: session)
                    .navigationTitle("Lighting")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsSun = false }.hoverEffect()
                        }
                    }
            }.frame(width: dynamicTypeSize.isAccessibilitySize ? 720 : 560, height: 760)
        }
        .sheet(isPresented: $showsInspector) {
            LunarExplorerInspector(session: session, close: { showsInspector = false }, landInCockpit: landInCockpit)
        }
    }

    private var exploreContent: some View {
        Group {
            if session.isBrowsingGlobe {
                VStack(spacing: 0) {
                    Picker("Places", selection: $filter) {
                        ForEach(["All", "Landings", "Craters"], id: \.self) { Text($0) }
                    }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
                    List(selection: Binding<String?>(
                        get: { session.selectedPlaceID },
                        set: { id in
                            if let place = session.catalogPlaces.first(where: { $0.id == id }) { session.previewPlace(place) }
                        })) {
                        if dynamicTypeSize.isAccessibilitySize { Section { destinationCard } }
                        if LMLunarNavigation.parse(search) != nil {
                            Button(action: openCoordinate) { Label("Show coordinate", systemImage: "mappin.and.ellipse") }
                                .frame(minHeight: 60).hoverEffect()
                        }
                        Section("Places") {
                            ForEach(matches) { place in
                                Label {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.name).font(.body.weight(.medium))
                                        Text(place.category == "apollo" ? "Landing site" : place.category.capitalized)
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: place.category == "apollo" ? "flag.fill" : "circle.dotted")
                                }
                                .frame(minHeight: 60).tag(place.id)
                                .accessibilityIdentifier("moon.place." + place.id)
                                .hoverEffect()
                            }
                        }
                        if matches.isEmpty && LMLunarNavigation.parse(search) == nil {
                            ContentUnavailableView.search(text: search)
                        }
                    }.listStyle(.plain)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Divider()
                        destinationCard.padding(24)
                    }
                }
                .searchable(text: $search, prompt: "Places or latitude, longitude")
                .onSubmit(of: .search, openCoordinate)
            } else {
                List {
                    Section {
                        Label(distance(session.altitudeMeters) + " above terrain", systemImage: "arrow.up.and.down")
                        Picker("Drag action", selection: $session.navigationMode) {
                            Text("Rotate").tag(LunarExplorerSession.NavigationMode.orbit)
                            Text("Move").tag(LunarExplorerSession.NavigationMode.pan)
                        }.pickerStyle(.segmented)
                        Text("Drag to \(session.navigationMode == .orbit ? "rotate" : "move"). Pinch to explore closer.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button { session.back() } label: { Label("Previous location", systemImage: "arrow.uturn.backward") }
                            .disabled(session.navigationHistory.isEmpty || session.navigationInProgress).hoverEffect()
                    }
                    Section { destinationCard }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if session.navigationInProgress {
                HStack { ProgressView(); Text(session.navigationMessage) }.padding()
            } else if !session.navigationMessage.isEmpty {
                Text(session.navigationMessage).font(.footnote).padding()
            }
        }
    }

    private var sceneControls: some View {
        HStack(spacing: 16) {
            Picker("View mode", selection: Binding(
                get: { session.isBrowsingGlobe ? "globe" : "surface" },
                set: { session.setExplorerMode($0) })) {
                    Text("Globe").tag("globe")
                    Text("Surface").tag("surface")
                }
                .pickerStyle(.segmented).frame(minHeight: 60)
                .help("Enter immersive terrain")
                .accessibilityIdentifier("moon.mode")
            Button { showsSun = true } label: {
                Label("Lighting", systemImage: "sun.max")
                    .labelStyle(.iconOnly).frame(width: 60, height: 60)
            }
            .buttonStyle(.borderless).help("Lighting and terminator").hoverEffect()
        }
        .padding(12)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 620 : 440)
        .glassBackgroundEffect()
        .disabled(session.navigationInProgress || session.landingRunning)
    }

    private var savedContent: some View {
        List {
            Section {
                Button(action: saveView) { Label("Save current view", systemImage: "bookmark.badge.plus") }
                    .frame(minHeight: 60).disabled(session.navigationInProgress).hoverEffect()
            }
            if session.library.views.isEmpty {
                ContentUnavailableView("Keep a view", systemImage: "bookmark",
                    description: Text("Save a location, camera and sunlight to return to later."))
            }
            ForEach(session.library.views.filter { savedSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(savedSearch) }) { view in
                Button { session.restore(view); tab = "explore" } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(view.name)
                        Text(view.isGlobe ? "Globe" : "Surface").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(minHeight: 60)
                }
                .hoverEffect()
                .contextMenu { Button("Delete saved view", role: .destructive) { session.library.remove(view.id) } }
            }
            if !session.library.message.isEmpty { Text(session.library.message).font(.footnote) }
        }
    }

    private var settingsContent: some View {
        List {
            Section("Globe") {
                Button { showsPlacement = true } label: { Label("Position globe", systemImage: "move.3d") }
                    .help("Adjust globe position and distance").hoverEffect()
                    .disabled(!session.isBrowsingGlobe)
                    .popover(isPresented: $showsPlacement) { LunarExplorerPlacementPanel(session: session) }
                Toggle("Rotate automatically", isOn: $session.automaticallyRotatesGlobe)
                    .disabled(session.reduceMotion)
                Text(session.reduceMotion ? "Automatic rotation is off with Reduce Motion." :
                    "Rotation pauses while you drag or scale the globe. Turn it off here to hold a view.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("View scale") {
                // A native adjustable control remains available to people who cannot pinch.
                Slider(value: Binding(
                    get: { log(session.metersAcross) },
                    set: { session.exploreZoom(by: session.metersAcross / exp($0), from: session.metersAcross) }),
                    in: session.isBrowsingGlobe ? log(3_400_000)...log(5_000_000) : log(8)...log(5_000_000))
                    .accessibilityLabel("View width")
                Text(distance(session.metersAcross) + " across").monospacedDigit()
            }
            Section {
                Button { showsInspector = true } label: { Label("Terrain inspector", systemImage: "slider.horizontal.3") }
                    .hoverEffect().disabled(session.isBrowsingGlobe || session.navigationInProgress)
            }
        }.disabled(session.landingRunning || session.navigationInProgress)
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selected?.name ?? "Selected location").font(.title3.weight(.semibold))
                Spacer()
                if let selected {
                    Button { infoPlace = selected } label: {
                        Label("About this place", systemImage: "info.circle").labelStyle(.iconOnly)
                            .frame(width: 60, height: 60)
                    }.buttonStyle(.borderless).help("About " + selected.name).hoverEffect()
                }
            }
            Button {
                let c = session.displayedCoordinate
                UIPasteboard.general.string = String(format: "%.6f, %.6f", c.latitudeDegrees, c.longitudeDegrees)
                copied = true
            } label: {
                Label(copied ? "Copied coordinates" : coordinateCaption, systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(minHeight: 60, alignment: .leading)
            }
            .buttonStyle(.borderless).help("Copy latitude and longitude").hoverEffect()
            .onChange(of: coordinateCaption) { copied = false }
            if let selected, session.isBrowsingGlobe {
                Text(selected.category == "apollo" ? "Explore this Apollo landing site and the surrounding terrain." : "Explore this lunar " + selected.category + " and its surroundings.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: saveView) { Label("Save view", systemImage: "bookmark.badge.plus") }
                .help("Save this location, camera and sunlight").hoverEffect()
            if !session.isBrowsingGlobe, let floor = session.diagnostics.measuredFloorMeters {
                Text("Elevation measured every \(distance(floor)). Finer terrain is modeled.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.disabled(session.landingRunning || session.navigationInProgress)
    }

    private var coordinateCaption: String {
        let c = session.displayedCoordinate
        return String(format: "%.4f° %@, %.4f° %@", abs(c.latitudeDegrees),
            c.latitudeDegrees < 0 ? "S" : "N", abs(c.longitudeDegrees), c.longitudeDegrees < 0 ? "W" : "E")
    }

    private func saveView() { savedName = selected?.name ?? "Moon view"; showsSave = true }
    private func openCoordinate() {
        guard let coordinate = LMLunarNavigation.parse(search) else { return }
        session.returnToGlobe()
        session.browseCoordinate = coordinate
        session.selectedPlaceID = nil
    }
    private func distance(_ value: Double) -> String {
        value >= 1_000 ? String(format: "%.1f km", value / 1_000) : String(format: "%.1f m", value)
    }
}

private struct LunarExplorerSunPanel: View {
    @Bindable var session: LunarExplorerSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Button("Daylight here") { session.showDaylight() }
            DatePicker("Date and time (UTC)", selection: $session.sunAnchorDate,
                       displayedComponents: [.date, .hourAndMinute])
                .environment(\.timeZone, .gmt)
            HStack {
                Button("−6 hours") { session.sunOffsetHours = max(-360, session.sunOffsetHours - 6) }
                Spacer()
                Text(String(format: "%+.1f days", session.sunOffsetHours / 24)).monospacedDigit()
                Spacer()
                Button("+6 hours") { session.sunOffsetHours = min(360, session.sunOffsetHours + 6) }
            }
            Slider(value: $session.sunOffsetHours, in: -360...360)
                .accessibilityLabel("Sunlight time offset")
            Text("Move through a lunar day to reveal crater rims and shadows.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("Now") { session.sunAnchorDate = Date(); session.sunOffsetHours = 0 }
                Spacer()
                Button("Apollo 11 landing") {
                    session.sunAnchorDate = LunarExplorerSession.apollo11TouchdownUTC
                    session.sunOffsetHours = 0
                }
            }
            Picker("Tone", selection: $session.presentationGrade) {
                ForEach(LMTerrainPresentationGrade.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
        }.padding(24)
        }.frame(width: dynamicTypeSize.isAccessibilitySize ? 680 : 460, height: 560)
    }
}

#Preview("Moon browser") {
    let session = LunarExplorerSession()
    session.configure(arguments: [])
    return LunarExplorerControls(session: session, close: {})
}
