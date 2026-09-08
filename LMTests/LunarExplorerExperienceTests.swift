@testable import LunarMapExplorer
@testable import LunarMap
import Foundation
import Testing
import simd
@testable import LM

@Suite("Moon Explorer experience") @MainActor
struct LunarExplorerExperienceTests {
    @Test func sitePackUsesGlobalENUAndLeavesInteractiveCameraUnchanged() throws {
        let manifest = try LMTerrainManifest.load()
        let origin = try LMTerrainFrameAlignment(manifest: manifest).terrainReferenceTouchdown
        let pack = try LunarExplorerSitePack(manifest: manifest, focusOrigin: origin)
        var camera = LunarExplorerCamera()
        camera.reference = nil
        let before = camera
        pack.configureInspection(&camera)
        #expect(camera == before)
        #expect(camera.siteHeightMeters == 1.45)
        #expect(pack.sourceIDs.contains("nac-dtm-apollo11"))
        var worst = 0.0
        for north in [-896.0, 0, 896] {
            for east in [-896.0, 0, 896] {
                let source = LMSiteENUPosition(northMeters: north, eastMeters: east, upMeters: -0.25)
                let coordinate = pack.frame.coordinate(for: source)
                let restored = pack.frame.position(for: coordinate)
                worst = max(worst, simd_length(restored.vector - source.vector))
            }
        }
        print("Apollo site-pack ENU round-trip maximum=\(worst)m")
        #expect(worst < 1e-6)
        camera.reference = .init(width: 24_000, tilt: 72)
        pack.configureInspection(&camera)
        #expect(camera.siteHeightMeters == -0.35)
        #expect(camera.reference?.fixedGlobeCoordinate == manifest.landingOriginCoordinate)
    }

    @Test func sitePackPanBoundsProtectMeasuredCollarInSourceCoordinates() throws {
        let manifest = try LMTerrainManifest.load()
        let origin = try LMTerrainFrameAlignment(manifest: manifest).terrainReferenceTouchdown
        let pack = try LunarExplorerSitePack(manifest: manifest, focusOrigin: origin)
        let session = LunarExplorerSession()
        session.residentPanBounds = pack.panBounds
        session.pan(northMeters: 20_000, eastMeters: -20_000)
        let tile = try #require(manifest.tile(id: "near-field"))
        #expect(abs(session.focusNorthOffsetMeters + origin.x - (tile.extentMeters / 2 - 128)) < 1e-9)
        #expect(abs(session.focusEastOffsetMeters + origin.y + (tile.extentMeters / 2 - 128)) < 1e-9)
        session.residentPanBounds = .regional
        session.pan(northMeters: 25_000, eastMeters: -25_000)
        #expect(session.focusNorthOffsetMeters == 20_000)
        #expect(session.focusEastOffsetMeters == -20_000)
    }

    @Test func fixedDepthPinchReleasesContinuouslyAtLimbWithoutZoomFloor() throws {
        typealias G = LunarExplorerPinchGeometry
        let ray = G.Ray(origin: SIMD3(0, 1.45, 0), through: SIMD3(2.05, 1.45, -2.17))
        var previous: SIMD3<Float>?
        var maximumStep: Float = 0
        for width in stride(from: 1_000_000.0, through: 5_000_000, by: 1_000) {
            let radius = Float(1_737_400 * 3 / width)
            let center = SIMD3<Float>(1.05, 1.45, -(2.17 + radius))
            let direction = try #require(G.sphereDirection(ray: ray, center: center, radius: radius, releaseAtLimb: true))
            #expect(abs(simd_length(direction) - 1) < 1e-5)
            if let previous { maximumStep = max(maximumStep, simd_distance(previous, direction)) }
            previous = direction
            if width == 1_000_000 {
                let hit = center + radius * direction
                #expect(simd_length(simd_cross(hit - ray.origin, ray.direction)) < 1e-5)
            }
            if width == 5_000_000 {
                #expect(G.sphereDirection(ray: ray, center: center, radius: radius, releaseAtLimb: false) == nil)
            }
        }
        #expect(maximumStep < 0.015)
    }

    @Test func pinchBoundsKeepParallelAndEdgeHits() {
        typealias G = LunarExplorerPinchGeometry
        let minimum = SIMD3<Float>(-1, -1, -1), maximum = SIMD3<Float>(1, 1, 1)
        #expect(G.intersectsBounds(origin: SIMD3(1, 0, 2), direction: SIMD3(0, 0, -1), minimum: minimum, maximum: maximum))
        #expect(!G.intersectsBounds(origin: SIMD3(2, 0, 2), direction: SIMD3(0, 0, -1), minimum: minimum, maximum: maximum))
        #expect(!G.intersectsBounds(origin: SIMD3(0, 0, 2), direction: SIMD3(0, 0, 1), minimum: minimum, maximum: maximum))
        #expect(G.intersectsBounds(origin: .zero, direction: SIMD3(0, 1, 0), minimum: minimum, maximum: maximum))
    }

    @Test func terrainAnchorSolvesPanAfterScaleAndTiltChange() throws {
        typealias G = LunarExplorerPinchGeometry
        let sourcePoint = SIMD3<Float>(140, 19, -80)
        let ray = G.Ray(origin: SIMD3(0, 1.45, 0), through: SIMD3(0.2, 1.3, -2.35))
        for tilt in [38.0, 58, 72, 90] {
            for heading in [0.0, 27, 90, 179] {
                let rotation = simd_quatf(angle: Float(tilt * .pi / 180), axis: SIMD3(1, 0, 0))
                    * simd_quatf(angle: Float(heading * .pi / 180), axis: SIMD3(0, 1, 0))
                let north = rotation.act(SIMD3<Float>(1, 0, 0)) * 0.003
                let east = rotation.act(SIMD3<Float>(0, 0, -1)) * 0.003
                let point = SIMD3<Float>(0, 1.45, -2.35) + rotation.act(sourcePoint) * 0.003
                let correction = try #require(G.panCorrection(point: point, north: north, east: east, ray: ray))
                let corrected = point - north * Float(correction.x) - east * Float(correction.y)
                #expect(simd_length(simd_cross(corrected - ray.origin, ray.direction)) < 1e-5)
            }
        }
    }

    @Test func ordinaryLaunchStartsWithBoundedMixedGlobeAndCaptureKeepsInspection() {
        let normal = LunarExplorerSession()
        normal.configure(arguments: [])
        #expect(normal.isBrowsingGlobe && normal.isExplorerExperience)
        normal.exploreZoom(by: 1_000, from: normal.metersAcross)
        #expect(abs(normal.metersAcross - 4_400) < 1e-8)
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
        #expect(!s.portalEnabled && !s.canImmerse)
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
        #expect(s.usesAltitudeCamera && s.tiltDegrees <= 72)
        #expect(s.presentsSite)
        s.exploreZoom(by: s.metersAcross / 24_000, from: s.metersAcross)
        #expect(s.selectedPreset == .regional && s.tiltDegrees == 72)
        s.diagnostics.loadMessage = "Apollo 11 terrain ready"
        s.enterImmersion()
        s.returnToGlobe()
        #expect(!s.isImmersed && !s.portalEnabled)
        #expect(s.metersAcross == 4_400_000)
    }

    @Test func altitudeCameraPreservesNamedFramingAndHasContinuousHandoff() {
        var camera = LunarExplorerCamera()
        camera.reference = nil
        for preset in LunarExplorerSession.Preset.allCases {
            camera.altitude = preset.altitudeMeters
            #expect(camera.width == preset.metersAcross)
            #expect(abs(camera.tilt - preset.tiltDegrees) < 1e-10)
            camera.setWidth(preset.metersAcross)
            #expect(camera.altitude == preset.altitudeMeters)
        }
        for width in [240_000.0, 180_000, 120_000] {
            let altitude = LunarExplorerCamera.altitude(forWidth: width)
            camera.altitude = altitude * (1 - 1e-8)
            let left = (camera.width, camera.tilt)
            camera.altitude = altitude * (1 + 1e-8)
            #expect(abs(camera.width - left.0) / width < 1e-6)
            #expect(abs(camera.tilt - left.1) < 1e-5)
        }
        camera.altitude = 7_500
        camera.windowWidthMeters = LunarExplorerCamera.calibratedWindowWidthMeters / 2
        #expect(camera.width == 12_000 && camera.tilt == 72)
        let s = LunarExplorerSession()
        s.configure(arguments: [])
        s.magnifyAltitude(by: 2, from: 7_500)
        #expect(s.altitudeMeters == 3_750 && s.usesAltitudeCamera)
    }

    @Test func planningHeadingUsesFifteenDegreeBinsWithHysteresisAcrossNorth() {
        var heading = LunarExplorerPlanningHeading()
        for value in [7.4, 8, 9.9, -9.9, 360, -720] { heading.commit(value); #expect(heading.degrees == 0) }
        heading.commit(10.1)
        #expect(heading.degrees == 15)
        heading.commit(6)
        #expect(heading.degrees == 15)
        heading.commit(4)
        #expect(heading.degrees == 0)
        heading.commit(349)
        #expect(heading.degrees == 345)
        heading.commit(354)
        #expect(heading.degrees == 345)
        heading.commit(356)
        #expect(heading.degrees == 0)
    }

    @Test func headingGestureAtSevenHundredMetersStartsNoTerrainGenerations() async throws {
        let s = LunarExplorerSession()
        s.configure(arguments: [])
        s.select(.terminal)
        let region = try LMLunarContactTests().region(at: .init(latitudeDegrees: -42, longitudeDegrees: 120))
        let terrain = LMLunarTerrainPresentation(region: region, mode: .procedural)
        defer { terrain.cancel() }
        var ready = false
        func update() {
            terrain.update(east: 0, north: 0, altitude: s.altitudeMeters,
                           metersAcross: s.metersAcross, heading: s.terrainPlanningHeadingDegrees) { _, _, _, _, ms in
                ready = ms != nil
            }
        }
        update()
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        while !ready && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(ready)
        let requests = terrain.generationRequestCount, builds = terrain.tileBuildCount
        s.beginHeadingGesture()
        for angle in stride(from: 0.0, through: 90.0, by: 1.5) {
            s.headingDegrees = angle
            update()
            try await Task.sleep(for: .milliseconds(2))
            #expect(terrain.generationRequestCount == requests)
            #expect(terrain.tileBuildCount == builds)
        }
        s.endHeadingGesture()
        update()
        #expect(s.terrainPlanningHeadingDegrees == 90)
        #expect(terrain.generationRequestCount == requests + 1)
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

    @Test func daylightChoosesMorningReliefLighting() {
        let s = LunarExplorerSession()
        s.configure(arguments: [])
        s.browseCoordinate = .init(latitudeDegrees: 0, longitudeDegrees: -179)
        let before = s.sunDate
        s.showDaylight()
        #expect(abs(s.sunDate.timeIntervalSince(before)) <= 15 * 86_400)
        let sun = LMLunarEphemeris.sunAngles(at: s.sunDate, site: s.browseCoordinate)
        #expect(abs(sun.elevationDegrees - 25) < 0.001)
        #expect(sun.azimuthDegreesClockwiseFromNorth < 180)
        #expect(s.sunOffsetHours == 0)
    }

    @Test func placeSelectionRetargetsDaylightButPreservesManualSunlight() throws {
        let session = LunarExplorerSession()
        session.configure(arguments: [])
        let place = try #require(session.catalogPlaces.first { $0.id == "apollo-11" })
        session.previewPlace(place)
        let sun = LMLunarEphemeris.sunAngles(at: session.sunDate, site: place.coordinate)
        #expect(abs(sun.elevationDegrees - 25) < 0.001)
        #expect(sun.azimuthDegreesClockwiseFromNorth < 180)
        session.sunOffsetHours = 12
        let manualDate = session.sunDate
        session.previewPlace(place)
        #expect(session.sunDate == manualDate)
    }

    @Test func daylightHandlesPolarSitesAndPreservesMissionCalibration() throws {
        let coordinate = LMSelenographicCoordinate(latitudeDegrees: 90, longitudeDegrees: 0)
        let reference = LunarExplorerSession.apollo11TouchdownUTC
        let date = LunarExplorerSession.daylightDate(near: reference, coordinate: coordinate)
        #expect(abs(date.timeIntervalSince(reference)) <= 15 * 86_400)
        #expect(LMLunarEphemeris.sunAngles(at: date, site: coordinate).elevationDegrees.isFinite)
        let manifest = try LMTerrainManifest.load()
        let mission = LMLunarEphemeris.sunAngles(at: reference, site: manifest.landingOriginCoordinate)
        #expect(LunarExplorerSession.globeRadianceMatch(elevationDegrees: mission.elevationDegrees) == 5.70)
        #expect(abs(LunarExplorerSession.globeRadianceMatch(elevationDegrees: 25) - 5.80867) < 0.0001)
        #expect(LunarExplorerSession.globeRadianceMatch(elevationDegrees: 1) < 5.70)
        let inspection = LunarExplorerSession()
        inspection.configure(arguments: ["--lunar-explorer-capture"])
        #expect(inspection.sunDate == reference)
    }

    @Test func productZoomRequestsFinerTerrainWhileInspectorZoomDoesNot() {
        let s = LunarExplorerSession()
        s.select(.regional)
        s.exploreZoom(by: 24_000 / 700, from: 24_000)
        #expect(abs(s.altitudeMeters - 180) < 1e-8)
        #expect(abs(s.tiltDegrees - 58) < 1e-8)
        #expect(s.metersAcross == 700)
        s.zoom(by: 2, from: 700)
        #expect(s.altitudeMeters < 180)
        let reference = LunarExplorerSession()
        reference.configure(arguments: ["--lunar-explorer-capture", "--lunar-explorer-preset=terminal"])
        reference.zoom(by: 2, from: 700)
        #expect(reference.altitudeMeters == 180 && reference.metersAcross == 350)
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
