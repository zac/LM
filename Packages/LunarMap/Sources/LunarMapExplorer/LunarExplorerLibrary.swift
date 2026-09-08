import LunarMap
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
        isBrowsingGlobe ? selectedMarkerPlace?.coordinate ?? browseCoordinate : currentCoordinate ?? destinationCoordinate ?? browseCoordinate
    }

    func returnToGlobe() {
        cancelNavigation()
        transitionOpacity = 1
        setGlobePresentation()
    }

    func setGlobePresentation() {
        let coordinate = isBrowsingGlobe ? browseCoordinate : currentCoordinate ?? destinationCoordinate ?? browseCoordinate
        if !isBrowsingGlobe { selectedPlaceID = nil }
        isBrowsingGlobe = true
        browseCoordinate = coordinate
        leaveImmersion()
        select(.globe)
        headingDegrees = 0
    }

    func previewPlace(_ place: LMLunarPOICatalog.Place) {
        returnToGlobe()
        browseCoordinate = place.coordinate
        selectedPlaceID = place.id
        if followsDaylightSelection { showDaylight() }
    }

    func exploreSelectedPlace(altitude: Double = Preset.regional.altitudeMeters, heading: Double = 0) {
        guard !landingRunning else { return }
        let coordinate = selectedMarkerPlace?.coordinate ?? browseCoordinate
        flightCoordinate = coordinate
        fly(to: coordinate, altitude: altitude, heading: heading)
    }

    func showDaylight() {
        sunAnchorDate = Self.daylightDate(near: sunDate, coordinate: displayedCoordinate)
        sunOffsetHours = 0
        followsDaylightSelection = true
    }

    /// Search the existing 30-day window for 25-degree relief lighting.
    /// Prefer a morning crossing, then the nearest instant. Polar sites that
    /// never reach the target use the closest sampled elevation in the window.
    static func daylightDate(near reference: Date, coordinate: LMSelenographicCoordinate) -> Date {
        func elevation(_ date: Date) -> Double {
            LMLunarEphemeris.sunAngles(at: date, site: coordinate).elevationDegrees
        }
        let dates = (-60...60).map { reference.addingTimeInterval(Double($0) * 21_600) }
        let samples = dates.map { (date: $0, elevation: elevation($0)) }
        var crossings = [(date: Date, morning: Bool)]()
        for (a, b) in zip(samples, samples.dropFirst()) {
            guard (a.elevation - 25) * (b.elevation - 25) <= 0 else { continue }
            var low = a.date, high = b.date
            let rising = b.elevation > a.elevation
            for _ in 0..<20 {
                let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                if (elevation(middle) < 25) == rising { low = middle } else { high = middle }
            }
            let date = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            let azimuth = LMLunarEphemeris.sunAngles(at: date, site: coordinate).azimuthDegreesClockwiseFromNorth
            crossings.append((date, azimuth >= 0 && azimuth < 180))
        }
        if let choice = crossings.min(by: {
            if $0.morning != $1.morning { return $0.morning }
            return abs($0.date.timeIntervalSince(reference)) < abs($1.date.timeIntervalSince(reference))
        }) { return choice.date }
        return samples.min {
            let a = abs($0.elevation - 25), b = abs($1.elevation - 25)
            return a == b ? abs($0.date.timeIntervalSince(reference)) < abs($1.date.timeIntervalSince(reference)) : a < b
        }?.date ?? reference
    }

    func rotateGlobe(from start: LMSelenographicCoordinate, horizontal: Double, vertical: Double) {
        guard horizontal.isFinite, vertical.isFinite else { return }
        browseCoordinate = LMLunarNavigation.draggedCoordinate(
            from: start, northDegrees: vertical * 0.18, eastDegrees: -horizontal * 0.18)
    }

    func setExplorerMode(_ mode: String) {
        guard !navigationInProgress, !landingRunning else { return }
        if mode == "globe", !isBrowsingGlobe { returnToGlobeGently() }
        else if mode == "surface", isBrowsingGlobe {
            let place = selectedMarkerPlace
            exploreSelectedPlace(altitude: place?.suggestedAltitudeMeters ?? 7_500,
                                 heading: place?.suggestedHeadingDegrees ?? 0)
        }
    }

    func advanceGlobeRotation(seconds: Double) {
        guard automaticallyRotatesGlobe, !reduceMotion, !isManipulatingGlobe,
              isBrowsingGlobe, !navigationInProgress, !landingRunning else { return }
        browseCoordinate = LMLunarNavigation.draggedCoordinate(from: browseCoordinate,
            northDegrees: 0, eastDegrees: min(0.1, max(0, seconds)) * 0.35)
    }

    /// The width adapter is for saved views and the scale slider. Gestures
    /// use their starting altitude directly, so magnification is logarithmic
    /// altitude rather than interpolation among independent camera controls.
    func exploreZoom(by magnification: Double, from initialWidth: Double) {
        guard magnification.isFinite, magnification > 0, initialWidth.isFinite, initialWidth > 0 else { return }
        camera.reference = nil
        metersAcross = initialWidth / magnification
        updateCameraSelection()
        synchronizeZoomDestination()
    }

    func magnifyAltitude(by magnification: Double, from initialAltitude: Double, synchronize: Bool = true) {
        guard magnification.isFinite, magnification > 0, initialAltitude.isFinite, initialAltitude > 0 else { return }
        camera.reference = nil
        altitudeMeters = initialAltitude / magnification
        updateCameraSelection()
        if synchronize { synchronizeZoomDestination() }
    }

    private func updateCameraSelection() {
        selectedPreset = Preset.allCases.min {
            abs(log($0.altitudeMeters / altitudeMeters)) < abs(log($1.altitudeMeters / altitudeMeters))
        } ?? .orbit
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
            metersAcross = min(Self.maximumMetersAcross, max(Self.minimumMetersAcross, view.width))
            synchronizeZoomDestination()
        } else {
            if isBrowsingGlobe { flightCoordinate = browseCoordinate }
            if !isExplorerExperience {
                isBrowsingGlobe = false
                immersionStyle = .full
            }
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
