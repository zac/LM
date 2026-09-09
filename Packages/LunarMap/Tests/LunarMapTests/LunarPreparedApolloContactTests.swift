import Foundation
import Testing
@testable import LunarMap

@Suite("Prepared Apollo contact")
struct LunarPreparedApolloContactTests {
    @Test func contactUsesRenderedPostsAndTriangleDiagonalWithEagleDatum() throws {
        let url = try #require(LunarMap.resources.url(
            forResource: "TerrainManifest", withExtension: "json", subdirectory: "Terrain"))
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var tileData = try #require((manifest["tiles"] as? [[String: Any]])?.first)
        tileData["postsPerSide"] = 2
        tileData["postSpacingMeters"] = 2
        tileData["extentMeters"] = 2
        let tile = try JSONDecoder().decode(LMTerrainManifest.Tile.self,
            from: JSONSerialization.data(withJSONObject: tileData))
        // Source samples deliberately differ from the rendered, morphed posts.
        let field = Apollo11TerrainHeightField(tile: tile,
            heights: [100, 100, 100, 100], craterCatalog: nil)
        let positions: [SIMD3<Float>] = [
            SIMD3(1, 7, 1), SIMD3(1, 9, -1),
            SIMD3(-1, 11, 1), SIMD3(-1, 17, -1)
        ]
        let surface = LMTerrainContactSurfaceBuilder.buildPreparedApollo(
            heightField: field, renderedPositions: positions,
            alignment: nil, referenceElevationMeters: 7)
        // Non-planar quad: bilinear interpolation would produce the wrong center.
        let samples: [(north: Double, east: Double, height: Double)] = [
            (1, -1, 0), (1, 1, 2), (-1, -1, 4), (-1, 1, 10),
            (0.5, -0.5, 1.5), (-0.5, 0.5, 6.5), (0, 0, 3),
            (2, 2, 0)
        ]
        for sample in samples {
            #expect(surface.surfaceHeightMeters(northMeters: sample.north,
                eastMeters: sample.east) == sample.height)
        }
    }
}
