import Foundation
import Testing
@testable import LM

@Suite("Moon Explorer experience") @MainActor
struct LunarExplorerExperienceTests {
    @Test func ordinaryLaunchStartsWithBoundedMixedGlobeAndCaptureKeepsInspection() {
        let normal = LunarExplorerSession()
        normal.configure(arguments: [])
        #expect(normal.isBrowsingGlobe && normal.isExplorerExperience)
        normal.exploreZoom(by: 1_000, from: normal.metersAcross)
        #expect(normal.metersAcross == 4_400)
        #expect(normal.presentsSite && normal.portalEnabled)
        #expect(!normal.isImmersed)
        normal.exploreZoom(by: 0.0001, from: normal.metersAcross)
        #expect(normal.metersAcross == 5_000_000)
        let capture = LunarExplorerSession()
        capture.configure(arguments: ["--lunar-explorer-capture", "--lunar-explorer-preset=terminal"])
        #expect(!capture.isBrowsingGlobe && !capture.isExplorerExperience)
        #expect(capture.altitudeMeters == 180 && capture.metersAcross == 700)
    }

    @Test func immersionGateClampsEveryZoomPathAndRestoresWindowRange() {
        let s = LunarExplorerSession()
        s.configure(arguments: [])
        #expect(s.portalEnabled && !s.canImmerse)
        s.enterImmersion()
        #expect(!s.isImmersed)
        s.exploreZoom(by: s.metersAcross / 120_000, from: s.metersAcross)
        #expect(!s.canImmerse) // The globe still covers a destination that is loading.
        s.diagnostics.loadMessage = "Apollo 11 terrain ready"
        #expect(s.canImmerse)
        s.enterImmersion()
        #expect(s.isImmersed && !s.portalEnabled)
        s.exploreZoom(by: 0.001, from: s.metersAcross)
        #expect(s.metersAcross == 120_000)
        s.logarithmicMetersAcross = 7
        #expect(s.metersAcross == 120_000)
        s.leaveImmersion()
        #expect(s.portalEnabled)
        s.exploreZoom(by: 0.001, from: s.metersAcross)
        #expect(s.metersAcross == 5_000_000 && s.isBrowsingGlobe)
    }

    @Test func windowHandoffKeepsTheSelectedRadialFacingTheEye() {
        let s = LunarExplorerSession()
        s.configure(arguments: [])
        s.exploreZoom(by: s.metersAcross / 180_000, from: s.metersAcross)
        #expect(s.selectedPreset == .globe && s.tiltDegrees == 0)
        #expect(s.presentsSite)
        s.exploreZoom(by: s.metersAcross / 24_000, from: s.metersAcross)
        #expect(s.selectedPreset == .regional && s.tiltDegrees == 72)
        s.diagnostics.loadMessage = "Apollo 11 terrain ready"
        s.enterImmersion()
        s.returnToGlobe()
        #expect(!s.isImmersed && s.portalEnabled)
        #expect(s.metersAcross == 4_400_000)
    }

    @Test func draggingCrossesDatelineAndPoleWithoutClamping() {
        let origin = LMSelenographicCoordinate(latitudeDegrees: 0, longitudeDegrees: 179)
        let east = LMLunarNavigation.draggedCoordinate(from: origin, northDegrees: 0, eastDegrees: 4)
        #expect(abs(east.longitudeDegrees + 177) < 1e-9)
        #expect(abs(east.latitudeDegrees) < 1e-9)
        let pole = LMLunarNavigation.draggedCoordinate(
            from: .init(latitudeDegrees: 89, longitudeDegrees: 0), northDegrees: 4, eastDegrees: 0)
        #expect(abs(pole.latitudeDegrees - 87) < 1e-9)
        #expect(abs(abs(pole.longitudeDegrees) - 180) < 1e-9)
        #expect(LMLunarNavigation.draggedCoordinate(from: origin, northDegrees: .nan, eastDegrees: 0) == origin)
    }

    @Test func daylightChoosesAnEphemerisTimeNearLocalNoon() {
        let s = LunarExplorerSession()
        s.configure(arguments: [])
        s.browseCoordinate = .init(latitudeDegrees: 0, longitudeDegrees: -179)
        let before = s.sunDate
        s.showDaylight()
        #expect(abs(s.sunDate.timeIntervalSince(before)) <= 15 * 86_400)
        #expect(LMLunarEphemeris.sunAngles(at: s.sunDate, site: s.browseCoordinate).elevationDegrees > 85)
        #expect(s.sunOffsetHours == 0)
    }

    @Test func productZoomRequestsFinerTerrainWhileInspectorZoomDoesNot() {
        let s = LunarExplorerSession()
        s.select(.regional)
        s.exploreZoom(by: 24_000 / 700, from: 24_000)
        #expect(abs(s.altitudeMeters - 180) < 1e-8)
        #expect(abs(s.tiltDegrees - 58) < 1e-8)
        #expect(s.metersAcross == 700)
        s.zoom(by: 2, from: 700)
        #expect(abs(s.altitudeMeters - 180) < 1e-8)
    }

    @Test func readyResidentGlobeHandsOffToTerrain() {
        let s = LunarExplorerSession()
        s.flightCoordinate = .init(latitudeDegrees: 0, longitudeDegrees: 23)
        s.pendingArrival = true
        s.beginArrival()
        #expect(s.flightCoordinate == nil)
        #expect(!s.pendingArrival && s.navigationPhase == .arriving)
        s.cancelNavigation()
    }

    @Test func savedCameraUsesAnchorAndOffsetsAndAppliesAfterArrival() {
        let s = LunarExplorerSession()
        s.destinationCoordinate = .init(latitudeDegrees: -42, longitudeDegrees: 120)
        s.currentCoordinate = .init(latitudeDegrees: -41.99, longitudeDegrees: 120.01)
        s.usesBundledSite = false
        s.select(.terminal)
        s.pan(northMeters: 130, eastMeters: -45)
        s.headingDegrees = 27
        s.sunOffsetHours = 120
        let saved = s.savedView(named: "Highland light")
        #expect(saved.latitude == -42 && saved.longitude == 120)
        #expect(saved.north == 130 && saved.east == -45)
        s.restore(saved)
        #expect(s.pendingSavedView == saved)
        #expect(s.sunDate == saved.date)
        s.pan(northMeters: 0, eastMeters: 0)
        s.applyPendingSavedView()
        #expect(s.focusNorthOffsetMeters == 130 && s.focusEastOffsetMeters == -45)
        #expect(s.headingDegrees == 27 && s.metersAcross == 700)
        #expect(s.pendingSavedView == nil)
        s.cancelNavigation()
    }

    @Test func leavingDuringFlightCancelsArrivalAndPreservesGlobe() async throws {
        let s = LunarExplorerSession()
        s.configure(arguments: [])
        s.browseCoordinate = .init(latitudeDegrees: -42, longitudeDegrees: 120)
        s.exploreSelectedPlace()
        #expect(s.navigationInProgress && s.isBrowsingGlobe) // Fade before immersion changes.
        #expect(s.flightCoordinate == s.browseCoordinate)
        s.returnToGlobe()
        try await Task.sleep(for: .milliseconds(80))
        #expect(s.isBrowsingGlobe && !s.navigationInProgress && !s.pendingArrival)
        #expect(s.flightCoordinate == nil)
    }

    @Test func reducedMotionFadesWithoutFlyingAndReopeningCancelsTransitions() async throws {
        let s = LunarExplorerSession()
        s.configure(arguments: [])
        s.reduceMotion = true
        let initialWidth = s.metersAcross
        s.exploreSelectedPlace(altitude: 180, heading: 27)
        #expect(s.isBrowsingGlobe && s.metersAcross == initialWidth)
        for _ in 0..<100 where s.navigationPhase != .loading {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!s.isBrowsingGlobe && s.pendingArrival && s.transitionOpacity == 0)
        #expect(s.metersAcross == initialWidth) // No zoom animation before load.
        s.beginArrival()
        #expect(s.altitudeMeters == 180 && s.headingDegrees == 27)
        let arrivalWidth = s.metersAcross
        for _ in 0..<100 where s.navigationInProgress {
            try await Task.sleep(for: .milliseconds(20))
            #expect(s.metersAcross == arrivalWidth) // Only opacity changes.
        }
        #expect(s.transitionOpacity == 1 && !s.navigationInProgress)
        s.returnToGlobeGently()
        s.prepareForPresentation()
        try await Task.sleep(for: .milliseconds(350))
        #expect(s.isBrowsingGlobe && s.transitionOpacity == 1)
        #expect(!s.navigationInProgress && !s.pendingArrival)
    }

    @Test func bookmarksSurviveReloadAndRejectInvalidPersistedCoordinates() throws {
        let name = "LM-Explorer-Test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let s = LunarExplorerSession()
        s.configure(arguments: [])
        s.browseCoordinate = .init(latitudeDegrees: 89, longitudeDegrees: 179)
        let saved = s.savedView(named: "Polar view")
        let library = LunarExplorerLibrary(defaults: defaults)
        library.save(saved)
        #expect(LunarExplorerLibrary(defaults: defaults).views == [saved])
        var invalid = saved
        invalid.latitude = 91
        defaults.set(try JSONEncoder().encode([invalid, saved]), forKey: LunarExplorerLibrary.key)
        #expect(LunarExplorerLibrary(defaults: defaults).views == [saved])
        library.remove(saved.id)
        #expect(LunarExplorerLibrary(defaults: defaults).views.isEmpty)
    }
}
