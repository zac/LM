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

    /// Build grid vertices for a tile. `holeHalfExtentMeters` skips quads whose
    /// centers lie inside an exactly aligned nested-tile boundary.
    static func grid(
        tile: LMTerrainManifest.Tile,
        heightMap: LMTerrainHeightMap,
        holeHalfExtentMeters: Double = 0
    ) throws -> VertexData {
        guard heightMap.width == tile.postsPerSide,
              heightMap.height == tile.postsPerSide else {
            throw MeshError.dimensionMismatch
        }
        let posts = tile.postsPerSide
        let spacing = Float(tile.postSpacingMeters)
        let halfExtent = Float(tile.extentMeters) / 2.0
        let holeLimit = Float(holeHalfExtentMeters)

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
                    zeroPointMeters: tile.zeroPointMeters,
                    centimetersPerCount: tile.heightEncoding.centimetersPerCount
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
                data.triangles.append(contentsOf: [v0, v1, v2, v1, v3, v2])
            }
        }
        return data
    }

    /// Hand a measured child band to its coarser parent before the child's
    /// square tile edge is reached.
    ///
    /// The source-conditioned albedo uses the same landing-centered radial
    /// smoothstep. Matching both height and vertex-normal LOD prevents the 2 m
    /// NAC mesh from reading as a rectangular card against the 32 m SLDEM
    /// parent and makes every child edge equal the parent's bilinear surface.
    /// Source samples remain untouched in the assets; only the outer render
    /// collar is geomorphed, well outside the Apollo 11 terminal site.
    static func morphToParent(
        child: VertexData,
        parent: VertexData,
        parentTile: LMTerrainManifest.Tile,
        childHalfExtentMeters: Double
    ) throws -> VertexData {
        let parentPosts = parentTile.postsPerSide
        guard parent.normals.count == parentPosts * parentPosts,
              child.positions.count == child.normals.count else {
            throw MeshError.dimensionMismatch
        }
        let parentHalfExtent = Float(parentTile.extentMeters / 2)
        let parentSpacing = Float(parentTile.postSpacingMeters)
        let childHalfExtent = Float(childHalfExtentMeters)
        guard childHalfExtent > 0 else { return child }

        func parentSample(
            north: Float,
            east: Float
        ) -> (height: Float, normal: SIMD3<Float>) {
            let column = min(
                max((east + parentHalfExtent) / parentSpacing, 0),
                Float(parentPosts - 1)
            )
            let row = min(
                max((parentHalfExtent - north) / parentSpacing, 0),
                Float(parentPosts - 1)
            )
            let column0 = Int(column.rounded(.down))
            let row0 = Int(row.rounded(.down))
            let column1 = min(column0 + 1, parentPosts - 1)
            let row1 = min(row0 + 1, parentPosts - 1)
            let eastBlend = column - Float(column0)
            let southBlend = row - Float(row0)
            let northWest = parent.normals[row0 * parentPosts + column0]
            let northEast = parent.normals[row0 * parentPosts + column1]
            let southWest = parent.normals[row1 * parentPosts + column0]
            let southEast = parent.normals[row1 * parentPosts + column1]
            let northNormal = northWest + (northEast - northWest) * eastBlend
            let southNormal = southWest + (southEast - southWest) * eastBlend
            let northWestHeight = parent.positions[row0 * parentPosts + column0].y
            let northEastHeight = parent.positions[row0 * parentPosts + column1].y
            let southWestHeight = parent.positions[row1 * parentPosts + column0].y
            let southEastHeight = parent.positions[row1 * parentPosts + column1].y
            let northHeight = northWestHeight
                + (northEastHeight - northWestHeight) * eastBlend
            let southHeight = southWestHeight
                + (southEastHeight - southWestHeight) * eastBlend
            return (
                northHeight + (southHeight - northHeight) * southBlend,
                simd_normalize(
                    northNormal + (southNormal - northNormal) * southBlend
                )
            )
        }

        var result = child
        for index in result.positions.indices {
            let position = result.positions[index]
            let north = position.x
            let east = -position.z
            let radius = hypot(north, east)
            let normalizedInterior = min(
                max(1 - radius / childHalfExtent, 0),
                1
            )
            let detailWeight = normalizedInterior * normalizedInterior
                * (3 - 2 * normalizedInterior)
            guard detailWeight < 1 else { continue }
            let coarse = parentSample(north: north, east: east)
            let detailedHeight = result.positions[index].y
            result.positions[index].y = coarse.height
                + (detailedHeight - coarse.height) * detailWeight
            let detailedNormal = result.normals[index]
            result.normals[index] = simd_normalize(
                coarse.normal + (detailedNormal - coarse.normal) * detailWeight
            )
        }
        return result
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

    /// Remove measured-base quads that are owned by resident progressive
    /// tiles. Progressive relief legitimately dips below the measured 2 m
    /// parent; drawing both surfaces made the depth buffer reveal the parent
    /// as moving gray islands inside otherwise rectangular fine footprints.
    /// Tile boundaries are aligned to the measured grid, so this produces one
    /// watertight owner per quad without lifting visual terrain away from the
    /// contact surface.
    static func excludingProgressiveFootprints(
        from data: VertexData,
        plans: [LMTerrainTilePlan]
    ) -> VertexData {
        guard !plans.isEmpty else { return data }
        var result = data
        result.triangles.removeAll(keepingCapacity: true)
        result.triangles.reserveCapacity(data.triangles.count)
        for offset in stride(from: 0, to: data.triangles.count, by: 3) {
            let triangle = data.triangles[offset..<(offset + 3)]
            let positions = triangle.map { data.positions[Int($0)] }
            let centerNorth = positions.reduce(Float.zero) { $0 + $1.x } / 3
            let centerEast = -positions.reduce(Float.zero) { $0 + $1.z } / 3
            let covered = plans.contains { plan in
                let half = Float(plan.sizeMeters / 2)
                return centerEast > Float(plan.centerEastMeters) - half
                    && centerEast < Float(plan.centerEastMeters) + half
                    && centerNorth > Float(plan.centerNorthMeters) - half
                    && centerNorth < Float(plan.centerNorthMeters) + half
            }
            if !covered {
                result.triangles.append(contentsOf: triangle)
            }
        }
        return result
    }
}
