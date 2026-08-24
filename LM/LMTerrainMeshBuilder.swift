import simd
import RealityKit

/// Builds RealityKit meshes from terrain height maps.
///
/// Tile grid convention (matches Tools/TerrainGenerator): row 0 is the north
/// edge, column 0 the west edge. RealityKit coordinates follow the shared
/// world mapping — +X north, +Y up, -Z east — so a feature east of the landing
/// origin sits toward -Z.
enum LMTerrainMeshBuilder {
    enum MeshError: Error {
        case dimensionMismatch
    }

    /// Interleaved layout: position float3, normal float3, texcoord float2.
    static let strideBytes = 32

    struct VertexData {
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var texCoords: [SIMD2<Float>]
        var triangles: [UInt32]
    }

    /// Build grid vertices for a tile. `holeExtentMeters` skips quads whose
    /// centers lie inside that square (used to punch the near-field hole in
    /// the horizon ring so the two tiles never overlap).
    static func grid(
        tile: LMTerrainManifest.Tile,
        heightMap: LMTerrainHeightMap,
        holeExtentMeters: Double = 0
    ) throws -> VertexData {
        guard heightMap.width == tile.postsPerSide,
              heightMap.height == tile.postsPerSide else {
            throw MeshError.dimensionMismatch
        }
        let posts = tile.postsPerSide
        let spacing = Float(tile.postSpacingMeters)
        let halfExtent = Float(tile.extentMeters) / 2.0
        let holeLimit = Float(holeExtentMeters)

        var data = VertexData(
            positions: [],
            normals: [],
            texCoords: [],
            triangles: []
        )
        data.positions.reserveCapacity(posts * posts)
        data.normals.reserveCapacity(posts * posts)
        data.texCoords.reserveCapacity(posts * posts)

        for row in 0..<posts {
            let north = halfExtent - Float(row) * spacing
            for column in 0..<posts {
                let east = Float(column) * spacing - halfExtent
                let height = Float(heightMap.heightMeters(
                    atPost: row,
                    column: column,
                    zeroPointMeters: tile.zeroPointMeters
                ))
                data.positions.append(SIMD3(north, height, -east))
                data.texCoords.append(SIMD2(
                    Float(column) / Float(posts - 1),
                    Float(row) / Float(posts - 1)
                ))
            }
        }

        for row in 0..<posts {
            for column in 0..<posts {
                let clampedRow = min(max(row, 1), posts - 2)
                let clampedColumn = min(max(column, 1), posts - 2)
                let centimetersPerCount = Float(tile.heightEncoding.centimetersPerCount)
                // Widen before subtracting: UInt16 slopes go both ways.
                let northDelta = Float(
                    Int(heightMap.counts[(clampedRow - 1) * posts + clampedColumn])
                        - Int(heightMap.counts[(clampedRow + 1) * posts + clampedColumn])
                )
                let eastDelta = Float(
                    Int(heightMap.counts[clampedRow * posts + clampedColumn + 1])
                        - Int(heightMap.counts[clampedRow * posts + clampedColumn - 1])
                )
                let metersPerCount = centimetersPerCount / 100.0
                let inverseSpan = 1.0 / (2.0 * spacing)
                let northSlope = northDelta * metersPerCount * inverseSpan
                let eastSlope = eastDelta * metersPerCount * inverseSpan
                // For p(north, east) = (north, height, -east), the upward
                // surface normal is (-dh/dnorth, 1, dh/deast).
                data.normals.append(simd_normalize(SIMD3(-northSlope, 1, eastSlope)))
            }
        }

        for row in 0..<(posts - 1) {
            for column in 0..<(posts - 1) {
                if holeLimit > 0 {
                    let centerNorth = halfExtent - (Float(row) + 0.5) * spacing
                    let centerEast = (Float(column) + 0.5) * spacing - halfExtent
                    if abs(centerNorth) < holeLimit && abs(centerEast) < holeLimit {
                        continue
                    }
                }
                let v0 = UInt32(row * posts + column)
                let v1 = UInt32(row * posts + column + 1)
                let v2 = UInt32((row + 1) * posts + column)
                let v3 = UInt32((row + 1) * posts + column + 1)
                data.triangles.append(contentsOf: [v0, v2, v1, v1, v2, v3])
            }
        }
        return data
    }

    /// Convert grid vertex data into a RealityKit mesh.
    static func mesh(from data: VertexData) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: "terrain")
        descriptor[MeshBuffers.positions] = MeshBuffer(data.positions)
        descriptor[MeshBuffers.normals] = MeshBuffer(data.normals)
        descriptor[MeshBuffers.textureCoordinates] = MeshBuffer(data.texCoords)
        descriptor.primitives = .triangles(data.triangles)
        return try MeshResource.generate(from: [descriptor])
    }
}
