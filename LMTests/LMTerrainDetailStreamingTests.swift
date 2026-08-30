import Foundation
import Testing
@testable import LM

@Suite("Streaming terrain detail")
struct LMTerrainDetailStreamingTests {
    @Test func repeatedTileUsesBoundedMemoryCache() async throws {
        let generator = CountingDetailGenerator(modelID: "test-detail-v1")
        let cache = LMTerrainDetailCache(byteLimit: 64)
        let pipeline = LMTerrainDetailPipeline(
            generator: generator,
            cache: cache
        )
        let plan = tilePlan(eastIndex: 4)

        let first = try await pipeline.textures(plan: plan, albedoField: nil)
        let second = try await pipeline.textures(plan: plan, albedoField: nil)

        #expect(!first.cacheHit)
        #expect(second.cacheHit)
        #expect(first.modelID == "test-detail-v1")
        #expect(second.textures.albedo == first.textures.albedo)
        #expect(await generator.count() == 1)
        let statistics = await cache.statistics()
        #expect(statistics.entryCount == 1)
        #expect(statistics.byteCount == 8)
        #expect(statistics.hitCount == 1)
        #expect(statistics.missCount == 1)
    }

    @Test func leastRecentlyUsedTileIsEvictedAtByteLimit() async throws {
        let generator = CountingDetailGenerator(modelID: "test-detail-v1")
        let cache = LMTerrainDetailCache(byteLimit: 16)
        let pipeline = LMTerrainDetailPipeline(generator: generator, cache: cache)
        let first = tilePlan(eastIndex: 1)
        let second = tilePlan(eastIndex: 2)
        let third = tilePlan(eastIndex: 3)

        _ = try await pipeline.textures(plan: first, albedoField: nil)
        _ = try await pipeline.textures(plan: second, albedoField: nil)
        _ = try await pipeline.textures(plan: first, albedoField: nil)
        _ = try await pipeline.textures(plan: third, albedoField: nil)
        let regeneratedSecond = try await pipeline.textures(
            plan: second,
            albedoField: nil
        )

        #expect(!regeneratedSecond.cacheHit)
        #expect(await generator.count() == 4)
        let statistics = await cache.statistics()
        #expect(statistics.entryCount == 2)
        #expect(statistics.byteCount == 16)
        #expect(statistics.evictionCount == 2)
    }

    @Test func cacheKeyIncludesModelVersion() async throws {
        let cache = LMTerrainDetailCache(byteLimit: 64)
        let firstGenerator = CountingDetailGenerator(modelID: "test-detail-v1")
        let secondGenerator = CountingDetailGenerator(modelID: "test-detail-v2")
        let firstPipeline = LMTerrainDetailPipeline(
            generator: firstGenerator,
            cache: cache
        )
        let secondPipeline = LMTerrainDetailPipeline(
            generator: secondGenerator,
            cache: cache
        )
        let plan = tilePlan(eastIndex: 8)

        _ = try await firstPipeline.textures(plan: plan, albedoField: nil)
        let second = try await secondPipeline.textures(plan: plan, albedoField: nil)

        #expect(!second.cacheHit)
        #expect(await firstGenerator.count() == 1)
        #expect(await secondGenerator.count() == 1)
        #expect(await cache.statistics().entryCount == 2)
    }

    private func tilePlan(eastIndex: Int) -> LMTerrainTilePlan {
        LMTerrainTilePlan(
            id: .init(level: 1, eastIndex: eastIndex, northIndex: -2),
            centerEastMeters: Double(eastIndex * 16) + 8,
            centerNorthMeters: -24,
            sizeMeters: 16,
            sampleSpacingMeters: 0.125,
            containsProceduralSubresolution: true
        )
    }
}

private actor CountingDetailGenerator: LMTerrainDetailGenerating {
    nonisolated let modelID: String
    private var generationCount = 0

    init(modelID: String) {
        self.modelID = modelID
    }

    func generate(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?
    ) async throws -> LMTerrainTileDetailTextures {
        try Task.checkCancellation()
        generationCount += 1
        let value = UInt8(truncatingIfNeeded: plan.id.eastIndex)
        return LMTerrainTileDetailTextures(
            resolution: 1,
            albedo: [value, value, value, 255],
            normal: [128, 128, 255, 255]
        )
    }

    func count() -> Int {
        generationCount
    }
}
