import Foundation
import RealityKit
import UIKit
import simd

struct Apollo11TerrainHeightField: Equatable, Sendable {
    let tile: LMTerrainManifest.Tile
    let heights: [Float]

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
}

struct LMProgressiveTerrainMeshData: Sendable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let tangents: [SIMD3<Float>]
    let bitangents: [SIMD3<Float>]
    /// Tile-local 0...1 coordinates for the tile's own baked detail textures.
    let textureCoordinates: [SIMD2<Float>]
    let indices: [UInt32]
}

enum Apollo11TerrainResource {
    enum ResourceError: Error, Equatable {
        case missingResource(String)
        case invalidDimensions
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
        return Apollo11TerrainHeightField(tile: near, heights: heights)
    }

    struct ProgressiveTileBuild: Sendable {
        let mesh: LMProgressiveTerrainMeshData
        let detail: LMTerrainTileDetailTextures
        let meshMilliseconds: Int
        let detailMilliseconds: Int
    }

    struct ProgressiveTileGenerationMetrics: Equatable, Sendable {
        let meshMilliseconds: Int
        let detailMilliseconds: Int
        let realizationMilliseconds: Int
    }

    struct ProgressiveTileEntityBuild {
        let entity: ModelEntity
        let metrics: ProgressiveTileGenerationMetrics
    }

    @MainActor
    static func makeProgressiveTileEntity(
        heightField: Apollo11TerrainHeightField,
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?
    ) async throws -> ModelEntity? {
        try await makeProgressiveTileEntityBuild(
            heightField: heightField,
            plan: plan,
            albedoField: albedoField
        )?.entity
    }

    @MainActor
    static func makeProgressiveTileEntityBuild(
        heightField: Apollo11TerrainHeightField,
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?
    ) async throws -> ProgressiveTileEntityBuild? {
        let generationTask = Task.detached(priority: .userInitiated) {
            // Geometry and appearance consume the same plan but do not depend
            // on one another. Structured child tasks keep cancellation intact
            // while allowing the two CPU-heavy products to use separate cores.
            async let timedMesh = timedProgressiveTileMesh(
                heightField: heightField,
                plan: plan
            )
            async let timedDetail = timedProgressiveTileDetail(
                plan: plan,
                albedoField: albedoField
            )
            let meshResult = try await timedMesh
            let detailResult = try await timedDetail
            guard let mesh = meshResult.value else {
                return ProgressiveTileBuild?.none
            }
            return ProgressiveTileBuild(
                mesh: mesh,
                detail: detailResult.value,
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
        let mesh = try MeshResource.generate(from: [descriptor])
        let material = try LMTerrainWorld.detailTerrainMaterial(build.detail)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "LROC progressive \(LMLunarGeologyModel.modelID) + \(LMTerrainTileDetailBaker.modelID) L\(plan.id.level) E\(plan.id.eastIndex) N\(plan.id.northIndex) \(plan.sampleSpacingMeters)m"
        return ProgressiveTileEntityBuild(
            entity: entity,
            metrics: ProgressiveTileGenerationMetrics(
                meshMilliseconds: build.meshMilliseconds,
                detailMilliseconds: build.detailMilliseconds,
                realizationMilliseconds: milliseconds(
                    realizationStarted.duration(to: .now)
                )
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
        heightField: Apollo11TerrainHeightField,
        plan: LMTerrainTilePlan
    ) throws -> (value: LMProgressiveTerrainMeshData?, milliseconds: Int) {
        let started = ContinuousClock.now
        let value = try makeProgressiveTileMeshData(
            heightField: heightField,
            plan: plan
        )
        return (value, milliseconds(started.duration(to: .now)))
    }

    nonisolated private static func timedProgressiveTileDetail(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?
    ) throws -> (value: LMTerrainTileDetailTextures, milliseconds: Int) {
        let started = ContinuousClock.now
        let value = try LMTerrainTileDetailBaker.bake(
            plan: plan,
            albedoField: albedoField
        )
        return (value, milliseconds(started.duration(to: .now)))
    }

    nonisolated static func makeProgressiveTileMeshData(
        heightField: Apollo11TerrainHeightField,
        plan: LMTerrainTilePlan
    ) throws -> LMProgressiveTerrainMeshData? {
        let tileSize = plan.sizeMeters
        let sampleSpacing = plan.sampleSpacingMeters
        let sampleCount = Int(tileSize / sampleSpacing) + 1
        // Precompute the geology once for this tile. The surface is unchanged;
        // only the number of times the generator hash runs is.
        let surfaceSampler = LMProgressiveTerrainSurfaceSampler(
            heightField: heightField
        ).prepared(for: plan)
        let halfSize = tileSize / 2

        var positions = [SIMD3<Float>]()
        var textureCoordinates = [SIMD2<Float>]()
        positions.reserveCapacity(sampleCount * sampleCount)
        textureCoordinates.reserveCapacity(sampleCount * sampleCount)

        for row in 0..<sampleCount {
            try Task.checkCancellation()
            let north = plan.centerNorthMeters + halfSize - Double(row) * sampleSpacing
            for column in 0..<sampleCount {
                let east = plan.centerEastMeters - halfSize + Double(column) * sampleSpacing
                guard let elevation = surfaceSampler.renderedElevation(
                    eastMeters: east,
                    northMeters: north,
                    plan: plan
                ) else {
                    return nil
                }
                positions.append(SIMD3(
                    Float(north),
                    elevation,
                    Float(-east)
                ))
                textureCoordinates.append(SIMD2(
                    Float(column) / Float(sampleCount - 1),
                    Float(row) / Float(sampleCount - 1)
                ))
            }
        }

        var normals = [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: positions.count)
        var tangents = [SIMD3<Float>](repeating: SIMD3(0, 0, -1), count: positions.count)
        var bitangents = [SIMD3<Float>](repeating: SIMD3(-1, 0, 0), count: positions.count)
        for row in 0..<sampleCount {
            for column in 0..<sampleCount {
                let leftColumn = max(column - 1, 0)
                let rightColumn = min(column + 1, sampleCount - 1)
                let northRow = max(row - 1, 0)
                let southRow = min(row + 1, sampleCount - 1)
                let left = positions[row * sampleCount + leftColumn]
                let right = positions[row * sampleCount + rightColumn]
                let north = positions[northRow * sampleCount + column]
                let south = positions[southRow * sampleCount + column]
                let index = row * sampleCount + column
                let normal = simd_normalize(simd_cross(right - left, south - north))
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
            }
        }

        var indices = [UInt32]()
        indices.reserveCapacity((sampleCount - 1) * (sampleCount - 1) * 6)
        for row in 0..<(sampleCount - 1) {
            for column in 0..<(sampleCount - 1) {
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
