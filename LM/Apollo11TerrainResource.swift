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

    @MainActor
    static func makeProgressiveTileEntity(
        heightField: Apollo11TerrainHeightField,
        plan: LMTerrainTilePlan,
        albedoTexture: TextureResource
    ) async throws -> ModelEntity? {
        let tileSize = plan.sizeMeters
        let sampleSpacing = plan.sampleSpacingMeters
        let sampleCount = Int(tileSize / sampleSpacing) + 1
        let sampler = LMProgressiveTerrainSampler(heightField: heightField)
        let halfSize = tileSize / 2

        var positions = [SIMD3<Float>]()
        var textureCoordinates = [SIMD2<Float>]()
        positions.reserveCapacity(sampleCount * sampleCount)
        textureCoordinates.reserveCapacity(sampleCount * sampleCount)

        let measuredHalfWidth = Double(heightField.width - 1) * heightField.spacingMeters / 2
        let measuredHalfDepth = Double(heightField.height - 1) * heightField.spacingMeters / 2
        let layerOffset = layerOffsetMeters(
            sourceSpacingMeters: heightField.spacingMeters,
            requestedSpacingMeters: sampleSpacing
        )
        for row in 0..<sampleCount {
            let north = plan.centerNorthMeters + halfSize - Double(row) * sampleSpacing
            for column in 0..<sampleCount {
                let east = plan.centerEastMeters - halfSize + Double(column) * sampleSpacing
                guard let sample = sampler.sample(
                    eastMeters: east,
                    northMeters: north,
                    requestedSpacingMeters: sampleSpacing
                ) else {
                    return nil
                }
                positions.append(SIMD3(
                    Float(north),
                    sample.elevationMeters + layerOffset,
                    Float(-east)
                ))
                textureCoordinates.append(textureCoordinate(
                    eastMeters: east,
                    northMeters: north,
                    measuredHalfWidth: measuredHalfWidth,
                    measuredHalfDepth: measuredHalfDepth
                ))
            }
        }

        var normals = [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: positions.count)
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
                normals[row * sampleCount + column] = simd_normalize(
                    simd_cross(right - left, south - north)
                )
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
                    northwest, southwest, northeast,
                    northeast, southwest, southeast,
                ])
            }
        }

        var descriptor = MeshDescriptor(name: "Progressive LROC tile")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(textureCoordinates)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        let material = LMTerrainWorld.terrainMaterial(texture: albedoTexture)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "LROC progressive L\(plan.id.level) E\(plan.id.eastIndex) N\(plan.id.northIndex) \(sampleSpacing)m"
        return entity
    }

    /// North-up image rows run from north at v=0 to south at v=1, matching
    /// `LMTerrainMeshBuilder` and the generator's row-major PDS sampling.
    nonisolated static func textureCoordinate(
        eastMeters: Double,
        northMeters: Double,
        measuredHalfWidth: Double,
        measuredHalfDepth: Double
    ) -> SIMD2<Float> {
        SIMD2(
            Float((eastMeters + measuredHalfWidth) / (measuredHalfWidth * 2)),
            Float((measuredHalfDepth - northMeters) / (measuredHalfDepth * 2))
        )
    }

    private static func layerOffsetMeters(
        sourceSpacingMeters: Double,
        requestedSpacingMeters: Double
    ) -> Float {
        Float(max(log2(sourceSpacingMeters / requestedSpacingMeters), 1) * 0.004)
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
