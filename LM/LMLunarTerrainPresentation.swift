import Foundation
import RealityKit
import OSLog

/// Uses the existing clipmap planner, tile baker, cache and ownership masks.
/// A complete generation is published atomically, including its contact mesh.
@MainActor
final class LMLunarTerrainPresentation {
    let root = Entity()
    let region: LMLunarTerrainRegion
    private(set) var snapshot = LMLunarTerrainMeshSnapshot(tiles: [])
    private(set) var boundsMinimum = SIMD3<Float>.zero
    private(set) var boundsMaximum = SIMD3<Float>.zero
    private var requested = [LMTerrainTilePlan]()
    private var task: Task<Void, Never>?
    private var morphTask: Task<Void, Never>?
    private var anchor: LMSelenographicLocalFrame?
    var presentationChanged: (@MainActor () -> Void)?
    private(set) var isMorphing = false
    static let morphDurationSeconds = 1.2
    private var generation = UUID()
    private var residentEntities = [(Entity, LMTerrainTilePlan)]()
    private var registeringEntities = [(Entity, LMTerrainTilePlan)]()
    private var pipeline: LMTerrainDetailPipeline
    private struct Cached {
        let plan: LMTerrainTilePlan
        let parents: [LMTerrainTilePlan]
        let owners: Set<LMTerrainTileID>
        let build: Apollo11TerrainResource.ProgressiveTileEntityBuild
    }
    private var cache = [LMTerrainTileID: Cached]()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.positron.LM", category: "LunarTerrain")

    init(region: LMLunarTerrainRegion, mode: LMTerrainDetailMode) {
        self.region = region
        // Per-region cache ownership prevents an appearance tile at one lunar
        // coordinate from being reused under the same local tile ID elsewhere.
        // The bundled neural corpus is Apollo-only. Until N3 has validated
        // geographic conditioning, global regions use the calibrated fallback.
        pipeline = LMTerrainDetailMode.procedural.makePipeline()
    }

    func update(east: Double, north: Double, altitude: Double, metersAcross: Double, heading: Double,
                status: @escaping @MainActor (String, Int, Int, Double?, Int?) -> Void) {
        let plans = Self.plans(sourceSpacing: region.terrain.base.spacingMeters, east: east, north: north,
                               altitude: altitude, metersAcross: metersAcross, heading: heading)
        update(plans: plans, east: east, north: north, status: status)
    }

    /// Also permits small real-baker plans in lifecycle tests.
    func update(plans: [LMTerrainTilePlan], east: Double, north: Double,
                status: @escaping @MainActor (String, Int, Int, Double?, Int?) -> Void) {
        guard plans != requested else { return }
        requested = plans
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
                // Coarse-to-fine order lets each child read its actual parent
                // triangles, including the parent's own outer morph collar.
                for plan in plans {
                    try Task.checkCancellation()
                    var field = LMLunarTerrainHeightField(terrain: region.terrain, frame: region.frame)
                    field.parents = .init(tiles: built.reversed())
                    let parents = plans.filter { $0.sampleSpacingMeters > plan.sampleSpacingMeters }
                    let owners = LunarExplorerScene.finerOwners(of: plan, in: plans)
                    let build: Apollo11TerrainResource.ProgressiveTileEntityBuild
                    var reused = false
                    if let cached = previousCache[plan.id], cached.plan == plan,
                       cached.parents == parents, cached.owners == owners {
                        reused = true
                        build = .init(entity: cached.build.entity.clone(recursive: true),
                                      mesh: cached.build.mesh, metrics: cached.build.metrics)
                    } else {
                        guard let generated = try await Apollo11TerrainResource.makeProgressiveTileEntityBuild(
                            heightField: field, plan: plan, activePlans: plans,
                            geometryReplacementPlans: plans, albedoField: region.albedo, detailPipeline: pipeline
                        ) else { throw LMLunarElevationGrid.GridError.invalidDimensions }
                        build = generated
                    }
                    nextCache[plan.id] = .init(plan: plan, parents: parents, owners: owners, build: build)
                    replacement.addChild(build.entity)
                    entities.append((build.entity, plan))
                    built.append(.init(plan: plan, mesh: build.mesh))
                    self?.logger.info("Global tile L\(plan.id.level) spacing=\(plan.sampleSpacingMeters)m cacheHit=\(reused) mesh=\(build.metrics.meshMilliseconds)ms detail=\(build.metrics.detailMilliseconds)ms")
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
                    self.logger.info("Global terrain ready tiles=\(built.count) generation=\(milliseconds)ms floor=\(region.measuredFloorMeters)m")
                }
                if self.snapshot.tiles.isEmpty {
                    self.install(replacement, snapshot: target, entities: entities, minimum: minimum, maximum: maximum)
                    self.cache = nextCache
                    ready()
                } else {
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
                    LMLunarTerrainTiming.memory("morph-after-preparation")
                    let realization = LMLunarTerrainTiming.begin("morph-realization")
                    let renderer = try await LMLunarTerrainMorphRenderer(morph: morph,
                        from: self.cache.values.map { ($0.plan, $0.build) },
                        to: nextCache.values.map { ($0.plan, $0.build) })
                    LMLunarTerrainTiming.end(realization)
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    try await self.prepareForPublication(renderer)
                    self.install(renderer.root, snapshot: morph.snapshot(weight: 0), entities: renderer.entities,
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
                                let elapsed = clock.duration(to: .now).components
                                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                                let weight = LMLunarTerrainMorph.weight(fraction: seconds / Self.morphDurationSeconds)
                                let update = LMLunarTerrainTiming.begin("morph-frame")
                                let command = try renderer.update(weight: weight)
                                self.snapshot = morph.snapshot(weight: weight)
                                self.presentationChanged?()
                                LMLunarTerrainTiming.end(update)
                                // Bound in-flight replacement buffers. Slow GPU
                                // work must not accumulate more mesh/texture copies.
                                let completion = LMLunarTerrainTiming.begin("morph-gpu-wait")
                                try await command.complete()
                                LMLunarTerrainTiming.end(completion)
                                if weight == 1 { break }
                                await self.waitForSceneUpdates(1)
                            }
                            await self.waitForSceneUpdates(2)
                            self.install(replacement, snapshot: target, entities: entities, minimum: minimum, maximum: maximum)
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

    nonisolated static func plans(sourceSpacing: Double, east: Double, north: Double,
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

    func cancel() {
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

    func setMode(_ mode: LMTerrainDetailMode) {
        cancel()
        // The bundled neural corpus is Apollo-only. Until N3 has validated
        // geographic conditioning, global regions use the calibrated fallback.
        pipeline = LMTerrainDetailMode.procedural.makePipeline()
        // Both modes currently resolve to that same deterministic generator.
        // Keep the displayed appearance available as the next morph endpoint.
        requested = []
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

    func apply(anchor: LMSelenographicLocalFrame) {
        self.anchor = anchor
        for (entity, plan) in residentEntities + registeringEntities {
            entity.transform = LMLunarAnchoredPlacement.chunkTransform(
                origin: .init(northMeters: plan.centerNorthMeters, eastMeters: plan.centerEastMeters, upMeters: 0),
                source: region.frame, anchor: anchor
            )
        }
    }
}
