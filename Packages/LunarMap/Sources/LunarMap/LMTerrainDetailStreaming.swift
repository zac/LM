import Foundation

/// Selects the appearance implementation without changing terrain planning,
/// geometry, normals, contact, materials, or camera state. Lunar Explorer uses
/// this as its production A/B switch; powered descent keeps `.automatic`.
public enum LMTerrainDetailMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case procedural
    case neural

    public var id: Self { self }

    package var title: String {
        switch self {
        case .automatic: "Auto"
        case .procedural: "Procedural"
        case .neural: "Neural"
        }
    }

    package func makePipeline(bundle: Bundle = LunarMap.resources) -> LMTerrainDetailPipeline {
        let generator: any LMTerrainDetailGenerating = switch self {
        case .procedural:
            LMProceduralTerrainDetailGenerator()
        case .automatic, .neural:
            // Explicit neural mode still degrades to the complete procedural
            // tile if the model cannot load or predict. Diagnostics report the
            // generator that actually produced the tile.
            LMAutomaticTerrainDetailGenerator(bundle: bundle)
        }
        return LMTerrainDetailPipeline(generator: generator)
    }
}

/// Runtime boundary between terrain residency and appearance synthesis.
///
/// A production neural implementation can conform to this protocol without
/// changing tile planning, cancellation, mesh generation, or RealityKit
/// realization. The procedural implementation remains the deadline-safe
/// fallback and the reference used by tests.
protocol LMTerrainDetailGenerating: Sendable {
    var modelID: String { get }

    func prepare() async

    func generate(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?
    ) async throws -> LMTerrainTileDetailTextures
}

extension LMTerrainDetailGenerating {
    func prepare() async {}
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
        let transitionEdges: LMTerrainTileEdges

        init(modelID: String, plan: LMTerrainTilePlan) {
            self.modelID = modelID
            tileID = plan.id
            sizeBitPattern = plan.sizeMeters.bitPattern
            spacingBitPattern = plan.sampleSpacingMeters.bitPattern
            transitionEdges = plan.transitionEdges
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

/// Produces one complete appearance tile through the selected generator and
/// records its source and cost. Cache lookup is actor-isolated, while model
/// work stays on the caller's cancellable background task.
public struct LMTerrainDetailPipeline: Sendable {
    struct Product: Sendable {
        let textures: LMTerrainTileDetailTextures
        let modelID: String
        let cacheHit: Bool
        let generationMilliseconds: Int
    }

    let generator: any LMTerrainDetailGenerating
    let cache: LMTerrainDetailCache

    var modelID: String { generator.modelID }

    init(
        generator: any LMTerrainDetailGenerating,
        cache: LMTerrainDetailCache = LMTerrainDetailCache()
    ) {
        self.generator = generator
        self.cache = cache
    }

    package func prepare() async {
        await generator.prepare()
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
