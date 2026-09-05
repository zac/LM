import Foundation
import RealityKit
import Testing
import simd
@testable import LM

@Suite("Global terrain transitions")
struct LMLunarTerrainTransitionTests {
    /// A nonzero refinement over a flat parent exposes discontinuous collars
    /// without depending on a particular random crater landing on the edge.
    private struct Refinement: LMTerrainHeightField {
        let spacingMeters = 1_895.0
        let width = 1_025, height = 1_025
        var craterCatalog: LMLunarCraterCatalog? { nil }
        var resolvesProceduralSamples: Bool { true }
        func relativeElevation(eastMeters: Double, northMeters: Double) -> Float? { 0 }
        func interpolatedSurfaceNormal(eastMeters: Double, northMeters: Double) -> SIMD3<Float>? { SIMD3(0, 1, 0) }
        func resolvedSample(eastMeters: Double, northMeters: Double, requestedSpacingMeters: Double) -> LMResolvedTerrainSample? {
            .init(measuredElevationMeters: 0, proceduralResidualMeters: 0.2, elevationMeters: 0.2,
                  provenance: .measuredWithProceduralSubresolution)
        }
        func renderedParent(eastMeters: Double, northMeters: Double, spacingMeters: Double) -> LMLunarTerrainMeshTile.Sample? {
            .init(elevation: 0, normal: SIMD3(0, 1, 0), spacing: spacingMeters * 4)
        }
    }

    @Test @MainActor func fullyOwnedParentRetainsSamplesWithoutUploadingEmptyMesh() async throws {
        let parent = LMTerrainTilePlan(id: .init(level: 0, eastIndex: 0, northIndex: 0),
                                      centerEastMeters: 2, centerNorthMeters: 2, sizeMeters: 4,
                                      sampleSpacingMeters: 1, containsProceduralSubresolution: true)
        let child = LMTerrainTilePlan(id: .init(level: 1, eastIndex: 0, northIndex: 0),
                                     centerEastMeters: 2, centerNorthMeters: 2, sizeMeters: 4,
                                     sampleSpacingMeters: 0.5, containsProceduralSubresolution: true)
        let result = try await Apollo11TerrainResource.makeProgressiveTileEntityBuild(
            heightField: Refinement(), plan: parent, activePlans: [parent, child],
            geometryReplacementPlans: [child], albedoField: nil,
            detailPipeline: LMTerrainDetailMode.procedural.makePipeline())
        let build = try #require(result)
        #expect(build.mesh.indices.isEmpty)
        #expect(!build.mesh.positions.isEmpty)
        #expect(build.entity.components[ModelComponent.self] == nil)
        #expect(LMLunarTerrainMeshTile(plan: parent, mesh: build.mesh).sample(east: 2, north: 2) != nil)
    }

    @Test @MainActor func cancelledRequestCanBeRetriedWithoutPublishingGeometry() throws {
        let region = try LMLunarContactTests().region(at: .init(latitudeDegrees: -42, longitudeDegrees: 120))
        let presentation = LMLunarTerrainPresentation(region: region, mode: .procedural)
        var requests = 0
        func request() {
            presentation.update(east: 0, north: 0, altitude: 2, metersAcross: 8, heading: 0) { message, _, _, _, _ in
                if message == "Building lunar terrain" { requests += 1 }
            }
        }
        request()
        presentation.cancel()
        #expect(presentation.snapshot.tiles.isEmpty)
        request()
        #expect(requests == 2)
        presentation.cancel()
        #expect(presentation.snapshot.tiles.isEmpty)
    }

    @Test func obliqueFootprintAppearanceEdgesMatchByteForByte() throws {
        let plans = LMLunarTerrainPresentation.plans(sourceSpacing: 1_895, east: 0, north: 0,
                                                    altitude: 2, metersAcross: 8, heading: 35)
        let fine = plans.filter { $0.sampleSpacingMeters == 0.125 }
        let northIndex = try #require(fine.map(\.id.northIndex).max())
        let row = fine.filter { $0.id.northIndex == northIndex }.sorted { $0.id.eastIndex < $1.id.eastIndex }
        let resolution = 65
        let tiles = try row.map { try LMTerrainTileDetailBaker.bake(plan: $0, albedoField: nil, resolution: resolution) }
        for pair in zip(tiles, tiles.dropFirst()) {
            for y in 0..<resolution {
                let a = (y * resolution + resolution - 1) * 4
                let b = y * resolution * 4
                #expect(Array(pair.0.albedo[a..<a + 4]) == Array(pair.1.albedo[b..<b + 4]))
                #expect(Array(pair.0.normal[a..<a + 4]) == Array(pair.1.normal[b..<b + 4]))
            }
        }
    }

    @Test func rayInspectionHonorsSubmittedTriangleHoles() throws {
        let plan = LMTerrainTilePlan(id: .init(level: 0, eastIndex: 0, northIndex: 0),
                                    centerEastMeters: 1, centerNorthMeters: 1, sizeMeters: 2,
                                    sampleSpacingMeters: 2, containsProceduralSubresolution: false)
        let mesh = LMProgressiveTerrainMeshData(
            positions: [SIMD3(1, 0, 1), SIMD3(1, 0, -1), SIMD3(-1, 0, 1), SIMD3(-1, 0, -1)],
            normals: Array(repeating: SIMD3(0, 1, 0), count: 4), tangents: [], bitangents: [],
            addedReliefNormalDistribution: .flat, textureCoordinates: [], indices: [0, 1, 2])
        let snapshot = LMLunarTerrainMeshSnapshot(tiles: [.init(plan: plan, mesh: mesh)])
        let hit = try #require(snapshot.raycast(origin: SIMD3(1.75, 2, -0.25), direction: SIMD3(0, -1, 0)))
        #expect(hit.distance == 2)
        #expect(hit.position.y == 0)
        #expect(snapshot.raycast(origin: SIMD3(0.25, 2, -1.75), direction: SIMD3(0, -1, 0)) == nil)
    }

    @Test func obliqueViewFootprintsHaveContinuousSharedMorphCollars() throws {
        let sampler = LMProgressiveTerrainSurfaceSampler(heightField: Refinement())
        for heading in [0.0, 17, 35, 90, 135] {
            let plans = LMLunarTerrainPresentation.plans(sourceSpacing: 1_895, east: 0, north: 0,
                                                        altitude: 2, metersAcross: 8, heading: heading)
            var maximumError: Float = 0
            for plan in plans {
                for neighbor in plans where neighbor.id.level == plan.id.level &&
                    ((neighbor.id.eastIndex == plan.id.eastIndex + 1 && neighbor.id.northIndex == plan.id.northIndex) ||
                     (neighbor.id.northIndex == plan.id.northIndex + 1 && neighbor.id.eastIndex == plan.id.eastIndex)) {
                    for fraction in [0.0, 0.03125, 0.125, 0.5, 0.875, 0.96875, 1] {
                        let east = neighbor.id.eastIndex != plan.id.eastIndex
                            ? plan.centerEastMeters + plan.sizeMeters / 2
                            : plan.centerEastMeters + (fraction - 0.5) * plan.sizeMeters
                        let north = neighbor.id.northIndex != plan.id.northIndex
                            ? plan.centerNorthMeters + plan.sizeMeters / 2
                            : plan.centerNorthMeters + (fraction - 0.5) * plan.sizeMeters
                        let a = try #require(sampler.renderedElevation(eastMeters: east, northMeters: north, plan: plan, activePlans: plans))
                        let b = try #require(sampler.renderedElevation(eastMeters: east, northMeters: north, plan: neighbor, activePlans: plans))
                        maximumError = max(maximumError, abs(a - b))
                    }
                }
            }
            print("LUNAR_TRANSITION heading=\(heading) tiles=\(plans.count) sharedEdgeError=\(maximumError)m")
            #expect(maximumError == 0)
        }
    }
}
