@testable import LunarMap
import Foundation
import Testing
import simd
import LMCore
@testable import LM

@Suite("Global rendered contact")
struct LMLunarContactTests {
    func region(at coordinate: LMSelenographicCoordinate) throws -> LMLunarTerrainRegion {
        let source = try #require(LMTerrainManifest.load().sources.first { $0.productId == "LDEM_16" })
        let url = try #require(LunarMap.resources.url(forResource: source.bundledFile, withExtension: nil, subdirectory: "Terrain"))
        let base = try LMLunarElevationGrid(data: Data(contentsOf: url, options: .mappedIfSafe), source: source)
        let terrain = LMLunarResolvedTerrain(base: base, refinements: [])
        let elevation = try #require(base.elevation(at: coordinate))
        let frame = LMSelenographicCoordinateSystem().localFrame(at: .init(latitudeDegrees: coordinate.latitudeDegrees,
                                                                          longitudeDegrees: coordinate.longitudeDegrees, heightMeters: elevation))
        return .init(terrain: terrain, frame: frame,
                     albedo: .init(width: 0, height: 0, halfExtentMeters: 0, luminance: []),
                     sourceIDs: [source.id], unavailableSourceIDs: [], measuredFloorMeters: base.spacingMeters)
    }

    @Test func contactReadsExactSubmittedTrianglesAndGearSettlesAtArbitraryAnchors() throws {
        for coordinate in [LMSelenographicCoordinate(latitudeDegrees: 8.35, longitudeDegrees: 30.83),
                           .init(latitudeDegrees: -42, longitudeDegrees: 120)] {
            let region = try region(at: coordinate)
            let field = LMLunarTerrainHeightField(terrain: region.terrain, frame: region.frame)
            let plan = LMTerrainTilePlan(id: .init(level: 1, eastIndex: 0, northIndex: 0),
                centerEastMeters: 0, centerNorthMeters: 0, sizeMeters: 16,
                sampleSpacingMeters: 0.125, containsProceduralSubresolution: true)
            let mesh = try #require(try Apollo11TerrainResource.makeProgressiveTileMeshData(heightField: field, plan: plan, activePlans: [plan]))
            let snapshot = LMLunarTerrainMeshSnapshot(tiles: [.init(plan: plan, mesh: mesh)])
            let surface = LMTerrainContactSurfaceBuilder.build(region: region, snapshot: snapshot)
            var maximumError = 0.0
            for i in 0..<1000 {
                let e = -7 + Double((i * 47) % 997) / 997 * 14
                let n = -7 + Double((i * 79) % 991) / 991 * 14
                let expected = try #require(snapshot.sample(east: e, north: n)).elevation
                maximumError = max(maximumError, abs(surface.surfaceHeightMeters(northMeters: n, eastMeters: e) - Double(expected)))
            }
            #expect(maximumError == 0)
            var drop = LMLunarLandingRehearsal(surface: surface, north: 0, east: 0)
            for _ in 0..<1800 { drop.step(); if drop.finished { break } }
            print("LUNAR_CONTACT lat=\(coordinate.latitudeDegrees) lon=\(coordinate.longitudeDegrees) triangleError=\(maximumError)m \(drop.message)")
            #expect(drop.isSettled)
            #expect(drop.gear.failure == nil)
            for leg in LMLandingGearLeg.allCases {
                let state = try #require(drop.gear.snapshot(leg))
                let pad = drop.position + drop.attitude.rotated(LMLandingGearGeometry.footpadBody(leg, strokeMeters: state.strokeMeters))
                let clearance = pad.z - surface.surfaceHeightMeters(northMeters: pad.x, eastMeters: pad.y)
                #expect(clearance >= -(state.regolithPenetrationMeters + LMLandingGearDynamics.regolithBearingLoadNewtons / LMLandingGearDynamics.padStiffnessNewtonsPerMeter + 0.01))
            }
        }
    }
}
