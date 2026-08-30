import Foundation

/// Runtime boundary between terrain residency and appearance synthesis.
///
/// A production neural implementation can conform to this protocol without
/// changing tile planning, cancellation, mesh generation, or RealityKit
/// realization. The procedural implementation remains the deadline-safe
/// fallback and the reference used by tests.
protocol LMTerrainDetailGenerating: Sendable {
    var modelID: String { get }

    func generate(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?
    ) async throws -> LMTerrainTileDetailTextures
}

struct LMProceduralTerrainDetailGenerator: LMTerrainDetailGenerating {
    let modelID = LMTerrainTileDetailBaker.modelID

    func generate(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?
    ) async throws -> LMTerrainTileDetailTextures {
        try Task.checkCancellation()
        return try LMTerrainTileDetailBaker.bake(
            plan: plan,
            albedoField: albedoField
        )
    }
}

/// Cost-bounded, deterministic cache for generated appearance tiles.
///
/// The cache intentionally owns no generation tasks. The scene already gives
/// each stable tile ID one cancellable task, so keeping task ownership there
/// prevents an obsolete request from leaving detached model work behind.
actor LMTerrainDetailCache {
    struct Key: Hashable, Sendable {
        let modelID: String
        let tileID: LMTerrainTileID
        let sizeBitPattern: UInt64
        let spacingBitPattern: UInt64

        init(modelID: String, plan: LMTerrainTilePlan) {
            self.modelID = modelID
            tileID = plan.id
            sizeBitPattern = plan.sizeMeters.bitPattern
            spacingBitPattern = plan.sampleSpacingMeters.bitPattern
        }
    }

    struct Statistics: Equatable, Sendable {
        let entryCount: Int
        let byteCount: Int
        let hitCount: Int
        let missCount: Int
        let evictionCount: Int
    }

    private struct Entry: Sendable {
        let textures: LMTerrainTileDetailTextures
        let byteCount: Int
        var access: UInt64
    }

    let byteLimit: Int
    private var entries: [Key: Entry] = [:]
    private var byteCount = 0
    private var access = UInt64.zero
    private var hitCount = 0
    private var missCount = 0
    private var evictionCount = 0

    init(byteLimit: Int = 32 * 1_024 * 1_024) {
        self.byteLimit = max(0, byteLimit)
    }

    func value(for key: Key) -> LMTerrainTileDetailTextures? {
        access &+= 1
        guard var entry = entries[key] else {
            missCount += 1
            return nil
        }
        hitCount += 1
        entry.access = access
        entries[key] = entry
        return entry.textures
    }

    func insert(_ textures: LMTerrainTileDetailTextures, for key: Key) {
        access &+= 1
        if let previous = entries.removeValue(forKey: key) {
            byteCount -= previous.byteCount
        }
        let cost = textures.albedo.count + textures.normal.count
        guard cost <= byteLimit else { return }
        entries[key] = Entry(textures: textures, byteCount: cost, access: access)
        byteCount += cost
        evictIfNeeded()
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: false)
        byteCount = 0
    }

    func statistics() -> Statistics {
        Statistics(
            entryCount: entries.count,
            byteCount: byteCount,
            hitCount: hitCount,
            missCount: missCount,
            evictionCount: evictionCount
        )
    }

    private func evictIfNeeded() {
        while byteCount > byteLimit,
              let oldest = entries.min(by: { $0.value.access < $1.value.access }) {
            byteCount -= oldest.value.byteCount
            entries.removeValue(forKey: oldest.key)
            evictionCount += 1
        }
    }
}

/// Generates one complete tile and records enough information to benchmark a
/// future Core ML model on device. Cache lookup is actor-isolated, while model
/// work stays on the caller's cancellable background task.
struct LMTerrainDetailPipeline: Sendable {
    struct Product: Sendable {
        let textures: LMTerrainTileDetailTextures
        let modelID: String
        let cacheHit: Bool
        let generationMilliseconds: Int
    }

    let generator: any LMTerrainDetailGenerating
    let cache: LMTerrainDetailCache

    init(
        generator: any LMTerrainDetailGenerating,
        cache: LMTerrainDetailCache = LMTerrainDetailCache()
    ) {
        self.generator = generator
        self.cache = cache
    }

    func textures(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?
    ) async throws -> Product {
        let key = LMTerrainDetailCache.Key(modelID: generator.modelID, plan: plan)
        if let cached = await cache.value(for: key) {
            return Product(
                textures: cached,
                modelID: generator.modelID,
                cacheHit: true,
                generationMilliseconds: 0
            )
        }

        let started = ContinuousClock.now
        let generated = try await generator.generate(
            plan: plan,
            albedoField: albedoField
        )
        try Task.checkCancellation()
        await cache.insert(generated, for: key)
        return Product(
            textures: generated,
            modelID: generator.modelID,
            cacheHit: false,
            generationMilliseconds: Self.milliseconds(
                started.duration(to: .now)
            )
        )
    }

    private static func milliseconds(_ duration: ContinuousClock.Duration) -> Int {
        Int(
            duration.components.seconds * 1_000
                + duration.components.attoseconds / 1_000_000_000_000_000
        )
    }
}
