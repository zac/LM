import Foundation
import LMCore
import RealityKit
import simd
import Testing
@testable import LM

@Suite("Lunar cockpit mission context")
struct LMLunarCockpitMissionTests {
    @Test @MainActor func customSiteCannotStartFromAnApolloCheckpoint() throws {
        let session = PoweredDescentSession()
        let site = try LMLunarLandingSite(latitudeDegrees: -42, longitudeDegrees: 120, radiusMeters: 1_739_000)
        session.selectLandingSite(site)
        #expect(session.scenario.initialState.landingSite == site)
        #expect(session.recording == nil)
        session.start(from: .p65TerminalDescent)
        guard case .error = session.status else { Issue.record("Custom site accepted Apollo checkpoint"); return }
        #expect(!session.isRunning)
        session.selectLandingSite(nil)
        #expect(session.scenario.id == LMPoweredDescentScenario.apollo11SourceBacked.id)
        #expect(session.scenario.initialState.landingSite == nil)
        session.stop()
    }

    @Test @MainActor func launchCoordinateUsesTheExistingValidatedParser() {
        let app = MainMenuViewModel(arguments: ["--cockpit-coordinate=-42,120"])
        #expect(app.cockpitCoordinate?.latitudeDegrees == -42)
        #expect(app.cockpitCoordinate?.longitudeDegrees == 120)
        let invalid = MainMenuViewModel(arguments: ["--cockpit-coordinate=91,120"])
        #expect(invalid.cockpitCoordinate == nil)
    }

    @Test @MainActor func regionDatumMatchesAGCMoonCenteredOrigin() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LMLunarElevationStore(directory: directory)
        let coordinate = LMSelenographicCoordinate(latitudeDegrees: -42, longitudeDegrees: 120)
        let region = try await LMLunarTerrainRegion.load(at: coordinate, store: store, offline: true)
        let terrain = try LMLunarCockpitTerrain(region: region, gate: .init(), date: LunarExplorerSession.apollo11TouchdownUTC)
        let station = LMCommanderStationScene()
        station.prepareProvisionalLighting(at: coordinate, date: LunarExplorerSession.apollo11TouchdownUTC)
        let provisionalSun = try #require(station.root.findEntity(named: "MissionSun") as? DirectionalLight)
        #expect(provisionalSun.light.intensity == terrain.sun.light.intensity)
        #expect(provisionalSun.shadow != nil && terrain.sun.shadow != nil)
        #expect(abs(simd_dot(provisionalSun.orientation.vector, terrain.sun.orientation.vector)) > 0.99999)
        let rotatedState = LMVehicleStateSnapshot(positionMeters: .init(z: 300),
            attitude: .init(w: cos(0.3), z: sin(0.3)), landingSite: terrain.site)
        station.apply(rotatedState)
        let worldSunBefore = provisionalSun.orientation(relativeTo: station.root)
        let shadowBefore = try #require(station.cockpitShadowFit)
        station.lunarWorld.position = SIMD3(100, 200, 300)
        station.installGlobalTerrain(terrain)
        #expect(abs(simd_dot(worldSunBefore.vector, terrain.sun.orientation(relativeTo: station.root).vector)) > 0.99999)
        #expect(abs((try #require(station.cockpitShadowFit)).span - shadowBefore.span) < 0.0001)
        #expect(station.lunarWorld.position == .zero)
        #expect(terrain.root.parent === station.lunarWorld)
        #expect(LMCommanderStationAssembly.descendants(station.root).filter { $0.name == "MissionSun" }.count == 1)
        let state = LMVehicleStateSnapshot(positionMeters: .init(x: 40_000, y: -80_000, z: 300), landingSite: terrain.site)
        let expected = region.frame.moonCenteredPosition(for: .init(northMeters: 40_000, eastMeters: -80_000, upMeters: 300))
        let actual = LMAGCNavState.moonCenteredPositionMeters(from: state)
        #expect(abs(actual.x - expected.xMeters) < 1e-8)
        #expect(abs(actual.y - expected.yMeters) < 1e-8)
        #expect(abs(actual.z - expected.zMeters) < 1e-8)
    }
}
