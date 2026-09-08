import LunarMap
import OSLog
import SwiftUI
import UIKit

/// Window navigation and scene controls have separate homes.
public struct LunarExplorerControls: View {
    @Bindable var session: LunarExplorerSession
    var close: () -> Void
    var landInCockpit: (() -> Void)? = nil

    public init(session: LunarExplorerSession, close: @escaping () -> Void,
                landInCockpit: (() -> Void)? = nil) {
        self.session = session
        self.close = close
        self.landInCockpit = landInCockpit
    }

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

    public var body: some View {
        TabView(selection: $tab) {
            exploreContent
            .tabItem { Label("Explore", systemImage: "moon.fill") }.tag("explore")

            NavigationStack {
                savedContent.navigationTitle("Saved")
            }
            .tabItem { Label("Saved", systemImage: "bookmark") }.tag("saved")

            NavigationStack { settingsContent.navigationTitle("Settings") }
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag("settings")
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 720 : 560,
               height: 800)
        // A quiet tint improves text contrast in bright surroundings; the system still supplies the glass.
        .background(.black.opacity(0.22), in: ContainerRelativeShape())
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) { sceneControls }
        .alert("Save view", isPresented: $showsSave) {
            TextField("Name", text: $savedName)
            Button("Save") { session.library.save(session.savedView(named: savedName)) }
                .disabled(savedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Remembers this location, camera and sunlight.") }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--lunar-explorer-profile-browser") else { return }
            let logger = Logger(subsystem: LunarMapLog.subsystem, category: "MoonBrowser")
            let originalLibrary = session.library
            let captureDomain = "MoonBrowserCapture." + UUID().uuidString
            guard let captureDefaults = UserDefaults(suiteName: captureDomain) else { return }
            session.library = LunarExplorerLibrary(defaults: captureDefaults)
            defer {
                session.library = originalLibrary
                captureDefaults.removePersistentDomain(forName: captureDomain)
            }
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
                if ProcessInfo.processInfo.arguments.contains("--lunar-explorer-profile-browser-search") {
                    search = "Tycho"
                    try await stage("search")
                    search = "No such place"
                    try await stage("empty")
                    search = "12.5, -45.25"
                    try await stage("coordinate")
                    openCoordinate()
                    search = ""
                    try await stage("coordinate-selected")
                    session.previewPlace(place)
                    logger.info("Moon browser stage=passed")
                    return
                }
                if ProcessInfo.processInfo.arguments.contains("--lunar-explorer-profile-browser-lighting") {
                    showsSun = true
                    try await stage("lighting")
                    showsSun = false
                    logger.info("Moon browser stage=passed")
                    return
                }
                try await stage("selected")
                if ProcessInfo.processInfo.arguments.contains("--lunar-explorer-profile-browser-selected") {
                    logger.info("Moon browser stage=passed")
                    return
                }
                infoPlace = place
                try await stage("mission")
                infoPlace = nil
                tab = "saved"
                try await stage("saved")
                session.library.save(session.savedView(named: "Sea of Tranquility"))
                try await stage("saved-views")
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
                    browserHeader
                    if dynamicTypeSize.isAccessibilitySize {
                        // Let the detail and results share one scroll surface at large sizes.
                        ScrollView {
                            VStack(spacing: 20) {
                                destinationCard
                                placeResults
                            }.padding(.horizontal, 24).padding(.bottom, 24)
                        }
                    } else {
                        ScrollView {
                            placeResults.padding(.horizontal, 24).padding(.bottom, 12)
                        }
                        Divider().overlay(.white.opacity(0.08))
                        destinationCard.padding(.horizontal, 24).padding(.vertical, 18)
                    }
                }
            } else {
                NavigationStack {
                    List {
                        Section {
                            Label(distance(session.altitudeMeters) + " above terrain", systemImage: "arrow.up.and.down")
                            Text("Drag to move. Pinch to zoom. Rotate with two hands to change heading.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button { session.back() } label: { Label("Previous location", systemImage: "arrow.uturn.backward") }
                                .disabled(session.navigationHistory.isEmpty || session.navigationInProgress).hoverEffect()
                        }
                        Section { destinationCard }
                    }.navigationTitle("Surface")
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

    private var browserHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "moon.fill")
                    .font(.title).foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.08), in: Circle())
                Text("Moon").font(.largeTitle.weight(.semibold))
                Spacer()
            }
            LunarExplorerSearchField(text: $search, prompt: "Search the Moon", submit: openCoordinate)
            HStack(spacing: 8) {
                ForEach(["All", "Landings", "Craters"], id: \.self) { value in
                    Button { filter = value } label: {
                        Text(value == "Landings" ? "Landing sites" : value)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 18).frame(minHeight: 44)
                            .background(filter == value ? Color.blue.opacity(0.65) : .white.opacity(0.08), in: Capsule())
                            .frame(minHeight: 60)
                            .contentShape(.hoverEffect, Capsule())
                    }
                    .buttonStyle(.plain).hoverEffect()
                    .accessibilityAddTraits(filter == value ? .isSelected : [])
                    .accessibilityIdentifier("moon.filter." + value)
                }
            }
        }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
    }

    private var placeResults: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            Text(search.isEmpty ? "Points of interest" : "Search results")
                .font(.headline).padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            if LMLunarNavigation.parse(search) != nil {
                Button(action: openCoordinate) {
                    Label("Show coordinate", systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                }.hoverEffect()
            }
            ForEach(matches) { place in
                LunarExplorerPlaceRow(place: place, isSelected: session.selectedPlaceID == place.id) {
                    session.previewPlace(place)
                }
            }
            if matches.isEmpty && LMLunarNavigation.parse(search) == nil {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    private var sceneControls: some View {
        HStack(spacing: 16) {
            Button {
                if session.isImmersed { session.leaveImmersion() }
                else { session.enterImmersion() }
            } label: {
                Label(session.isImmersed ? "Leave immersion" : "Immerse",
                      systemImage: session.isImmersed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderless).hoverEffect()
            .disabled(!session.isImmersed && !session.canImmerse)
            .help(session.isImmersed ? "Return to the window" : "Available below 120 km across")
            .accessibilityIdentifier("moon.immersion")
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
        VStack(spacing: 12) {
            LunarExplorerSearchField(text: $savedSearch, prompt: "Search saved views", submit: {})
                .padding(.horizontal, 24)
            savedList
        }
    }

    private var savedMatches: [LunarExplorerSavedView] {
        session.library.views.filter { savedSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(savedSearch) }
    }

    private var savedList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Button(action: saveView) {
                    Label("Save current view", systemImage: "bookmark.badge.plus")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).disabled(session.navigationInProgress).hoverEffect()
                if session.library.views.isEmpty {
                    ContentUnavailableView("Keep a view", systemImage: "bookmark",
                        description: Text("Save a location, camera and sunlight to return to later."))
                        .padding(.top, 32)
                }
                if !session.library.views.isEmpty && savedMatches.isEmpty {
                    ContentUnavailableView.search(text: savedSearch).padding(.top, 32)
                }
                ForEach(savedMatches) { view in
                    Button { session.restore(view); tab = "explore" } label: {
                        HStack(spacing: 16) {
                            Image(systemName: view.isGlobe ? "globe" : "mountain.2")
                                .font(.title2).frame(width: 56, height: 56)
                                .background(.white.opacity(0.06), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(view.name).font(.title3.weight(.medium))
                                Text(view.isGlobe ? "Globe" : "Surface")
                                    .font(.callout).foregroundStyle(.secondary)
                            }.fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(14).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 24))
                    }
                    .buttonStyle(.plain).hoverEffect()
                    .contextMenu { Button("Delete saved view", role: .destructive) { session.library.remove(view.id) } }
                }
                if !session.library.message.isEmpty { Text(session.library.message).font(.footnote) }
            }.padding(.horizontal, 24).padding(.bottom, 24)
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
                    in: log(8)...log(5_000_000))
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
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title).foregroundStyle(.blue, .white)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.map(LunarExplorerPlaceRow.title) ?? "Selected location")
                        .font(.title3.weight(.semibold))
                    Button {
                        let c = session.displayedCoordinate
                        UIPasteboard.general.string = String(format: "%.6f, %.6f", c.latitudeDegrees, c.longitudeDegrees)
                        copied = true
                    } label: {
                        Label(copied ? "Copied coordinates" : coordinateCaption,
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain).help("Copy latitude and longitude").hoverEffect()
                    .onChange(of: coordinateCaption) { copied = false }
                }
                Spacer(minLength: 0)
                if let selected {
                    Button { infoPlace = selected } label: {
                        Label("About this place", systemImage: "info.circle").labelStyle(.iconOnly)
                            .frame(width: 60, height: 60)
                    }.buttonStyle(.borderless).help("About " + selected.name).hoverEffect()
                }
            }
            HStack(spacing: 12) {
                if session.isBrowsingGlobe {
                    Button { session.setExplorerMode("surface") } label: {
                        Label("Explore site", systemImage: "mountain.2")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(.blue)
                    .help("Zoom to terrain at this location").hoverEffect()
                    .accessibilityIdentifier("moon.exploreSite")
                }
                Button(action: saveView) {
                    Label("Save view", systemImage: "bookmark")
                        .labelStyle(.iconOnly).frame(width: 60, height: 60)
                }
                .buttonStyle(.borderless)
                .help("Save this location, camera and sunlight").hoverEffect()
            }
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

/// A full-width native text input; toolbar search collapses to an unreadable capsule in this window.
private struct LunarExplorerSearchField: View {
    @Binding var text: String
    var prompt: String
    var submit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain).submitLabel(.search)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .onSubmit(submit).accessibilityLabel(prompt)
                .help(prompt == "Search the Moon" ? "Search places or enter latitude, longitude" : prompt)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Label("Clear search", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                }.buttonStyle(.plain).hoverEffect()
            }
        }
        .font(.title3).padding(.horizontal, 18).frame(minHeight: 60)
        .background(.black.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .contentShape(.hoverEffect, Capsule()).hoverEffect()
    }
}

private struct LunarExplorerPlaceRow: View {
    let place: LMLunarPOICatalog.Place
    let isSelected: Bool
    var select: () -> Void

    static func title(_ place: LMLunarPOICatalog.Place) -> String {
        switch place.category {
        case "apollo": place.name + " Landing Site"
        case "crater": place.name + " Crater"
        default: place.name
        }
    }

    private var subtitle: String {
        // Regional names are presentation copy, independent of the pinned source coordinates.
        switch place.id {
        case "apollo-11": "Sea of Tranquility"
        case "apollo-17": "Taurus–Littrow"
        case "6163": "Southern highlands"
        default: place.category == "apollo" ? "Apollo landing site" : "Lunar " + place.category
        }
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 16) {
                Image(systemName: place.category == "apollo" ? "flag" : "circle.circle")
                    .font(.title2.weight(.light))
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.04), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.title(place)).font(.title3.weight(.medium))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.14) : .white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24)
                .strokeBorder(isSelected ? Color.blue.opacity(0.8) : .white.opacity(0.12),
                              lineWidth: isSelected ? 1.5 : 1))
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain).hoverEffect()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("moon.place." + place.id)
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
