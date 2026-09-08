import Foundation
import LMCore
import RealityKit
import Testing
import simd
@testable import LM

@MainActor
@Suite(.serialized)
struct LMCockpitStartupLightingTests {
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
        #expect(initial.shadow?.shadowProjection == LMTerrainWorld.missionShadow(altitudeMeters: nearGround.altitudeMeters).shadowProjection)
        try await station.loadApollo11Terrain()
        let suns = LMCommanderStationAssembly.descendants(station.root).filter { $0.name == "MissionSun" }
        #expect(suns.count == 1)
        let prepared = try #require(suns.first as? DirectionalLight)
        #expect(prepared !== initial && prepared.light.intensity == initial.light.intensity)
        #expect(prepared.shadow?.shadowProjection == initial.shadow?.shadowProjection)
        #expect(abs(simd_dot(prepared.orientation(relativeTo: station.root).vector,
                             initial.orientation.vector)) > 0.99999)
    }
}
