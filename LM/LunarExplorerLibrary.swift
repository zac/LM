import Foundation
import SwiftUI

/// A camera and lighting bookmark, independent of transient terrain residency.
struct LunarExplorerSavedView: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var isGlobe: Bool
    var altitude: Double
    var width: Double
    var heading: Double
    var tilt: Double
    var north: Double
    var east: Double
    var date: Date
    var grade: String
    var detail: String
    var shadows: Bool
    var navigation: String

    var coordinate: LMSelenographicCoordinate {
        .init(latitudeDegrees: latitude, longitudeDegrees: longitude)
    }

    var isValid: Bool {
        [latitude, longitude, altitude, width, heading, tilt, north, east,
         date.timeIntervalSince1970].allSatisfy(\.isFinite)
            && abs(latitude) <= 90 && abs(longitude) <= 180
            && (1.5...1_500_000).contains(altitude)
            && (8...5_000_000).contains(width)
            && (-82...82).contains(tilt)
            && abs(north) <= 20_000 && abs(east) <= 20_000
            && LMTerrainPresentationGrade(rawValue: grade) != nil
            && LMTerrainDetailMode(rawValue: detail) != nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor @Observable
final class LunarExplorerLibrary {
    private(set) var views: [LunarExplorerSavedView] = []
    var message = ""
    @ObservationIgnored private let defaults: UserDefaults
    static let key = "moon-explorer.saved-views.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do { views = try JSONDecoder().decode([LunarExplorerSavedView].self, from: data).filter(\.isValid) }
            catch { message = "Saved views could not be read." }
        }
    }

    func save(_ view: LunarExplorerSavedView) {
        guard view.isValid else { message = "This view is not ready to save."; return }
        views.insert(view, at: 0)
        persist()
    }

    func remove(_ id: UUID) {
        views.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(views), forKey: Self.key)
            message = ""
        } catch { message = "The view could not be saved." }
    }
}

extension LunarExplorerSession {
    var displayedCoordinate: LMSelenographicCoordinate {
        isBrowsingGlobe ? browseCoordinate : currentCoordinate ?? destinationCoordinate ?? browseCoordinate
    }

    func returnToGlobe() {
        let coordinate = isBrowsingGlobe ? browseCoordinate : currentCoordinate ?? destinationCoordinate ?? browseCoordinate
        if !isBrowsingGlobe { selectedPlaceID = nil }
        cancelNavigation()
        isBrowsingGlobe = true
        browseCoordinate = coordinate
        select(.globe)
        headingDegrees = 0
        immersionStyle = .mixed
    }

    func previewPlace(_ place: LMLunarPOICatalog.Place) {
        returnToGlobe()
        browseCoordinate = place.coordinate
        selectedPlaceID = place.id
    }

    func exploreSelectedPlace(altitude: Double = Preset.regional.altitudeMeters, heading: Double = 0) {
        guard !landingRunning else { return }
        flightCoordinate = browseCoordinate
        isBrowsingGlobe = false
        immersionStyle = .full
        fly(to: browseCoordinate, altitude: altitude, heading: heading)
    }

    func showDaylight() {
        let reference = sunDate
        let coordinate = displayedCoordinate
        let candidates = (-60...60).map { reference.addingTimeInterval(Double($0) * 6 * 3_600) }
        sunAnchorDate = candidates.max {
            LMLunarEphemeris.sunAngles(at: $0, site: coordinate).elevationDegrees
                < LMLunarEphemeris.sunAngles(at: $1, site: coordinate).elevationDegrees
        } ?? reference
        sunOffsetHours = 0
    }

    func rotateGlobe(from start: LMSelenographicCoordinate, horizontal: Double, vertical: Double) {
        guard horizontal.isFinite, vertical.isFinite else { return }
        browseCoordinate = LMLunarNavigation.draggedCoordinate(
            from: start, northDegrees: vertical * 0.18, eastDegrees: -horizontal * 0.18)
        selectedPlaceID = nil
    }

    /// Product zoom requests matching geometry. The independent inspection
    /// zoom remains available in the inspector and all old capture arguments.
    func exploreZoom(by magnification: Double, from initialWidth: Double) {
        guard magnification.isFinite, magnification > 0, initialWidth.isFinite else { return }
        if isBrowsingGlobe {
            metersAcross = min(5_000_000, max(3_400_000, initialWidth / magnification))
            return
        }
        zoom(by: magnification, from: initialWidth)
        let stops = [(5_000_000.0, 1_500_000.0, 0.0)]
            + Preset.allCases.map { ($0.metersAcross, $0.altitudeMeters, $0.tiltDegrees) }
            + [(8.0, 1.5, 38.0)]
        for (a, b) in zip(stops, stops.dropFirst()) where metersAcross <= a.0 && metersAcross >= b.0 {
            let t = (log(metersAcross) - log(a.0)) / (log(b.0) - log(a.0))
            altitudeMeters = exp(log(a.1) * (1 - t) + log(b.1) * t)
            tiltDegrees = a.2 * (1 - t) + b.2 * t
            break
        }
    }

    func savedView(named name: String) -> LunarExplorerSavedView {
        // Save the resident anchor plus offsets. Saving the focused coordinate
        // and the offsets together would apply a pan twice on restore.
        let coordinate = isBrowsingGlobe ? browseCoordinate
            : destinationCoordinate ?? (try? LMTerrainManifest.load().landingOriginCoordinate) ?? displayedCoordinate
        return .init(name: name, latitude: coordinate.latitudeDegrees, longitude: coordinate.longitudeDegrees,
            isGlobe: isBrowsingGlobe, altitude: altitudeMeters, width: metersAcross,
            heading: headingDegrees, tilt: tiltDegrees,
            north: focusNorthOffsetMeters, east: focusEastOffsetMeters,
            date: sunDate, grade: presentationGrade.rawValue, detail: detailMode.rawValue,
            shadows: missionShadowsEnabled, navigation: navigationMode.rawValue)
    }

    func restore(_ view: LunarExplorerSavedView) {
        guard view.isValid, !landingRunning else { return }
        selectedPlaceID = nil
        sunAnchorDate = view.date
        sunOffsetHours = 0
        presentationGrade = LMTerrainPresentationGrade(rawValue: view.grade) ?? .calibrated
        detailMode = LMTerrainDetailMode(rawValue: view.detail) ?? .automatic
        missionShadowsEnabled = view.shadows
        if view.isGlobe {
            returnToGlobe()
            browseCoordinate = view.coordinate
            metersAcross = min(5_000_000, max(3_400_000, view.width))
        } else {
            if isBrowsingGlobe { flightCoordinate = browseCoordinate }
            isBrowsingGlobe = false
            immersionStyle = .full
            fly(to: view.coordinate, altitude: view.altitude, heading: view.heading)
            pendingSavedView = view
        }
    }

    func applyPendingSavedView() {
        guard let view = pendingSavedView else { return }
        pendingSavedView = nil
        altitudeMeters = view.altitude
        metersAcross = view.width
        headingDegrees = view.heading
        tiltDegrees = view.tilt
        pan(northMeters: view.north, eastMeters: view.east)
        navigationMode = NavigationMode(rawValue: view.navigation) ?? .orbit
    }
}
