@testable import LunarMap
import Foundation
import Testing
import LMCore
import simd

// Verbatim fixture builders for unchanged cockpit integration tests.
struct LMLunarTerrainArrivalTests {
    func tile(level: Int, spacing: Double, fine: Bool) -> LMLunarTerrainMeshTile {
        let plan = LMTerrainTilePlan(id: .init(level: level, eastIndex: 0, northIndex: 0),
                                    centerEastMeters: 2, centerNorthMeters: 2, sizeMeters: 4,
                                    sampleSpacingMeters: spacing, containsProceduralSubresolution: fine)
        let side = Int(4 / spacing) + 1
        var positions = [SIMD3<Float>](), indices = [UInt32]()
        for row in 0..<side {
            for column in 0..<side {
                let e = Double(column) * spacing, n = 4 - Double(row) * spacing
                // A saddle makes bilinear interpolation fail against triangles.
                let residual = fine ? 0.12 * sin(e * .pi / 2) * sin(n * .pi / 2) : 0
                positions.append(SIMD3(Float(n - 2), Float(e * n / 20 + residual), Float(2 - e)))
                if row < side - 1 && column < side - 1 {
                    let nw = UInt32(row * side + column), ne = nw + 1, sw = nw + UInt32(side)
                    indices += [nw, ne, sw, ne, sw + 1, sw]
                }
            }
        }
        return .init(plan: plan, mesh: .init(positions: positions,
            normals: Array(repeating: SIMD3(0, 1, 0), count: positions.count), tangents: [], bitangents: [],
            addedReliefNormalDistribution: .flat, textureCoordinates: [], indices: indices))
    }
}

struct LMLunarContactTests {
    func region(at coordinate: LMSelenographicCoordinate) throws -> LMLunarTerrainRegion {
        let source = try #require(LMTerrainManifest.load().sources.first { $0.productId == "LDEM_16" })
        let url = try #require(LunarMap.resources.url(forResource: source.bundledFile, withExtension: nil, subdirectory: "Terrain"))
        let base = try LMLunarElevationGrid(data: Data(contentsOf: url, options: .mappedIfSafe), source: source)
        let terrain = LMLunarResolvedTerrain(base: base, refinements: [])
        let elevation = try #require(base.elevation(at: coordinate))
        let frame = LMSelenographicCoordinateSystem().localFrame(at: .init(latitudeDegrees: coordinate.latitudeDegrees,
                                                                          longitudeDegrees: coordinate.longitudeDegrees, heightMeters: elevation))
        return .init(terrain: terrain, frame: frame,
                     albedo: .init(width: 0, height: 0, halfExtentMeters: 0, luminance: []),
                     sourceIDs: [source.id], unavailableSourceIDs: [], measuredFloorMeters: base.spacingMeters)
    }
}
