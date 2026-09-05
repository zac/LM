import Foundation
import CryptoKit
import RealityKit
import UIKit
import simd

struct Apollo11TerrainHeightField: Equatable, Sendable {
    let tile: LMTerrainManifest.Tile
    let heights: [Float]
    let craterCatalog: LMLunarCraterCatalog?

    var width: Int { tile.postsPerSide }
    var height: Int { tile.postsPerSide }
    var spacingMeters: Double { tile.postSpacingMeters }

    func relativeElevation(eastMeters: Double, northMeters: Double) -> Float? {
        let spacing = spacingMeters
        let column = eastMeters / spacing + Double(width - 1) / 2
        let row = -northMeters / spacing + Double(height - 1) / 2
        guard column >= 0, row >= 0,
              column <= Double(width - 1),
              row <= Double(height - 1) else {
            return nil
        }

        let x0 = Int(column.rounded(.down))
        let y0 = Int(row.rounded(.down))
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = Float(column - Double(x0))
        let ty = Float(row - Double(y0))
        func value(_ x: Int, _ y: Int) -> Float {
            heights[y * width + x]
        }
        let north = value(x0, y0) + (value(x1, y0) - value(x0, y0)) * tx
        let south = value(x0, y1) + (value(x1, y1) - value(x0, y1)) * tx
        return north + (south - north) * ty
    }

    /// Smooth shading normal from the measured DTM posts.
    ///
    /// The geometry remains the exact bilinear interpolation above, preserving
    /// every measured post and the contact surface. Recomputing a constant
    /// slope from that interpolation inside every 2 m source cell exposes the
    /// DTM grid at surface scale. Interpolating the same central-difference
    /// post normals used by the measured base mesh removes that artificial
    /// faceting without inventing or moving any elevation.
    func interpolatedSurfaceNormal(
        eastMeters: Double,
        northMeters: Double
    ) -> SIMD3<Float>? {
        let spacing = spacingMeters
        let column = eastMeters / spacing + Double(width - 1) / 2
        let row = -northMeters / spacing + Double(height - 1) / 2
        guard column >= 0, row >= 0,
              column <= Double(width - 1),
              row <= Double(height - 1) else {
            return nil
        }
        let x0 = Int(column.rounded(.down))
        let y0 = Int(row.rounded(.down))
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = Float(column - Double(x0))
        let ty = Float(row - Double(y0))

        func postNormal(_ x: Int, _ y: Int) -> SIMD3<Float> {
            let centerX = min(max(x, 1), width - 2)
            let centerY = min(max(y, 1), height - 2)
            let west = heights[centerY * width + centerX - 1]
            let east = heights[centerY * width + centerX + 1]
            let north = heights[(centerY - 1) * width + centerX]
            let south = heights[(centerY + 1) * width + centerX]
            let eastSlope = (east - west) / Float(2 * spacing)
            let northSlope = (north - south) / Float(2 * spacing)
            return simd_normalize(SIMD3(-northSlope, 1, eastSlope))
        }

        let northwest = postNormal(x0, y0)
        let northeast = postNormal(x1, y0)
        let southwest = postNormal(x0, y1)
        let southeast = postNormal(x1, y1)
        let north = simd_mix(northwest, northeast, SIMD3(repeating: tx))
        let south = simd_mix(southwest, southeast, SIMD3(repeating: tx))
        return simd_normalize(simd_mix(north, south, SIMD3(repeating: ty)))
    }
}

struct LMProgressiveTerrainMeshData: Sendable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let tangents: [SIMD3<Float>]
    let bitangents: [SIMD3<Float>]
    /// Directional slopes of only the geometry band this tile adds relative
    /// to its resident parent. This remains independent of sun and material.
    let addedReliefNormalDistribution: LMTerrainNormalDistribution
    /// Tile-local 0...1 coordinates for the tile's own baked detail textures.
    let textureCoordinates: [SIMD2<Float>]
    let indices: [UInt32]
}

enum Apollo11TerrainResource {
    /// Process-local, model-versioned appearance pipeline. Tile task ownership
    /// remains in the scene so cancellation and residency behavior do not
    /// change when neural reconstruction is available.
    nonisolated static let detailPipeline = LMTerrainDetailPipeline(
        generator: LMAutomaticTerrainDetailGenerator()
    )

    nonisolated static func prepareTerrainDetail(
        pipeline: LMTerrainDetailPipeline = detailPipeline
    ) async {
        await pipeline.prepare()
    }

    enum ResourceError: Error, Equatable {
        case missingResource(String)
        case invalidDimensions
        case invalidCraterCatalog(String)
    }

    /// Load the native 2 m/post near-field tile imported from the source-pinned
    /// full-immersion terrain pipeline. This supersedes the older 8 m cockpit
    /// crop as the measured foundation for local sampling and procedural LOD.
    nonisolated static func loadSourceBackedHeightField(
        bundle: Bundle = .main
    ) throws -> Apollo11TerrainHeightField {
        let terrainManifest = try LMTerrainManifest.load(bundle: bundle)
        guard let near = terrainManifest.tile(id: LMTerrainWorld.nearFieldTileID) else {
            throw ResourceError.missingResource("Terrain/near-field-height.png")
        }
        let heightURL = try terrainResourceURL(
            file: near.heightFile,
            bundle: bundle
        )
        let map = try LMTerrainHeightMap.load(contentsOf: heightURL)
        guard map.width == near.postsPerSide,
              map.height == near.postsPerSide else {
            throw ResourceError.invalidDimensions
        }

        let metersPerCount = Double(near.heightEncoding.centimetersPerCount) / 100
        let heights = map.counts.map {
            Float(near.zeroPointMeters + Double($0) * metersPerCount)
        }
        return Apollo11TerrainHeightField(
            tile: near,
            heights: heights,
            craterCatalog: try loadPinnedCraterCatalog(
                manifest: terrainManifest,
                bundle: bundle
            )
        )
    }

    /// Loads the catalog pinned by the terrain manifest. Its file digest and
    /// embedded provenance must both match so a regenerated catalog cannot
    /// silently change visual or contact geometry.
    nonisolated private static func loadPinnedCraterCatalog(
        manifest: LMTerrainManifest,
        bundle: Bundle
    ) throws -> LMLunarCraterCatalog? {
        guard let pin = manifest.craterCatalog else { return nil }
        let url = try terrainResourceURL(file: pin.file, bundle: bundle)
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == pin.sha256 else {
            throw ResourceError.invalidCraterCatalog(
                "SHA-256 mismatch for \(pin.file)"
            )
        }
        let catalog = try JSONDecoder().decode(
            LMLunarCraterCatalog.self,
            from: data
        )
        guard catalog.catalogID == pin.catalogID else {
            throw ResourceError.invalidCraterCatalog("catalog ID mismatch")
        }
        guard catalog.generatorVersion == pin.generatorVersion else {
            throw ResourceError.invalidCraterCatalog(
                "generator version mismatch"
            )
        }
        guard catalog.sourceIDs == pin.sourceIDs else {
            throw ResourceError.invalidCraterCatalog("source IDs mismatch")
        }
        return catalog
    }

    struct ProgressiveTileBuild: Sendable {
        let mesh: LMProgressiveTerrainMeshData
        let detail: LMTerrainTileDetailTextures
        let detailModelID: String
        let detailCacheHit: Bool
        let meshMilliseconds: Int
        let detailMilliseconds: Int
    }

    struct ProgressiveTileGenerationMetrics: Equatable, Sendable {
        let meshMilliseconds: Int
        let detailMilliseconds: Int
        let realizationMilliseconds: Int
        let detailModelID: String
        let detailCacheHit: Bool
    }

    struct ProgressiveTileEntityBuild {
        let entity: ModelEntity
        let mesh: LMProgressiveTerrainMeshData
        let metrics: ProgressiveTileGenerationMetrics
    }

    @MainActor
    static func makeProgressiveTileEntity(
        heightField: any LMTerrainHeightField,
        plan: LMTerrainTilePlan,
        activePlans: [LMTerrainTilePlan]? = nil,
        geometryReplacementPlans: [LMTerrainTilePlan]? = nil,
        albedoField: LMMeasuredAlbedoField?,
        detailPipeline: LMTerrainDetailPipeline = Apollo11TerrainResource
            .detailPipeline
    ) async throws -> ModelEntity? {
        try await makeProgressiveTileEntityBuild(
            heightField: heightField,
            plan: plan,
            activePlans: activePlans,
            geometryReplacementPlans: geometryReplacementPlans,
            albedoField: albedoField,
            detailPipeline: detailPipeline
        )?.entity
    }

    @MainActor
    static func makeProgressiveTileEntityBuild(
        heightField: any LMTerrainHeightField,
        plan: LMTerrainTilePlan,
        activePlans: [LMTerrainTilePlan]? = nil,
        geometryReplacementPlans: [LMTerrainTilePlan]? = nil,
        albedoField: LMMeasuredAlbedoField?,
        detailPipeline: LMTerrainDetailPipeline = Apollo11TerrainResource
            .detailPipeline
    ) async throws -> ProgressiveTileEntityBuild? {
        let generationTask = Task.detached(priority: .userInitiated) {
            // Geometry and appearance consume the same plan but do not depend
            // on one another. Structured child tasks keep cancellation intact
            // while allowing the two CPU-heavy products to use separate cores.
            async let timedMesh = timedProgressiveTileMesh(
                heightField: heightField,
                plan: plan,
                activePlans: activePlans,
                geometryReplacementPlans: geometryReplacementPlans
            )
            async let timedDetail = timedProgressiveTileDetail(
                plan: plan,
                albedoField: albedoField,
                detailPipeline: detailPipeline
            )
            let meshResult = try await timedMesh
            let detailResult = try await timedDetail
            guard let mesh = meshResult.value else {
                return ProgressiveTileBuild?.none
            }
            return ProgressiveTileBuild(
                mesh: mesh,
                detail: LMTerrainTileDetailBaker.addingSamplingGutter(
                    to: detailResult.value.textures
                ),
                detailModelID: detailResult.value.modelID,
                detailCacheHit: detailResult.value.cacheHit,
                meshMilliseconds: meshResult.milliseconds,
                detailMilliseconds: detailResult.milliseconds
            )
        }
        let build = try await withTaskCancellationHandler(
            operation: { try await generationTask.value },
            onCancel: { generationTask.cancel() }
        )
        guard let build else { return nil }
        let data = build.mesh

        let realizationStarted = ContinuousClock.now
        var descriptor = MeshDescriptor(name: "Progressive LROC tile")
        descriptor.positions = MeshBuffers.Positions(data.positions)
        descriptor.normals = MeshBuffers.Normals(data.normals)
        descriptor.tangents = MeshBuffers.Tangents(data.tangents)
        descriptor.bitangents = MeshBuffers.Tangents(data.bitangents)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(data.textureCoordinates)
        descriptor.primitives = .triangles(data.indices)
        let mesh = try LMLunarTerrainTiming.measure("mesh-upload") {
            try MeshResource.generate(from: [descriptor])
        }
        let material = try LMLunarTerrainTiming.measure("material-upload") {
            try LMTerrainWorld.detailTerrainMaterial(build.detail, plan: plan)
        }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        if heightField.resolvesProceduralSamples {
            entity.position = SIMD3(Float(plan.centerNorthMeters), 0, Float(-plan.centerEastMeters))
        }
        let geologyID = LMProgressiveTerrainSampler(
            heightField: heightField
        ).geology.versionedModelID
        entity.name = "LROC progressive \(geologyID) + \(build.detailModelID) L\(plan.id.level) E\(plan.id.eastIndex) N\(plan.id.northIndex) \(plan.sampleSpacingMeters)m"
        return ProgressiveTileEntityBuild(
            entity: entity,
            mesh: data,
            metrics: ProgressiveTileGenerationMetrics(
                meshMilliseconds: build.meshMilliseconds,
                detailMilliseconds: build.detailMilliseconds,
                realizationMilliseconds: milliseconds(
                    realizationStarted.duration(to: .now)
                ),
                detailModelID: build.detailModelID,
                detailCacheHit: build.detailCacheHit
            )
        )
    }

    nonisolated private static func milliseconds(
        _ duration: ContinuousClock.Duration
    ) -> Int {
        Int(
            duration.components.seconds * 1_000
                + duration.components.attoseconds / 1_000_000_000_000_000
        )
    }

    nonisolated private static func timedProgressiveTileMesh(
        heightField: any LMTerrainHeightField,
        plan: LMTerrainTilePlan,
        activePlans: [LMTerrainTilePlan]?,
        geometryReplacementPlans: [LMTerrainTilePlan]?
    ) throws -> (value: LMProgressiveTerrainMeshData?, milliseconds: Int) {
        let started = ContinuousClock.now
        let interval = LMLunarTerrainTiming.begin("cpu-mesh")
        defer { LMLunarTerrainTiming.end(interval) }
        let value = try makeProgressiveTileMeshData(
            heightField: heightField,
            plan: plan,
            activePlans: activePlans,
            geometryReplacementPlans: geometryReplacementPlans
        )
        return (value, milliseconds(started.duration(to: .now)))
    }

    nonisolated private static func timedProgressiveTileDetail(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?,
        detailPipeline: LMTerrainDetailPipeline
    ) async throws -> (value: LMTerrainDetailPipeline.Product, milliseconds: Int) {
        let interval = LMLunarTerrainTiming.begin("appearance-bake")
        defer { LMLunarTerrainTiming.end(interval) }
        let value = try await detailPipeline.textures(
            plan: plan,
            albedoField: albedoField
        )
        return (value, value.generationMilliseconds)
    }

    nonisolated static func makeProgressiveTileMeshData(
        heightField: any LMTerrainHeightField,
        plan: LMTerrainTilePlan,
        activePlans: [LMTerrainTilePlan]? = nil,
        geometryReplacementPlans: [LMTerrainTilePlan]? = nil
    ) throws -> LMProgressiveTerrainMeshData? {
        let tileSize = plan.sizeMeters
        let sampleSpacing = plan.sampleSpacingMeters
        let sampleCount = Int(tileSize / sampleSpacing) + 1
        // Precompute the geology once for this tile. The surface is unchanged;
        // only the number of times the generator hash runs is.
        let surfaceSampler = LMProgressiveTerrainSurfaceSampler(
            heightField: heightField
        ).prepared(for: plan)
        // A standalone tile has no same-level neighbors, even if its plan was
        // copied from a larger footprint. Production callers pass the complete
        // residency set so shared edges retain their actual ownership.
        let meshPlan = activePlans == nil ? plan.withTransitionEdges(.all) : plan
        let residentPlans = activePlans ?? [meshPlan]
        // Residency determines the hierarchical height/morph evaluation, but
        // only fully opaque children may take geometric ownership from this
        // parent. Keeping those inputs separate prevents a preloaded or
        // crossfading child from exposing the immersive background through a
        // parent hole.
        let finerResidentPlans = (geometryReplacementPlans ?? residentPlans).filter {
            $0.sampleSpacingMeters < plan.sampleSpacingMeters - 1e-9
        }
        let halfSize = tileSize / 2

        var positions = [SIMD3<Float>]()
        var levelContributions = [Float]()
        var textureCoordinates = [SIMD2<Float>]()
        positions.reserveCapacity(sampleCount * sampleCount)
        levelContributions.reserveCapacity(sampleCount * sampleCount)
        textureCoordinates.reserveCapacity(sampleCount * sampleCount)

        for row in 0..<sampleCount {
            try Task.checkCancellation()
            let north = plan.centerNorthMeters + halfSize - Double(row) * sampleSpacing
            for column in 0..<sampleCount {
                let east = plan.centerEastMeters - halfSize + Double(column) * sampleSpacing
                guard let sample = surfaceSampler.renderedElevationSample(
                    eastMeters: east,
                    northMeters: north,
                    plan: meshPlan,
                    activePlans: residentPlans
                ) else {
                    return nil
                }
                positions.append(SIMD3(
                    Float(north - (heightField.resolvesProceduralSamples ? plan.centerNorthMeters : 0)),
                    sample.elevationMeters,
                    Float(-east + (heightField.resolvesProceduralSamples ? plan.centerEastMeters : 0))
                ))
                levelContributions.append(sample.levelContributionMeters)
                textureCoordinates.append(SIMD2(
                    LMTerrainTileDetailBaker.renderingTextureCoordinate(
                        contentFraction: Float(column) / Float(sampleCount - 1)
                    ),
                    LMTerrainTileDetailBaker.renderingTextureCoordinate(
                        // Baked CGImage rows run north-to-south, while
                        // RealityKit texture V runs bottom-to-top. Address the
                        // northern image row at V=1 so every world edge meets
                        // the corresponding neighbor instead of a vertically
                        // mirrored sample from the opposite side of its tile.
                        contentFraction: 1
                            - Float(row) / Float(sampleCount - 1)
                    )
                ))
            }
        }

        var normals = [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: positions.count)
        var tangents = [SIMD3<Float>](repeating: SIMD3(0, 0, -1), count: positions.count)
        var bitangents = [SIMD3<Float>](repeating: SIMD3(-1, 0, 0), count: positions.count)
        var addedReliefNormalDistribution = LMTerrainNormalDistribution.Accumulator()
        for row in 0..<sampleCount {
            for column in 0..<sampleCount {
                let leftColumn = max(column - 1, 0)
                let rightColumn = min(column + 1, sampleCount - 1)
                let northRow = max(row - 1, 0)
                let southRow = min(row + 1, sampleCount - 1)
                let northMeters = plan.centerNorthMeters + halfSize
                    - Double(row) * sampleSpacing
                let eastMeters = plan.centerEastMeters - halfSize
                    + Double(column) * sampleSpacing
                var left = positions[row * sampleCount + leftColumn]
                var right = positions[row * sampleCount + rightColumn]
                var north = positions[northRow * sampleCount + column]
                var south = positions[southRow * sampleCount + column]
                if column == 0, let elevation = surfaceSampler.renderedElevationAround(
                    eastMeters: eastMeters - sampleSpacing,
                    northMeters: northMeters,
                    referencePlan: meshPlan,
                    activePlans: residentPlans
                ) {
                    left = SIMD3(
                        Float(northMeters),
                        elevation,
                        Float(-(eastMeters - sampleSpacing))
                    )
                }
                if column == sampleCount - 1,
                   let elevation = surfaceSampler.renderedElevationAround(
                       eastMeters: eastMeters + sampleSpacing,
                       northMeters: northMeters,
                       referencePlan: meshPlan,
                       activePlans: residentPlans
                   ) {
                    right = SIMD3(
                        Float(northMeters),
                        elevation,
                        Float(-(eastMeters + sampleSpacing))
                    )
                }
                if row == 0, let elevation = surfaceSampler.renderedElevationAround(
                    eastMeters: eastMeters,
                    northMeters: northMeters + sampleSpacing,
                    referencePlan: meshPlan,
                    activePlans: residentPlans
                ) {
                    north = SIMD3(
                        Float(northMeters + sampleSpacing),
                        elevation,
                        Float(-eastMeters)
                    )
                }
                if row == sampleCount - 1,
                   let elevation = surfaceSampler.renderedElevationAround(
                       eastMeters: eastMeters,
                       northMeters: northMeters - sampleSpacing,
                       referencePlan: meshPlan,
                       activePlans: residentPlans
                   ) {
                    south = SIMD3(
                        Float(northMeters - sampleSpacing),
                        elevation,
                        Float(-eastMeters)
                    )
                }
                let index = row * sampleCount + column
                var normal = SIMD3<Float>(0, 1, 0)
                let measuredNormal = heightField.interpolatedSurfaceNormal(
                    eastMeters: eastMeters,
                    northMeters: northMeters
                ) ?? SIMD3<Float>(0, 1, 0)
                let measuredNorthSlope = -measuredNormal.x / measuredNormal.y
                let measuredEastSlope = measuredNormal.z / measuredNormal.y
                func residualHeight(
                    _ position: SIMD3<Float>,
                    east: Double,
                    north: Double
                ) -> Float {
                    position.y - (heightField.relativeElevation(
                        eastMeters: east,
                        northMeters: north
                    ) ?? position.y)
                }
                let leftEast = eastMeters - sampleSpacing
                let rightEast = eastMeters + sampleSpacing
                let northCoordinate = northMeters + sampleSpacing
                let southCoordinate = northMeters - sampleSpacing
                let residualEastSlope = (
                    residualHeight(
                        right,
                        east: rightEast,
                        north: northMeters
                    ) - residualHeight(
                        left,
                        east: leftEast,
                        north: northMeters
                    )
                ) / Float(2 * sampleSpacing)
                let residualNorthSlope = (
                    residualHeight(
                        north,
                        east: eastMeters,
                        north: northCoordinate
                    ) - residualHeight(
                        south,
                        east: eastMeters,
                        north: southCoordinate
                    )
                ) / Float(2 * sampleSpacing)
                normal = simd_normalize(SIMD3<Float>(
                    -(measuredNorthSlope + residualNorthSlope),
                    1,
                    measuredEastSlope + residualEastSlope
                ))
                if heightField.resolvesProceduralSamples {
                    if let parent = heightField.renderedParent(eastMeters: eastMeters, northMeters: northMeters,
                                                               spacingMeters: sampleSpacing) {
                        var distance = Double.infinity
                        if meshPlan.transitionEdges.contains(.west) { distance = min(distance, eastMeters - plan.centerEastMeters + halfSize) }
                        if meshPlan.transitionEdges.contains(.east) { distance = min(distance, plan.centerEastMeters + halfSize - eastMeters) }
                        if meshPlan.transitionEdges.contains(.north) { distance = min(distance, plan.centerNorthMeters + halfSize - northMeters) }
                        if meshPlan.transitionEdges.contains(.south) { distance = min(distance, northMeters - plan.centerNorthMeters + halfSize) }
                        let t = Float(min(1, max(0, distance / min(tileSize / 4, parent.spacing * 8))))
                        normal = simd_normalize(simd_mix(parent.normal, normal, SIMD3(repeating: t * t * (3 - 2 * t))))
                    }
                }
                normals[index] = normal
                // u runs east (RealityKit -Z) and v runs south (-X). Orthogonalize
                // the tangent against the vertex normal so the baked tangent-space
                // normal map lands in the same basis the baker assumed.
                let rawTangent = SIMD3<Float>(0, 0, -1)
                let tangent = simd_normalize(
                    rawTangent - normal * simd_dot(normal, rawTangent)
                )
                tangents[index] = tangent
                bitangents[index] = simd_cross(normal, tangent)

                let eastSpan = Float(rightColumn - leftColumn) * Float(sampleSpacing)
                let northSpan = Float(southRow - northRow) * Float(sampleSpacing)
                let eastSlope = (
                    levelContributions[row * sampleCount + rightColumn]
                        - levelContributions[row * sampleCount + leftColumn]
                ) / eastSpan
                let northSlope = (
                    levelContributions[northRow * sampleCount + column]
                        - levelContributions[southRow * sampleCount + column]
                ) / northSpan
                // Match the detail baker's T=east, B=south, N=up basis so the
                // mesh and normal-map distributions can be evaluated together.
                addedReliefNormalDistribution.add(simd_normalize(SIMD3(
                    -eastSlope,
                    northSlope,
                    1
                )))
            }
        }

        var indices = [UInt32]()
        indices.reserveCapacity((sampleCount - 1) * (sampleCount - 1) * 6)
        for row in 0..<(sampleCount - 1) {
            for column in 0..<(sampleCount - 1) {
                // A finer resident tile replaces its parent geometrically.
                // Keeping both complete meshes lets the parent win the depth
                // test wherever fine procedural relief dips below it, which
                // exposes the finer footprint as an irregular rectangular
                // card. Tile boundaries align across these 4x levels, and the
                // child already reaches the exact rendered parent along its
                // perimeter, so removing covered parent quads creates neither
                // a crack nor a contact offset.
                let quadNorth = plan.centerNorthMeters + halfSize
                    - (Double(row) + 0.5) * sampleSpacing
                let quadEast = plan.centerEastMeters - halfSize
                    + (Double(column) + 0.5) * sampleSpacing
                if finerResidentPlans.contains(where: {
                    let finerHalfSize = $0.sizeMeters / 2
                    return quadEast > $0.centerEastMeters - finerHalfSize
                        && quadEast < $0.centerEastMeters + finerHalfSize
                        && quadNorth > $0.centerNorthMeters - finerHalfSize
                        && quadNorth < $0.centerNorthMeters + finerHalfSize
                }) {
                    continue
                }
                let northwest = UInt32(row * sampleCount + column)
                let northeast = northwest + 1
                let southwest = UInt32((row + 1) * sampleCount + column)
                let southeast = southwest + 1
                indices.append(contentsOf: [
                    northwest, northeast, southwest,
                    northeast, southeast, southwest,
                ])
            }
        }

        return LMProgressiveTerrainMeshData(
            positions: positions,
            normals: normals,
            tangents: tangents,
            bitangents: bitangents,
            addedReliefNormalDistribution: addedReliefNormalDistribution.finalized(),
            textureCoordinates: textureCoordinates,
            indices: indices
        )
    }

    private nonisolated static func terrainResourceURL(
        file: String,
        bundle: Bundle
    ) throws -> URL {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Terrain"
        ) ?? bundle.url(forResource: name, withExtension: ext) else {
            throw ResourceError.missingResource("Terrain/\(file)")
        }
        return url
    }
}
