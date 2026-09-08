@testable import LunarMapExplorer
@testable import LunarMap
import Testing
import Observation
import Synchronization
import simd
@testable import LM

@Suite("Moon map controls") @MainActor
struct LunarExplorerMapTests {
    @Test func unchangedTerrainDiagnosticsDoNotInvalidateTheObservedScene() {
        let session = LunarExplorerSession()
        let invalidated = Mutex(false)
        withObservationTracking {
            _ = session.diagnostics.activeTileCount
        } onChange: {
            invalidated.withLock { $0 = true }
        }
        let scene = LunarExplorerScene()
        scene.pendingDiagnostics = session.diagnostics
        scene.publishPendingDiagnostics(to: session)
        #expect(!invalidated.withLock { $0 })
        var changed = session.diagnostics
        changed.activeTileCount = 1
        scene.pendingDiagnostics = changed
        scene.publishPendingDiagnostics(to: session)
        #expect(invalidated.withLock { $0 })
        #expect(session.diagnostics.activeTileCount == 1)
    }

    @Test func sceneSnapshotExcludesUIAndDiagnosticOutputs() {
        let session = LunarExplorerSession()
        session.configure(arguments: [])
        let original = session.sceneSnapshot
        let invalidated = Mutex(false)
        withObservationTracking { _ = session.sceneSnapshot } onChange: {
            invalidated.withLock { $0 = true }
        }
        session.diagnostics.activeTileCount = 4
        session.diagnosticsVisible.toggle()
        #expect(session.sceneSnapshot == original)
        #expect(!invalidated.withLock { $0 })
        session.headingDegrees += 30
        #expect(session.sceneSnapshot != original)
        #expect(invalidated.withLock { $0 })
    }

    @Test func changedDiagnosticsPublishOnlyOnce() {
        let session = LunarExplorerSession()
        let scene = LunarExplorerScene()
        scene.pendingDiagnostics.activeTileCount = 2
        scene.publishPendingDiagnostics(to: session)
        let invalidated = Mutex(false)
        withObservationTracking { _ = session.diagnostics } onChange: {
            invalidated.withLock { $0 = true }
        }
        for _ in 0..<120 { scene.publishPendingDiagnostics(to: session) }
        #expect(!invalidated.withLock { $0 })
        #expect(session.diagnostics.activeTileCount == 2)
    }

    @Test func selectedDestinationSurvivesRotationAndModeSwitch() throws {
        let session = LunarExplorerSession()
        session.configure(arguments: [])
        let place = try #require(session.catalogPlaces.first { $0.id == "apollo-17" })
        session.previewPlace(place)
        session.rotateGlobe(from: session.browseCoordinate, horizontal: 800, vertical: 40)
        #expect(session.browseCoordinate != place.coordinate)
        #expect(session.displayedCoordinate == place.coordinate)
        #expect(session.selectedMarkerPlace?.id == place.id)
        session.setExplorerMode("surface")
        #expect(session.flightCoordinate == place.coordinate)
        #expect(session.navigationInProgress)
        session.returnToGlobe()
    }

    @Test func optionalRotationStopsForMotionPreferenceAndManipulation() throws {
        let session = LunarExplorerSession()
        session.configure(arguments: [])
        let place = try #require(session.catalogPlaces.first { $0.id == "apollo-11" })
        session.previewPlace(place)
        let initial = session.browseCoordinate
        session.advanceGlobeRotation(seconds: 0.05)
        #expect(session.browseCoordinate == initial)
        session.automaticallyRotatesGlobe = true
        session.advanceGlobeRotation(seconds: 0.05)
        #expect(session.browseCoordinate != initial)
        #expect(session.selectedPlaceID == place.id)
        let rotated = session.browseCoordinate
        session.isManipulatingGlobe = true
        session.advanceGlobeRotation(seconds: 0.05)
        #expect(session.browseCoordinate == rotated)
        session.isManipulatingGlobe = false
        session.reduceMotion = true
        session.advanceGlobeRotation(seconds: 0.05)
        #expect(session.browseCoordinate == rotated)
    }

    @Test func globeDirectionsAndHorizonRespectPolesAndDateline() {
        let center = LMSelenographicCoordinate(latitudeDegrees: 0, longitudeDegrees: 179)
        let front = LunarExplorerMapGeometry.direction(to: center, centeredOn: center)
        let back = LunarExplorerMapGeometry.direction(to: .init(latitudeDegrees: 0, longitudeDegrees: -1), centeredOn: center)
        #expect(simd_distance(front, SIMD3(0, 0, 1)) < 1e-6)
        #expect(simd_distance(back, SIMD3(0, 0, -1)) < 1e-6)
        let east = LunarExplorerMapGeometry.direction(to: .init(latitudeDegrees: 0, longitudeDegrees: -179), centeredOn: center)
        #expect(east.x > 0 && east.z > 0.99)
        let pole = LunarExplorerMapGeometry.direction(to: .init(latitudeDegrees: 90, longitudeDegrees: 0), centeredOn: center)
        #expect(simd_distance(pole, SIMD3(0, 1, 0)) < 1e-6)
        let position = SIMD3<Float>(1.05, 0, -2)
        #expect(LunarExplorerMapGeometry.isVisible(direction: front, globePosition: position, radius: 0.4))
        #expect(!LunarExplorerMapGeometry.isVisible(direction: back, globePosition: position, radius: 0.4))
        #expect(!LunarExplorerMapGeometry.isVisible(direction: SIMD3(1, 0, 0), globePosition: position, radius: 0.4))
    }
}
