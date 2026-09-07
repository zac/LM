import Foundation
import RealityKit
import OSLog

/// Uses the existing clipmap planner, tile baker, cache and ownership masks.
/// A complete generation is published atomically, including its contact mesh.
@MainActor
public final class LMLunarTerrainPresentation {
    public let root = Entity()
    public let region: LMLunarTerrainRegion
    let simulationGate: LMTerrainSimulationGate?
    public private(set) var snapshot = LMLunarTerrainMeshSnapshot(tiles: [])
    package private(set) var boundsMinimum = SIMD3<Float>.zero
    package private(set) var boundsMaximum = SIMD3<Float>.zero
    private var requested = [LMTerrainTilePlan]()
    private(set) var generationRequestCount = 0
    private(set) var tileBuildCount = 0
    private var task: Task<Void, Never>?
    private var morphTask: Task<Void, Never>?
    private var anchor: LMSelenographicLocalFrame?
    public var presentationChanged: (@MainActor () -> Void)?
    /// A contacted lander must retain the surface it is resting on. Waiting
    /// happens outside the simulation gate so contact dynamics keep advancing.
    public var publicationAllowed: (@MainActor () -> Bool)?
    public private(set) var isMorphing = false
    static let morphDurationSeconds = 1.2
    private var generation = UUID()
    private var residentEntities = [(Entity, LMTerrainTilePlan)]()
    private var registeringEntities = [(Entity, LMTerrainTilePlan)]()
    private var pipeline: LMTerrainDetailPipeline
    private struct Cached {
        let plan: LMTerrainTilePlan
        let parents: [ParentDependency]
        let neighbors: [LMTerrainTilePlan]
        let geometryRevision: UUID
        let owners: Set<LMTerrainTileID>
        let build: Apollo11TerrainResource.ProgressiveTileEntityBuild
    }
    private struct ParentDependency: Equatable {
        let id: LMTerrainTileID
        let revision: UUID
    }
    struct CacheStatistics {
        var hits = 0, remasked = 0, missing = 0, plan = 0, parents = 0, owners = 0, neighbors = 0
        mutating func add(_ other: Self) {
            hits += other.hits; remasked += other.remasked; missing += other.missing
            plan += other.plan; parents += other.parents; owners += other.owners; neighbors += other.neighbors
        }
    }
    private(set) var cacheStatistics = CacheStatistics()
    private var cache = [LMTerrainTileID: Cached]()

    /// Vertices and central-difference edge normals read no farther than one
    /// sample outside the tile. Include touching boundaries and a second sample
    /// conservatively. Distant parents cannot affect these reads.
    nonisolated static func samplingDependencies(for plan: LMTerrainTilePlan,
                                                in plans: [LMTerrainTilePlan]) -> [LMTerrainTilePlan] {
        let radius = plan.sizeMeters / 2 + plan.sampleSpacingMeters * 2
        return plans.filter {
            $0.sampleSpacingMeters >= plan.sampleSpacingMeters &&
            abs($0.centerEastMeters - plan.centerEastMeters) <= radius + $0.sizeMeters / 2 &&
            abs($0.centerNorthMeters - plan.centerNorthMeters) <= radius + $0.sizeMeters / 2
        }
    }
    private let logger = Logger(subsystem: LunarMapLog.subsystem, category: "LunarTerrain")

    public init(region: LMLunarTerrainRegion, mode: LMTerrainDetailMode,
         simulationGate: LMTerrainSimulationGate? = nil) {
        self.region = region
        self.simulationGate = simulationGate
        // Per-region cache ownership prevents an appearance tile at one lunar
        // coordinate from being reused under the same local tile ID elsewhere.
        // The bundled neural corpus is Apollo-only. Until N3 has validated
        // geographic conditioning, global regions use the calibrated fallback.
        pipeline = LMTerrainDetailMode.procedural.makePipeline()
    }

    package func update(east: Double, north: Double, altitude: Double, metersAcross: Double, heading: Double,
                coarseFirst: Bool = false,
                status: @escaping @MainActor (String, Int, Int, Double?, Int?) -> Void) {
        let plans = Self.plans(sourceSpacing: region.terrain.base.spacingMeters, east: east, north: north,
                               altitude: altitude, metersAcross: metersAcross, heading: heading)
        if coarseFirst {
            updateProgressively(plans: plans, east: east, north: north, status: status)
        } else {
            update(plans: plans, east: east, north: north, status: status)
        }
    }

    private struct RefinementRequest {
        let plans: [LMTerrainTilePlan]
        let east: Double
        let north: Double
        let status: @MainActor (String, Int, Int, Double?, Int?) -> Void
    }
    private var refinementRequest: RefinementRequest?
    private var refinementInFlight = false

    /// Explorer requests advance by one spacing level per committed generation.
    /// New zoom requests update the destination without cancelling the coarse build.
    func updateProgressively(east: Double, north: Double, altitude: Double, metersAcross: Double, heading: Double,
        status: @escaping @MainActor (String, Int, Int, Double?, Int?) -> Void) {
        let plans = Self.plans(sourceSpacing: region.terrain.base.spacingMeters, east: east, north: north,
            altitude: altitude, metersAcross: metersAcross, heading: heading)
        updateProgressively(plans: plans, east: east, north: north, status: status)
    }

    func updateProgressively(plans: [LMTerrainTilePlan], east: Double, north: Double,
        status: @escaping @MainActor (String, Int, Int, Double?, Int?) -> Void) {
        refinementRequest = .init(plans: plans, east: east, north: north, status: status)
        advanceRefinement()
    }

    nonisolated static func nextRefinement(plans: [LMTerrainTilePlan], residentSpacing: Double?) -> [LMTerrainTilePlan] {
        let levels = Set(plans.map(\.sampleSpacingMeters)).sorted(by: >)
        guard let coarsest = levels.first else { return [] }
        let next = residentSpacing.flatMap { current in levels.first { $0 < current } }
            ?? residentSpacing ?? coarsest
        return plans.filter { $0.sampleSpacingMeters >= next }
    }

    private func advanceRefinement() {
        guard !refinementInFlight, let request = refinementRequest else { return }
        let plans = Self.nextRefinement(plans: request.plans,
            residentSpacing: snapshot.tiles.map(\.plan.sampleSpacingMeters).min())
        guard !plans.isEmpty, plans != requested else {
            refinementRequest = nil
            return
        }
        refinementInFlight = true
        update(plans: plans, east: request.east, north: request.north) { [weak self] message, requested, active, spacing, ms in
            request.status(message, requested, active, spacing, ms)
            guard let self else { return }
            if ms != nil {
                self.refinementInFlight = false
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.advanceRefinement()
                }
            } else if message.hasPrefix("Lunar terrain failed") {
                self.refinementInFlight = false
                self.refinementRequest = nil
            }
        }
    }

    /// Detached from the visible scene during prefetch, but published through
    /// the same generation/contact path before being adopted at the handoff.
    package func prepareCoarse(metersAcross: Double = 600_000) async throws {
        let plans = Self.plans(sourceSpacing: region.terrain.base.spacingMeters, east: 0, north: 0,
            altitude: 1_000_000, metersAcross: metersAcross, heading: 0).filter { $0.sampleSpacingMeters == 512 }
        update(plans: plans, east: 0, north: 0) { _, _, _, _, _ in }
        let pending = task
        await withTaskCancellationHandler(operation: { await pending?.value }, onCancel: { pending?.cancel() })
        try Task.checkCancellation()
        guard !snapshot.tiles.isEmpty else { throw LMLunarElevationGrid.GridError.invalidDimensions }
    }

    /// Also permits small real-baker plans in lifecycle tests.
    public func update(plans: [LMTerrainTilePlan], east: Double, north: Double,
                status: @escaping @MainActor (String, Int, Int, Double?, Int?) -> Void) {
        guard plans != requested else { return }
        requested = plans
        generationRequestCount += 1
        task?.cancel()
        let token = UUID()
        generation = token
        let region = region, pipeline = pipeline
        let previousCache = cache
        status("Building lunar terrain", plans.count, snapshot.tiles.count, plans.map(\.sampleSpacingMeters).min(), nil)
        task = Task { [weak self] in
            do {
                let start = ContinuousClock.now
                let replacement = Entity()
                var entities = [(Entity, LMTerrainTilePlan)]()
                var nextCache = [LMTerrainTileID: Cached]()
                var built = [LMLunarTerrainMeshTile]()
                var statistics = CacheStatistics()
                // Finish each parent level before starting its children.
                // Within a level, at most two CPU bakes/imports are in flight.
                var offset = 0
                while offset < plans.count {
                    let spacing = plans[offset].sampleSpacingMeters
                    var end = offset + 1
                    while end < plans.count && plans[end].sampleSpacingMeters == spacing { end += 1 }
                    let parentSnapshot = LMLunarTerrainMeshSnapshot(tiles: built.reversed())
                    let parentCache = nextCache
                    let interval = LMLunarTerrainTiming.begin("global-level-\(spacing)m")
                    var cpuMilliseconds = 0.0, freshTiles = 0
                    for first in stride(from: offset, to: end, by: 2) {
                        try Task.checkCancellation()
                        let results: [TileBuild]
                        if first + 1 < end {
                            async let a = Self.buildTile(plans[first], plans: plans, region: region, pipeline: pipeline,
                                parentSnapshot: parentSnapshot, parentCache: parentCache, previousCache: previousCache)
                            async let b = Self.buildTile(plans[first + 1], plans: plans, region: region, pipeline: pipeline,
                                parentSnapshot: parentSnapshot, parentCache: parentCache, previousCache: previousCache)
                            results = try await [a, b]
                        } else {
                            results = [try await Self.buildTile(plans[first], plans: plans, region: region, pipeline: pipeline,
                                parentSnapshot: parentSnapshot, parentCache: parentCache, previousCache: previousCache)]
                        }
                        // Restore planner order independently of completion order.
                        for result in results {
                            let cached = result.cached, plan = cached.plan, build = cached.build
                            nextCache[plan.id] = cached
                            statistics.add(result.statistics)
                            if !result.reused {
                                self?.tileBuildCount += 1
                                cpuMilliseconds += Double(build.metrics.meshMilliseconds)
                                freshTiles += 1
                            }
                            replacement.addChild(build.entity)
                            entities.append((build.entity, plan))
                            built.append(.init(plan: plan, mesh: build.mesh))
                            self?.logger.info("Global tile L\(plan.id.level) spacing=\(plan.sampleSpacingMeters)m cacheHit=\(result.reused) mesh=\(build.metrics.meshMilliseconds)ms detail=\(build.metrics.detailMilliseconds)ms")
                        }
                    }
                    LMLunarTerrainTiming.end(interval)
                    self?.logger.info("Global level spacing=\(spacing)m freshTiles=\(freshTiles) cpuMeshSum=\(cpuMilliseconds)ms")
                    offset = end
                }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                // Let the current visible interpolation finish even when a new
                // request cancels pending work. Never restart from its target
                // while a different intermediate surface is still displayed.
                if let active = self.morphTask { await active.value }
                try Task.checkCancellation()
                guard self.generation == token else { return }
                let target = LMLunarTerrainMeshSnapshot(tiles: built.reversed())
                var minimum = SIMD3<Float>(repeating: .infinity)
                var maximum = SIMD3<Float>(repeating: -.infinity)
                for tile in built {
                    let offset = SIMD3(Float(tile.plan.centerNorthMeters), 0, Float(-tile.plan.centerEastMeters))
                    for vertex in tile.mesh.positions {
                        minimum = simd_min(minimum, vertex + offset)
                        maximum = simd_max(maximum, vertex + offset)
                    }
                }
                @MainActor func ready() {
                    guard self.generation == token else { return }
                    self.logger.info("Global focus rendered=\(self.snapshot.sample(east: east, north: north)?.elevation ?? 0)m")
                    let elapsed = start.duration(to: .now).components
                    let milliseconds = Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)
                    status("Lunar terrain ready", plans.count, built.count, plans.map(\.sampleSpacingMeters).min(), milliseconds)
                    self.cacheStatistics = statistics
                    self.logger.info("Global cache hits=\(statistics.hits) remasked=\(statistics.remasked) missing=\(statistics.missing) plan=\(statistics.plan) parents=\(statistics.parents) owners=\(statistics.owners) neighbors=\(statistics.neighbors)")
                    self.logger.info("Global terrain ready tiles=\(built.count) generation=\(milliseconds)ms floor=\(region.measuredFloorMeters)m")
                }
                if self.snapshot.tiles.isEmpty {
                    try await self.publish(replacement, snapshot: target, entities: entities, minimum: minimum, maximum: maximum)
                    self.cache = nextCache
                    ready()
                } else {
                    try await self.waitForPublication()
                    LMLunarTerrainTiming.memory("morph-before-preparation")
                    let previous = self.snapshot
                    let preparation = Task.detached(priority: .userInitiated) {
                        try LMLunarTerrainTiming.measure("morph-preparation") {
                            try LMLunarTerrainMorph(from: previous, to: target)
                        }
                    }
                    let morph = try await withTaskCancellationHandler(
                        operation: { try await preparation.value }, onCancel: { preparation.cancel() })
                    try Task.checkCancellation()
                    LMLunarTerrainTiming.memory("morph-after-preparation", resourceBytes: morph.tiles.reduce(0) {
                        $0 + ($1.endpoints.start.count + $1.endpoints.end.count) * MemoryLayout<SIMD4<Float>>.stride
                    })
                    let realization = LMLunarTerrainTiming.begin("morph-realization")
                    let renderer = try await LMLunarTerrainMorphRenderer(morph: morph,
                        from: self.cache.values.map { ($0.plan, $0.build) },
                        to: nextCache.values.map { ($0.plan, $0.build) })
                    LMLunarTerrainTiming.end(realization)
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    try await self.prepareForPublication(renderer)
                    try await self.publish(renderer.root, snapshot: morph.snapshot(weight: 0), entities: renderer.entities,
                        minimum: simd_min(self.boundsMinimum, minimum), maximum: simd_max(self.boundsMaximum, maximum))
                    self.cache = nextCache
                    self.isMorphing = true
                    status("Blending lunar terrain", plans.count, morph.tiles.count, plans.map(\.sampleSpacingMeters).min(), nil)
                    self.logger.info("Global morph begin tiles=\(morph.tiles.count) dynamic=\(renderer.entries.count) appearance=\(renderer.appearances.count) duration=\(Self.morphDurationSeconds)s")
                    self.morphTask = Task { @MainActor in
                        defer { self.morphTask = nil; self.isMorphing = false }
                        do {
                            // Let RealityKit consume initial entity/buffer
                            // publication before replacing those buffers again.
                            await self.waitForSceneUpdates(2)
                            let clock = ContinuousClock.now
                            while true {
                                try await self.waitForPublication()
                                let elapsed = clock.duration(to: .now).components
                                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                                let weight = LMLunarTerrainMorph.weight(fraction: seconds / Self.morphDurationSeconds)
                                let update = LMLunarTerrainTiming.begin("morph-frame")
                                if let gate = self.simulationGate {
                                    let published = try await gate.withAccess {
                                        try Task.checkCancellation()
                                        guard self.publicationAllowed?() != false else { return false }
                                        let command = try renderer.update(weight: weight)
                                        // Physics waits for the GPU replacement and
                                        // its matching immutable contact snapshot.
                                        let completion = LMLunarTerrainTiming.begin("cockpit-morph-gpu-wait")
                                        try await command.complete()
                                        LMLunarTerrainTiming.end(completion)
                                        LMLunarTerrainTiming.measure("cockpit-morph-contact-publication") {
                                            self.snapshot = morph.snapshot(weight: weight)
                                            self.presentationChanged?()
                                        }
                                        return true
                                    }
                                    LMLunarTerrainTiming.end(update)
                                    if !published { continue }
                                } else {
                                    let command = try renderer.update(weight: weight)
                                    self.snapshot = morph.snapshot(weight: weight)
                                    self.presentationChanged?()
                                    LMLunarTerrainTiming.end(update)
                                    let completion = LMLunarTerrainTiming.begin("morph-gpu-wait")
                                    try await command.complete()
                                    LMLunarTerrainTiming.end(completion)
                                }
                                if weight == 1 { break }
                                await self.waitForSceneUpdates(1)
                            }
                            await self.waitForSceneUpdates(2)
                            try await self.publish(replacement, snapshot: target, entities: entities, minimum: minimum, maximum: maximum)
                            self.isMorphing = false
                            LMLunarTerrainTiming.memory("morph-complete")
                            self.logger.info("Global morph complete")
                            ready()
                        } catch {
                            self.logger.error("Global terrain failed: morph \(error.localizedDescription)")
                            if self.generation == token {
                                status("Lunar terrain failed: \(error.localizedDescription)", plans.count, self.snapshot.tiles.count, nil, nil)
                            }
                        }
                    }
                }
            } catch is CancellationError { }
            catch {
                guard let self, self.generation == token else { return }
                self.requested = []
                self.logger.error("Global terrain failed: \(error.localizedDescription)")
                status("Lunar terrain failed: \(error.localizedDescription)", plans.count, self.snapshot.tiles.count, nil, nil)
            }
        }
    }

    private struct TileBuild {
        let cached: Cached
        let reused: Bool
        let statistics: CacheStatistics
    }

    private static func buildTile(_ plan: LMTerrainTilePlan, plans: [LMTerrainTilePlan],
        region: LMLunarTerrainRegion, pipeline: LMTerrainDetailPipeline,
        parentSnapshot: LMLunarTerrainMeshSnapshot, parentCache: [LMTerrainTileID: Cached],
        previousCache: [LMTerrainTileID: Cached]) async throws -> TileBuild {
        try Task.checkCancellation()
        var field = LMLunarTerrainHeightField(terrain: region.terrain, frame: region.frame)
        field.parents = parentSnapshot
        let neighbors = samplingDependencies(for: plan, in: plans)
        let parents = neighbors.compactMap { dependency -> ParentDependency? in
            guard dependency.sampleSpacingMeters > plan.sampleSpacingMeters,
                  let cached = parentCache[dependency.id] else { return nil }
            return .init(id: dependency.id, revision: cached.geometryRevision)
        }
        let owners = Self.finerOwners(of: plan, in: plans)
        let build: Apollo11TerrainResource.ProgressiveTileEntityBuild
        var reused = false, statistics = CacheStatistics()
        if let cached = previousCache[plan.id], cached.plan == plan,
           cached.parents == parents, cached.owners == owners, cached.neighbors == neighbors {
            reused = true
            statistics.hits = 1
            build = .init(entity: cached.build.entity.clone(recursive: true),
                          mesh: cached.build.mesh, metrics: cached.build.metrics)
        } else if let cached = previousCache[plan.id], cached.plan == plan,
                  cached.parents == parents, cached.neighbors == neighbors,
                  cached.build.entity.model != nil {
            statistics.remasked = 1
            reused = true
            build = try await replacingOwnership(cached.build, plan: plan, plans: plans)
        } else {
            if let cached = previousCache[plan.id] {
                if cached.plan != plan { statistics.plan = 1 }
                else if cached.parents != parents { statistics.parents = 1 }
                else if cached.owners != owners { statistics.owners = 1 }
                else { statistics.neighbors = 1 }
            } else { statistics.missing = 1 }
            guard let generated = try await Apollo11TerrainResource.makeProgressiveTileEntityBuild(
                heightField: field, plan: plan, activePlans: plans, geometryReplacementPlans: plans,
                albedoField: region.albedo, detailPipeline: pipeline
            ) else { throw LMLunarElevationGrid.GridError.invalidDimensions }
            build = generated
        }
        let previous = previousCache[plan.id]
        let sameGeometry = previous?.plan == plan &&
            previous?.build.mesh.positions == build.mesh.positions &&
            previous?.build.mesh.normals == build.mesh.normals
        let cached = Cached(plan: plan, parents: parents, neighbors: neighbors,
            geometryRevision: sameGeometry ? previous!.geometryRevision : UUID(), owners: owners, build: build)
        return TileBuild(cached: cached, reused: reused, statistics: statistics)
    }

    private static func replacingOwnership(_ cached: Apollo11TerrainResource.ProgressiveTileEntityBuild,
                                           plan: LMTerrainTilePlan, plans: [LMTerrainTilePlan]) async throws
        -> Apollo11TerrainResource.ProgressiveTileEntityBuild {
        let geometry = cached.mesh
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return Apollo11TerrainResource.progressiveTileIndices(plan: plan,
                finerResidentPlans: plans.filter { $0.sampleSpacingMeters < plan.sampleSpacingMeters - 1e-9 })
        }
        let indices = try await withTaskCancellationHandler(operation: { try await task.value },
                                                            onCancel: { task.cancel() })
        try Task.checkCancellation()
        let data = LMProgressiveTerrainMeshData(positions: geometry.positions, normals: geometry.normals,
            tangents: geometry.tangents, bitangents: geometry.bitangents,
            addedReliefNormalDistribution: geometry.addedReliefNormalDistribution,
            textureCoordinates: geometry.textureCoordinates, indices: indices)
        let entity = cached.entity.clone(recursive: true)
        if indices.isEmpty {
            entity.model = nil
        } else {
            var descriptor = MeshDescriptor(name: "Lunar tile ownership")
            descriptor.positions = MeshBuffers.Positions(data.positions)
            descriptor.normals = MeshBuffers.Normals(data.normals)
            descriptor.tangents = MeshBuffers.Tangents(data.tangents)
            descriptor.bitangents = MeshBuffers.Tangents(data.bitangents)
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(data.textureCoordinates)
            descriptor.primitives = .triangles(indices)
            let resource = try LMLunarTerrainTiming.measure("ownership-upload") {
                try MeshResource.generate(from: [descriptor])
            }
            entity.model?.mesh = resource
        }
        return .init(entity: entity, mesh: data, metrics: cached.metrics)
    }

    public nonisolated static func plans(sourceSpacing: Double, east: Double, north: Double,
                                  altitude: Double, metersAcross: Double, heading: Double) -> [LMTerrainTilePlan] {
        var policy = LMTerrainDetailPolicy()
        policy.globalBands = true
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: sourceSpacing,
                                                  levels: LMProgressiveTerrainPlanner.globalLevels)
        var plans = planner.focusedPlans(focusEastMeters: east, focusNorthMeters: north,
                                        altitudeMeters: altitude, policy: policy)
        if altitude <= policy.landingAltitudeMeters {
            // A global anchor starts exactly at a tile corner. The 32 m-wide
            // footprint exposed its terminal parent in the Surface capture;
            // cover both lateral edges of the oblique view as well as its ray.
            let radians = heading * .pi / 180
            for lateral in [-16.0, 0, 16] {
                let e = east - sin(radians) * lateral
                let n = north + cos(radians) * lateral
                plans += planner.viewCorridorPlans(focusEastMeters: e, focusNorthMeters: n,
                                                   headingDegrees: heading, forwardDistanceMeters: 48, altitudeMeters: altitude)
                plans += planner.viewCorridorPlans(focusEastMeters: e, focusNorthMeters: n,
                                                   headingDegrees: heading + 180, forwardDistanceMeters: 32, altitudeMeters: altitude)
            }
        }
        if altitude <= policy.terminalAltitudeMeters {
            plans += planner.viewCorridorPlans(focusEastMeters: east, focusNorthMeters: north,
                                               headingDegrees: heading, forwardDistanceMeters: min(384, max(48, metersAcross * 0.75)),
                                               altitudeMeters: max(altitude, policy.landingAltitudeMeters + 1))
        }
        // Coarse measured geometry must cover the globe-to-region handoff.
        // Fine residency remains bounded by the planner's nested footprints.
        let reach = min(131_000, max(32_000, metersAcross * 0.8))
        let size = 65_536.0
        for n in Int(floor((north - reach) / size))...Int(floor((north + reach) / size)) {
            for e in Int(floor((east - reach) / size))...Int(floor((east + reach) / size)) {
                plans.append(.init(id: .init(level: 6, eastIndex: e, northIndex: n),
                                   centerEastMeters: (Double(e) + 0.5) * size,
                                   centerNorthMeters: (Double(n) + 0.5) * size,
                                   sizeMeters: size, sampleSpacingMeters: 512,
                                   containsProceduralSubresolution: false))
            }
        }
        plans = planner.rectangularPlansEnclosingChildren(plans).sorted {
            if $0.sampleSpacingMeters != $1.sampleSpacingMeters { return $0.sampleSpacingMeters > $1.sampleSpacingMeters }
            if $0.id.northIndex != $1.id.northIndex { return $0.id.northIndex < $1.id.northIndex }
            return $0.id.eastIndex < $1.id.eastIndex
        }
        return plans
    }

    /// Re-enter the already resident, fully published surface without cloning
    /// meshes or running a no-op morph. No second region or resource cache exists.
    package func resumeIfReady(plans: [LMTerrainTilePlan]) -> Bool {
        guard !plans.isEmpty, !isMorphing, registeringEntities.isEmpty,
              snapshot.tiles.count == plans.count, cache.count == plans.count,
              plans.allSatisfy({ cache[$0.id]?.plan == $0 }),
              snapshot.tiles.allSatisfy({ plans.contains($0.plan) }) else { return false }
        cancel()
        requested = plans
        cacheStatistics = CacheStatistics()
        cacheStatistics.hits = plans.count
        logger.info("Global terrain reused tiles=\(plans.count) generation=0ms")
        return true
    }

    public func cancel() {
        refinementRequest = nil
        refinementInFlight = false
        generation = UUID()
        task?.cancel()
        task = nil
        requested = []
    }

    private func waitForSceneUpdates(_ count: Int) async {
        guard let scene = root.scene else {
            try? await Task.sleep(for: .milliseconds(16 * count))
            return
        }
        let (updates, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(count))
        let subscription = scene.subscribe(to: SceneEvents.Update.self) { _ in continuation.yield(()) }
        // A detached or suspended scene must not retain an arrival forever.
        let timeout = Task {
            try? await Task.sleep(for: .seconds(1))
            continuation.finish()
        }
        defer { subscription.cancel(); timeout.cancel(); continuation.finish() }
        var received = 0
        for await _ in updates {
            received += 1
            if received == count { break }
        }
    }

    private func prepareForPublication(_ renderer: LMLunarTerrainMorphRenderer) async throws {
        // The common-refinement start is the same geometric surface as the
        // current snapshot. Keep the old opaque representation beneath that
        // endpoint while RealityKit first renders the incoming resources. A
        // zero-opacity registration did not prevent a one-frame upload gap.
        let incoming = renderer.root
        registeringEntities = renderer.entities
        apply(anchor: anchor ?? region.frame)
        root.addChild(incoming)
        var completed = false
        defer {
            registeringEntities = []
            if !completed { incoming.removeFromParent() }
        }
        // The observed gap lasts one 60 Hz capture frame. This 100 ms hold
        // allows several rendered frames while retaining exact endpoint contact.
        try await Task.sleep(for: .milliseconds(100))
        await waitForSceneUpdates(3)
        try Task.checkCancellation()
        completed = true
    }

    package func setMode(_ mode: LMTerrainDetailMode) {
        cancel()
        // The bundled neural corpus is Apollo-only. Until N3 has validated
        // geographic conditioning, global regions use the calibrated fallback.
        pipeline = LMTerrainDetailMode.procedural.makePipeline()
        // Both modes currently resolve to that same deterministic generator.
        // Keep the displayed appearance available as the next morph endpoint.
        requested = []
    }

    private func waitForPublication() async throws {
        while publicationAllowed?() == false {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
    }

    private func publish(_ replacement: Entity, snapshot: LMLunarTerrainMeshSnapshot,
                         entities: [(Entity, LMTerrainTilePlan)], minimum: SIMD3<Float>, maximum: SIMD3<Float>) async throws {
        if let simulationGate {
            while true {
                try await waitForPublication()
                let installed = try await simulationGate.withAccess {
                    try Task.checkCancellation()
                    guard publicationAllowed?() != false else { return false }
                    install(replacement, snapshot: snapshot, entities: entities, minimum: minimum, maximum: maximum)
                    return true
                }
                if installed { break }
            }
        } else {
            install(replacement, snapshot: snapshot, entities: entities, minimum: minimum, maximum: maximum)
        }
    }

    private func install(_ replacement: Entity, snapshot: LMLunarTerrainMeshSnapshot,
                         entities: [(Entity, LMTerrainTilePlan)], minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        let publication = LMLunarTerrainTiming.begin("generation-publication")
        defer { LMLunarTerrainTiming.end(publication) }
        residentEntities = entities
        apply(anchor: anchor ?? region.frame)
        let old = root.children.filter { $0 !== replacement }
        if replacement.parent !== root { root.addChild(replacement) }
        old.forEach { $0.removeFromParent() }
        self.snapshot = snapshot
        boundsMinimum = minimum
        boundsMaximum = maximum
        presentationChanged?()
    }

    public func apply(anchor: LMSelenographicLocalFrame) {
        self.anchor = anchor
        for (entity, plan) in residentEntities + registeringEntities {
            entity.transform = LMLunarAnchoredPlacement.chunkTransform(
                origin: .init(northMeters: plan.centerNorthMeters, eastMeters: plan.centerEastMeters, upMeters: 0),
                source: region.frame, anchor: anchor
            )
        }
    }
    package static func finerOwners(
        of plan: LMTerrainTilePlan,
        in candidates: [LMTerrainTilePlan]
    ) -> Set<LMTerrainTileID> {
        let half = plan.sizeMeters / 2
        return Set(candidates.compactMap { candidate in
            guard candidate.sampleSpacingMeters
                    < plan.sampleSpacingMeters - 1e-9 else { return nil }
            let candidateHalf = candidate.sizeMeters / 2
            let overlaps = candidate.centerEastMeters + candidateHalf
                    > plan.centerEastMeters - half
                && candidate.centerEastMeters - candidateHalf
                    < plan.centerEastMeters + half
                && candidate.centerNorthMeters + candidateHalf
                    > plan.centerNorthMeters - half
                && candidate.centerNorthMeters - candidateHalf
                    < plan.centerNorthMeters + half
            return overlaps ? candidate.id : nil
        })
    }

}
