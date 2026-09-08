@testable import LunarMap
import Foundation
import Testing
@testable import LM

@Suite("Streaming terrain detail")
struct LMTerrainDetailStreamingTests {
    @Test func pipelinePreparationWarmsGenerator() async {
        let generator = CountingDetailGenerator(modelID: "test-detail-v1")
        let pipeline = LMTerrainDetailPipeline(generator: generator)

        await pipeline.prepare()

        #expect(await generator.prepareCount() == 1)
    }

    @Test func bundledCoreMLModelGeneratesSeamSafeTile() async throws {
        let generator = try LMCoreMLTerrainDetailGenerator()
        let preparationStarted = ContinuousClock.now
        await generator.prepare()
        let preparationElapsed = milliseconds(
            preparationStarted.duration(to: .now)
        )
        // Internal same-level edges keep full procedural detail, but the
        // independent neural residual still restores the exact procedural
        // boundary through its narrow inference collar.
        let plan = tilePlan(eastIndex: 4, transitionEdges: [])
        let procedural = try LMTerrainTileDetailBaker.bake(
            plan: plan,
            albedoField: nil
        )
        let started = ContinuousClock.now
        let generated = try await generator.generate(
            plan: plan,
            albedoField: nil
        )
        let coldElapsed = milliseconds(started.duration(to: .now))
        let inferenceMilliseconds = try await generator.predictionMilliseconds(
            iterations: 4
        )
        var reconstructionMilliseconds = [Int]()
        var lastReconstruction: LMTerrainTileDetailTextures?
        for _ in 0..<3 {
            let reconstructionStarted = ContinuousClock.now
            lastReconstruction = try await generator.reconstruct(
                procedural,
                transitionEdges: []
            )
            reconstructionMilliseconds.append(milliseconds(
                reconstructionStarted.duration(to: .now)
            ))
        }

        #expect(generated.resolution == 512)
        #expect(generated.albedo.count == 512 * 512 * 4)
        #expect(generated.normal == procedural.normal)
        #expect(generated.normalDistribution == procedural.normalDistribution)
        #expect(edgesMatch(generated.albedo, procedural.albedo, resolution: 512))
        let interiorChangedPixels = changedPixelCount(
            generated.albedo,
            procedural.albedo,
            resolution: 512,
            inset: 64
        )
        #expect(interiorChangedPixels > 1_000)
        #expect(
            gradientEnergy(generated.albedo, resolution: 512, inset: 64)
                >= gradientEnergy(procedural.albedo, resolution: 512, inset: 64)
                    * 0.98
        )
        #expect(
            abs(
                meanLuminance(generated.albedo, resolution: 512, inset: 64)
                    - meanLuminance(
                        procedural.albedo,
                        resolution: 512,
                        inset: 64
                    )
            ) < 1
        )
        #expect(Swift.stride(
            from: 3,
            to: generated.albedo.count,
            by: 4
        ).allSatisfy { generated.albedo[$0] == 255 })
        #expect(coldElapsed < 8_000)
        #expect((inferenceMilliseconds.dropFirst().min() ?? .max) < 100)
        #expect(lastReconstruction?.albedo == generated.albedo)
        print("coreml_terrain_preparation_ms=\(preparationElapsed)")
        print("coreml_terrain_cold_generation_ms=\(coldElapsed)")
        print("coreml_terrain_inference_ms=\(inferenceMilliseconds)")
        print("coreml_terrain_reconstruction_ms=\(reconstructionMilliseconds)")
        print("coreml_terrain_albedo_fnv1a64=\(fnv1a64(generated.albedo))")
    }

    @Test func missingModelReturnsCompleteProceduralTile() async throws {
        let generator = LMAutomaticTerrainDetailGenerator(neural: nil)
        let plan = tilePlan(eastIndex: 5)
        let expected = try LMTerrainTileDetailBaker.bake(
            plan: plan,
            albedoField: nil
        )

        let generated = try await generator.generate(
            plan: plan,
            albedoField: nil
        )

        #expect(generator.modelID == LMTerrainTileDetailBaker.modelID)
        #expect(generated.resolution == expected.resolution)
        #expect(generated.albedo == expected.albedo)
        #expect(generated.normal == expected.normal)
    }

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

    @Test func cacheKeyIncludesFootprintEdgeOwnership() async throws {
        let generator = CountingDetailGenerator(modelID: "test-detail-v1")
        let cache = LMTerrainDetailCache(byteLimit: 64)
        let pipeline = LMTerrainDetailPipeline(generator: generator, cache: cache)
        let perimeter = tilePlan(eastIndex: 8, transitionEdges: .all)
        let interior = tilePlan(eastIndex: 8, transitionEdges: [])

        _ = try await pipeline.textures(plan: perimeter, albedoField: nil)
        let changed = try await pipeline.textures(plan: interior, albedoField: nil)

        #expect(!changed.cacheHit)
        #expect(await generator.count() == 2)
        #expect(await cache.statistics().entryCount == 2)
    }

    private func tilePlan(
        eastIndex: Int,
        transitionEdges: LMTerrainTileEdges = .all
    ) -> LMTerrainTilePlan {
        LMTerrainTilePlan(
            id: .init(level: 1, eastIndex: eastIndex, northIndex: -2),
            centerEastMeters: Double(eastIndex * 16) + 8,
            centerNorthMeters: -24,
            sizeMeters: 16,
            sampleSpacingMeters: 0.125,
            containsProceduralSubresolution: true,
            transitionEdges: transitionEdges
        )
    }

    private func milliseconds(_ duration: ContinuousClock.Duration) -> Int {
        Int(
            duration.components.seconds * 1_000
                + duration.components.attoseconds / 1_000_000_000_000_000
        )
    }

    private func edgesMatch(
        _ first: [UInt8],
        _ second: [UInt8],
        resolution: Int
    ) -> Bool {
        for coordinate in 0..<resolution {
            let offsets = [
                coordinate * 4,
                ((resolution - 1) * resolution + coordinate) * 4,
                (coordinate * resolution) * 4,
                (coordinate * resolution + resolution - 1) * 4,
            ]
            for offset in offsets where !first[offset..<(offset + 4)].elementsEqual(
                second[offset..<(offset + 4)]
            ) {
                return false
            }
        }
        return true
    }

    private func changedPixelCount(
        _ first: [UInt8],
        _ second: [UInt8],
        resolution: Int,
        inset: Int
    ) -> Int {
        var count = 0
        for row in inset..<(resolution - inset) {
            for column in inset..<(resolution - inset) {
                let offset = (row * resolution + column) * 4
                if first[offset] != second[offset] {
                    count += 1
                }
            }
        }
        return count
    }

    private func gradientEnergy(
        _ rgba: [UInt8],
        resolution: Int,
        inset: Int
    ) -> Double {
        var energy = 0.0
        var count = 0
        for row in inset..<(resolution - inset - 1) {
            for column in inset..<(resolution - inset - 1) {
                let pixel = Double(rgba[(row * resolution + column) * 4])
                let east = Double(rgba[(row * resolution + column + 1) * 4])
                let south = Double(
                    rgba[((row + 1) * resolution + column) * 4]
                )
                energy += abs(east - pixel) + abs(south - pixel)
                count += 2
            }
        }
        return energy / Double(max(count, 1))
    }

    private func meanLuminance(
        _ rgba: [UInt8],
        resolution: Int,
        inset: Int
    ) -> Double {
        var total = 0.0
        var count = 0
        for row in inset..<(resolution - inset) {
            for column in inset..<(resolution - inset) {
                total += Double(rgba[(row * resolution + column) * 4])
                count += 1
            }
        }
        return total / Double(max(count, 1))
    }

    private func fnv1a64(_ bytes: [UInt8]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private actor CountingDetailGenerator: LMTerrainDetailGenerating {
    nonisolated let modelID: String
    private var generationCount = 0
    private var preparationCount = 0

    init(modelID: String) {
        self.modelID = modelID
    }

    func prepare() {
        preparationCount += 1
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

    func prepareCount() -> Int {
        preparationCount
    }
}
