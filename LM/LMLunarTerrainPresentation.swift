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
    private var generation = UUID()
    private var residentEntities = [(Entity, LMTerrainTilePlan)]()
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
                let publication = LMLunarTerrainTiming.begin("generation-publication")
                defer { LMLunarTerrainTiming.end(publication) }
                let old = Array(self.root.children)
                self.root.addChild(replacement)
                old.forEach { $0.removeFromParent() }
                self.snapshot = .init(tiles: built.reversed())
                var minimum = SIMD3<Float>(repeating: .infinity)
                var maximum = SIMD3<Float>(repeating: -.infinity)
                for tile in built {
                    let offset = SIMD3(Float(tile.plan.centerNorthMeters), 0, Float(-tile.plan.centerEastMeters))
                    for vertex in tile.mesh.positions {
                        minimum = simd_min(minimum, vertex + offset)
                        maximum = simd_max(maximum, vertex + offset)
                    }
                }
                self.boundsMinimum = minimum
                self.boundsMaximum = maximum
                self.residentEntities = entities
                self.cache = nextCache
                self.logger.info("Global focus rendered=\(self.snapshot.sample(east: east, north: north)?.elevation ?? 0)m")
                let elapsed = start.duration(to: .now).components
                let milliseconds = Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)
                status("Lunar terrain ready", plans.count, built.count, plans.map(\.sampleSpacingMeters).min(), milliseconds)
                self.logger.info("Global terrain ready tiles=\(built.count) generation=\(milliseconds)ms floor=\(region.measuredFloorMeters)m")
            } catch is CancellationError { }
            catch {
                guard let self, self.generation == token else { return }
                self.requested = []
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

    func setMode(_ mode: LMTerrainDetailMode) {
        cancel()
        // The bundled neural corpus is Apollo-only. Until N3 has validated
        // geographic conditioning, global regions use the calibrated fallback.
        pipeline = LMTerrainDetailMode.procedural.makePipeline()
        cache = [:]
        requested = []
    }

    func apply(anchor: LMSelenographicLocalFrame) {
        for (entity, plan) in residentEntities {
            entity.transform = LMLunarAnchoredPlacement.chunkTransform(
                origin: .init(northMeters: plan.centerNorthMeters, eastMeters: plan.centerEastMeters, upMeters: 0),
                source: region.frame, anchor: anchor
            )
        }
    }
}
