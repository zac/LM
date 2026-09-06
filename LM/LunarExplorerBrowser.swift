import SwiftUI
import UIKit

/// The everyday Explorer. Detailed renderer controls live in the inspector.
struct LunarExplorerControls: View {
    @Bindable var session: LunarExplorerSession
    var close: () -> Void
    var landInCockpit: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsPlacement = false
    @State private var places: [LMLunarPOICatalog.Place] = []
    @State private var search = ""
    @State private var filter = "All"
    @State private var showsSun = false
    @State private var showsInspector = false
    @State private var showsSave = false
    @State private var savedName = ""

    private var selected: LMLunarPOICatalog.Place? {
        places.first { $0.id == session.selectedPlaceID }
    }
    private var matches: [LMLunarPOICatalog.Place] {
        places.filter {
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { panelContent }
            } else {
                panelContent
            }
        }
        .padding(24)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 680 : 520,
               height: session.isBrowsingGlobe ? 720 : 560)
        .glassBackgroundEffect()
        .tint(.blue)
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            toolbar
        }
        .alert("Save view", isPresented: $showsSave) {
            TextField("Name", text: $savedName)
            Button("Save") { session.library.save(session.savedView(named: savedName)) }
                .disabled(savedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Remembers this location, camera and sunlight.") }
        .sheet(isPresented: $showsInspector) {
            LunarExplorerInspector(session: session, close: { showsInspector = false }, landInCockpit: landInCockpit)
        }
        .task {
            do { places = try LMLunarPOICatalog.load().features }
            catch { session.navigationMessage = "Places could not be loaded. Coordinate search is still available." }
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "moonphase.waning.gibbous").font(.largeTitle)
                VStack(alignment: .leading) {
                    Text("Moon").font(.largeTitle.weight(.semibold))
                    Text(session.isBrowsingGlobe ? "Choose somewhere to explore" : "Exploring the surface")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 60, height: 60).contentShape(.rect) }
                    .buttonStyle(.borderless).accessibilityLabel("Close Moon Explorer")
            }
            if session.isBrowsingGlobe {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search places or latitude, longitude", text: $search)
                        .onSubmit { openCoordinate() }
                        .accessibilityIdentifier("moon.search")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }
                .padding(12).frame(minHeight: 60).background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                if dynamicTypeSize.isAccessibilitySize {
                    placeFilter.pickerStyle(.menu)
                } else {
                    placeFilter.pickerStyle(.segmented)
                }

                if dynamicTypeSize.isAccessibilitySize {
                    destinationCard
                    placeResults
                } else {
                    ScrollView { placeResults }.frame(minHeight: 140, maxHeight: .infinity)
                }
            } else {
                HStack {
                    Button { session.returnToGlobeGently() } label: { Label("Return to globe", systemImage: "globe") }
                    Spacer()
                    Button { session.back() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(session.navigationHistory.isEmpty || session.navigationInProgress)
                        .accessibilityLabel("Previous location")
                }
                .accessibilityIdentifier("moon.return")
                HStack {
                    Label(distance(session.altitudeMeters) + " above terrain", systemImage: "arrow.up.and.down")
                    Spacer()
                    Menu("View") {
                        ForEach(LunarExplorerSession.Preset.allCases.filter { $0 != .globe }) { preset in
                            Button(preset.title) { session.select(preset) }
                        }
                    }
                }.font(.subheadline)
                Picker("Drag action", selection: $session.navigationMode) {
                    Text("Rotate").tag(LunarExplorerSession.NavigationMode.orbit)
                    Text("Move").tag(LunarExplorerSession.NavigationMode.pan)
                }.pickerStyle(.segmented)
                Text("Drag the terrain to \(session.navigationMode == .orbit ? "rotate" : "move"). Pinch to explore closer.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Divider()
            if !session.isBrowsingGlobe || !dynamicTypeSize.isAccessibilitySize { destinationCard }
            if session.navigationInProgress {
                HStack { ProgressView().controlSize(.small); Text(session.navigationMessage).font(.subheadline) }
            } else if !session.navigationMessage.isEmpty {
                Text(session.navigationMessage).font(.caption).foregroundStyle(.secondary)
            }
            if !session.library.message.isEmpty { Text(session.library.message).font(.caption) }
        }
    }

    private var placeFilter: some View {
        Picker("Places", selection: $filter) {
            ForEach(["All", "Landings", "Craters", "Saved"], id: \.self) { Text($0) }
        }
    }

    private var placeResults: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            if filter == "Saved" {
                if session.library.views.isEmpty {
                    ContentUnavailableView("Keep a view", systemImage: "bookmark",
                        description: Text("Save a location, camera angle and sunlight to return to later."))
                }
                ForEach(session.library.views.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { view in
                    Button { session.restore(view) } label: {
                        placeRow(title: view.name,
                            subtitle: view.isGlobe ? "Saved globe view" : "Open immersive terrain view",
                            symbol: "bookmark.fill", selected: false)
                    }
                    .buttonStyle(.plain).hoverEffect(.highlight)
                    .contextMenu { Button("Delete saved view", role: .destructive) { session.library.remove(view.id) } }
                }
            } else {
                if LMLunarNavigation.parse(search) != nil {
                    Button(action: openCoordinate) {
                        placeRow(title: "Show coordinate", subtitle: search,
                                 symbol: "mappin.and.ellipse", selected: false)
                    }.buttonStyle(.plain).hoverEffect(.highlight)
                }
                ForEach(matches) { place in
                    Button { session.previewPlace(place) } label: {
                        placeRow(title: place.name,
                            subtitle: place.category == "apollo" ? "Landing site" : place.category.capitalized,
                            symbol: place.category == "apollo" ? "flag.fill" : "circle.dotted",
                            selected: session.selectedPlaceID == place.id)
                    }
                    .buttonStyle(.plain).hoverEffect(.highlight)
                    .accessibilityIdentifier("moon.place." + place.id)
                }
                if matches.isEmpty && LMLunarNavigation.parse(search) == nil {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }

    private var toolbar: some View {
            HStack(spacing: 8) {
                Button { session.returnToGlobeGently() } label: { Image(systemName: "globe").frame(width: 60, height: 60).contentShape(.rect) }
                    .accessibilityLabel("Return to whole Moon")
                Button { session.exploreZoom(by: 1 / 1.6, from: session.metersAcross) } label: { Image(systemName: "minus").frame(width: 60, height: 60).contentShape(.rect) }
                    .accessibilityLabel("Zoom out")
                Button { session.exploreZoom(by: 1.6, from: session.metersAcross) } label: { Image(systemName: "plus").frame(width: 60, height: 60).contentShape(.rect) }
                    .accessibilityLabel("Zoom in")
                Button { showsSun.toggle() } label: { Image(systemName: "sun.max").frame(width: 60, height: 60).contentShape(.rect) }
                    .accessibilityLabel("Sunlight")
                    .popover(isPresented: $showsSun) { LunarExplorerSunPanel(session: session) }
                Button { savedName = selected?.name ?? "Moon view"; showsSave = true } label: { Image(systemName: "bookmark").frame(width: 60, height: 60).contentShape(.rect) }
                    .accessibilityLabel("Save this view")
                    .disabled(session.navigationInProgress)
                if session.isBrowsingGlobe {
                    Button { showsPlacement = true } label: {
                        Image(systemName: "move.3d").frame(width: 60, height: 60).contentShape(.rect)
                    }
                    .accessibilityLabel("Position globe")
                    .popover(isPresented: $showsPlacement) { LunarExplorerPlacementPanel(session: session) }
                }
                Button { showsInspector = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 60, height: 60).contentShape(.rect) }
                    .accessibilityLabel("Terrain inspector")
                    .disabled(session.isBrowsingGlobe || session.navigationInProgress)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .glassBackgroundEffect()
            .disabled(session.landingRunning)
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "mappin.circle.fill").foregroundStyle(.blue).font(.title2)
                Text(selected?.name ?? "Selected location").font(.title3.weight(.semibold))
                Spacer()
                if let selected { Link(destination: selected.sourceURL) { Image(systemName: "info.circle").frame(width: 60, height: 60).contentShape(.rect) }.accessibilityLabel("Place source") }
            }
            Text(coordinateCaption).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let selected, session.isBrowsingGlobe {
                Text(placeDescription(selected)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if session.isBrowsingGlobe {
                Button {
                    session.exploreSelectedPlace(altitude: selected?.suggestedAltitudeMeters ?? 7_500,
                                                 heading: selected?.suggestedHeadingDegrees ?? 0)
                } label: {
                    Label("Explore surface", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("moon.explore")
                Text("Opens an immersive terrain view. Return to the globe anytime.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let floor = session.diagnostics.measuredFloorMeters {
                Text("Elevation measured every \(distance(floor)). Finer terrain is modeled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.disabled(session.landingRunning || session.navigationInProgress)
    }

    private func placeRow(title: String, subtitle: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(selected ? Color.blue.opacity(0.16) : Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private func placeDescription(_ place: LMLunarPOICatalog.Place) -> String {
        switch place.id {
        case "apollo-11": "Tranquility Base, where the first crewed Moon landing took place on July 20, 1969."
        case "apollo-17": "Taurus-Littrow valley, explored by the final Apollo landing crew in December 1972."
        default: "Explore this \(place.category == "apollo" ? "landing site" : place.category) and its surroundings under changing lunar sunlight."
        }
    }

    private var coordinateCaption: String {
        let c = session.displayedCoordinate
        return String(format: "%.4f° %@, %.4f° %@", abs(c.latitudeDegrees),
            c.latitudeDegrees < 0 ? "S" : "N", abs(c.longitudeDegrees), c.longitudeDegrees < 0 ? "W" : "E")
    }

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
            Label("Sunlight", systemImage: "sun.max").font(.title2.weight(.semibold))
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
