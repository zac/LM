import Foundation
import Testing
import RealityKit
@testable import LM

@Suite("Lunar coarse-first refinement")
struct LMLunarTerrainRefinementTests {
    func plan(_ level: Int, spacing: Double, size: Double, east: Int) -> LMTerrainTilePlan {
        .init(id: .init(level: level, eastIndex: east, northIndex: 0),
              centerEastMeters: Double(east) * size + size / 2, centerNorthMeters: size / 2,
              sizeMeters: size, sampleSpacingMeters: spacing, containsProceduralSubresolution: true)
    }

    @Test func regionalRequestAdvancesOneCompleteLevelAtATime() {
        let plans = LMLunarTerrainPresentation.plans(sourceSpacing: 236.901175, east: 0, north: 0,
            altitude: 7_500, metersAcross: 24_000, heading: 0)
        #expect(plans.count == 16)
        var resident: Double?
        for (spacing, count) in [(512.0, 4), (128, 8), (32, 12), (8, 16)] {
            let next = LMLunarTerrainPresentation.nextRefinement(plans: plans, residentSpacing: resident)
            #expect(next.count == count)
            #expect(next.map(\.sampleSpacingMeters).min() == spacing)
            #expect(next == plans.filter { $0.sampleSpacingMeters >= spacing })
            resident = spacing
        }
        #expect(LMLunarTerrainPresentation.nextRefinement(plans: plans, residentSpacing: 0.125) == plans)
    }

    @Test @MainActor func concurrentSiblingsMatchSerialParentSampling() async throws {
        let region = try LMLunarContactTests().region(at: .init(latitudeDegrees: -42, longitudeDegrees: 120))
        let plans = [plan(2, spacing: 2, size: 16, east: 0), plan(2, spacing: 2, size: 16, east: 1),
                     plan(1, spacing: 1, size: 8, east: 0), plan(1, spacing: 1, size: 8, east: 1),
                     plan(0, spacing: 0.5, size: 4, east: 0), plan(0, spacing: 0.5, size: 4, east: 1)]
        let pipeline = LMTerrainDetailMode.procedural.makePipeline()
        var serial = [LMLunarTerrainMeshTile]()
        for plan in plans {
            var field = LMLunarTerrainHeightField(terrain: region.terrain, frame: region.frame)
            field.parents = .init(tiles: serial.reversed())
            let build = try #require(try await Apollo11TerrainResource.makeProgressiveTileEntityBuild(
                heightField: field, plan: plan, activePlans: plans, geometryReplacementPlans: plans,
                albedoField: region.albedo, detailPipeline: pipeline))
            serial.append(.init(plan: plan, mesh: build.mesh))
        }
        let concurrent = LMLunarTerrainPresentation(region: region, mode: .procedural)
        defer { concurrent.cancel() }
        var ready = false
        concurrent.update(plans: plans, east: 2, north: 2) { _, _, _, _, ms in ready = ms != nil }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !ready && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(ready)
        for expected in serial {
            let actual = try #require(concurrent.snapshot.tiles.first { $0.plan.id == expected.plan.id })
            #expect(actual.mesh.positions == expected.mesh.positions)
            #expect(actual.mesh.normals == expected.mesh.normals)
            #expect(actual.mesh.indices == expected.mesh.indices)
        }
    }

    @Test @MainActor func finerRequestDoesNotCancelCoarseGeneration() async throws {
        let region = try LMLunarContactTests().region(at: .init(latitudeDegrees: -42, longitudeDegrees: 120))
        let coarse = plan(2, spacing: 2, size: 16, east: 0)
        let middle = plan(1, spacing: 1, size: 8, east: 0)
        let fine = plan(0, spacing: 0.5, size: 4, east: 0)
        let terrain = LMLunarTerrainPresentation(region: region, mode: .procedural)
        defer { terrain.cancel() }
        var published = [Double]()
        let status: @MainActor (String, Int, Int, Double?, Int?) -> Void = { _, _, _, spacing, ms in
            if ms != nil, let spacing { published.append(spacing) }
        }
        terrain.updateProgressively(plans: [coarse], east: 2, north: 2, status: status)
        terrain.updateProgressively(plans: [coarse, middle, fine], east: 2, north: 2, status: status)
        #expect(terrain.generationRequestCount == 1)
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while published.last != 0.5 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(published == [2, 1, 0.5])
        #expect(terrain.generationRequestCount == 3)
        #expect(terrain.snapshot.tiles.count == 3)
        // The final visible mesh and contact ray use the same committed generation.
        let sample = try #require(terrain.snapshot.sample(east: 1.1, north: 1.3))
        let hit = try #require(terrain.snapshot.raycast(origin: SIMD3(1.3, sample.elevation + 10, -1.1),
                                                       direction: SIMD3(0, -1, 0)))
        #expect(abs(hit.position.y - sample.elevation) < 0.00001)
    }
}
