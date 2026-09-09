@testable import LunarMap
@testable import LunarMapExplorer
import Foundation
import LMCore
import RealityKit
import Testing
import simd
@testable import LM

@MainActor
@Suite(.serialized)
struct LMCockpitStartupLightingTests {
    @Test func invalidFitRestoresSourcePositionAndCanRecover() throws {
        let station = LMCommanderStationScene(loadACA: false)
        let sun = try #require(station.root.findEntity(named: "MissionSun") as? DirectionalLight)
        let original = sun.orientation
        #expect(station.cockpitShadowFit != nil)
        sun.orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        station.apply(LMVehicleStateSnapshot(positionMeters: .init(z: 2)))
        #expect(station.cockpitShadowFit == nil)
        #expect(sun.position == .zero)
        sun.orientation = original
        station.apply(LMVehicleStateSnapshot(positionMeters: .init(z: 2)))
        #expect(station.cockpitShadowFit != nil)
        #expect(sun.position != .zero)
    }

    @Test func missingLightingMetadataKeepsUsableShadowedFallback() throws {
        let station = LMCommanderStationScene(loadACA: false, lightingManifest: nil)
        let sun = try #require(station.root.findEntity(named: "MissionSun") as? DirectionalLight)
        #expect(sun.shadow != nil && abs(sun.light.intensity - LMTerrainWorld.missionSunIlluminanceLux) < 1)
        #expect(abs(simd_length(sun.orientation.vector) - 1) < 0.00001)
        #expect(abs(sun.orientation.real - 1) < 0.00001)
    }
    @Test func provisionalAndPreparedApolloUseSameMissionSun() async throws {
        let station = LMCommanderStationScene()
        let manifest = try LMTerrainManifest.load()
        let initial = try #require(station.root.findEntity(named: "MissionSun") as? DirectionalLight)
        #expect(initial.light.intensity == LMTerrainWorld.missionSunIlluminance(elevationDegrees: manifest.sun.elevationDegrees))
        #expect(initial.shadow != nil)
        let expected = LMFullDescentMapper.sunLightOrientation(from: manifest)
        #expect(abs(simd_dot(initial.orientation.vector, expected.vector)) > 0.99999)
        // The same light remains usable indefinitely while terrain is absent or fails.
        station.prepareProvisionalLighting(at: nil, date: LunarExplorerSession.apollo11TouchdownUTC)
        #expect(station.root.findEntity(named: "MissionSun") === initial)
        let nearGround = LMVehicleStateSnapshot(positionMeters: .init(z: 2))
        station.apply(nearGround)
        #expect(station.cockpitShadowFit != nil)
        let beforeSpan = station.cockpitShadowFit?.span
        try await station.loadApollo11Terrain()
        let suns = LMCommanderStationAssembly.descendants(station.root).filter { $0.name == "MissionSun" }
        #expect(suns.count == 1)
        let prepared = try #require(suns.first as? DirectionalLight)
        #expect(prepared !== initial && prepared.light.intensity == initial.light.intensity)
        #expect(station.cockpitShadowFit?.span == beforeSpan)
        #expect(abs(simd_dot(prepared.orientation(relativeTo: station.root).vector,
                             initial.orientation.vector)) > 0.99999)
    }
}
