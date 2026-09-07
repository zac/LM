import Foundation
import simd

extension LunarExplorerSession {
    /// Immutable scene inputs. UI-only state and scene diagnostic outputs are
    /// intentionally absent, so publication cannot request another scene step.
    struct ScenePlace: Equatable {
        let id: String
        let coordinate: LMSelenographicCoordinate
    }

    struct SceneSnapshot: Equatable {
        let camera: LunarExplorerCamera
        let heading: Double
        let planningHeading: Double
        let north: Double
        let east: Double
        let opacity: Float
        let windowPosition: SIMD3<Float>
        let browse: LMSelenographicCoordinate
        let current: LMSelenographicCoordinate?
        let destination: LMSelenographicCoordinate?
        let flight: LMSelenographicCoordinate?
        let navigationRevision: Int
        let navigationPhase: NavigationPhase
        let pendingArrival: Bool
        let landingRequest: Int
        let landingRunning: Bool
        let bundledSite: Bool
        let panBounds: LunarExplorerPanBounds
        let browsing: Bool
        let explorer: Bool
        let window: Bool
        let portal: Bool
        let selectedPlaceID: String?
        let places: [ScenePlace]
        let preset: Preset
        let date: Date
        let detail: LMTerrainDetailMode
        let grade: LMTerrainPresentationGrade
        let shadows: Bool
        let offline: Bool
        let elevationCoordinate: LMSelenographicCoordinate?
        let elevationOffline: Bool
        let reanchorProbe: Bool
        let referencePresentation: CapturePresentation?
        let unmatchedRadiance: Bool
    }

    var sceneSnapshot: SceneSnapshot {
        .init(camera: camera, heading: headingDegrees, planningHeading: terrainPlanningHeadingDegrees,
              north: focusNorthOffsetMeters, east: focusEastOffsetMeters, opacity: transitionOpacity,
              windowPosition: globePosition, browse: browseCoordinate, current: currentCoordinate,
              destination: destinationCoordinate, flight: flightCoordinate,
              navigationRevision: navigationRevision, navigationPhase: navigationPhase,
              pendingArrival: pendingArrival, landingRequest: landingRequest, landingRunning: landingRunning,
              bundledSite: usesBundledSite, panBounds: residentPanBounds, browsing: isBrowsingGlobe, explorer: isExplorerExperience,
              window: usesWindowContainer, portal: portalEnabled, selectedPlaceID: selectedPlaceID,
              places: catalogPlaces.map { .init(id: $0.id, coordinate: $0.coordinate) },
              preset: selectedPreset, date: sunDate,
              detail: detailMode, grade: presentationGrade, shadows: missionShadowsEnabled,
              offline: regionOffline, elevationCoordinate: captureElevationCoordinate,
              elevationOffline: captureElevationOffline, reanchorProbe: captureReanchorProbe,
              referencePresentation: capturePresentation, unmatchedRadiance: captureUnmatchedGlobeRadiance)
    }
}
