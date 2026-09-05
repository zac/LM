import Foundation
import LMCore
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
        station.lunarWorld.position = SIMD3(100, 200, 300)
        station.installGlobalTerrain(terrain)
        #expect(station.lunarWorld.position == .zero)
        #expect(terrain.root.parent === station.lunarWorld)
        let state = LMVehicleStateSnapshot(positionMeters: .init(x: 40_000, y: -80_000, z: 300), landingSite: terrain.site)
        let expected = region.frame.moonCenteredPosition(for: .init(northMeters: 40_000, eastMeters: -80_000, upMeters: 300))
        let actual = LMAGCNavState.moonCenteredPositionMeters(from: state)
        #expect(abs(actual.x - expected.xMeters) < 1e-8)
        #expect(abs(actual.y - expected.yMeters) < 1e-8)
        #expect(abs(actual.z - expected.zMeters) < 1e-8)
    }
}
