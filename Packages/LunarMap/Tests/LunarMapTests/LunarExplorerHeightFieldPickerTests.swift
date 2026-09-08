@testable import LunarMapExplorer
@testable import LunarMap
import Testing
import simd

@Suite("Measured height-field gesture picking")
struct LunarExplorerHeightFieldPickerTests {
    @Test(arguments: [0.0, 4.0])
    func marcherMatchesIndependentTriangleSearch(hole: Double) throws {
        let posts = 17, spacing = 2.0, half: Float = 16
        var heights: [Float] = []
        var positions: [SIMD3<Float>] = []
        for row in 0..<posts {
            for column in 0..<posts {
                let height = sin(Float(row) * 0.6) * 3 + Float(column) * 0.2
                heights.append(height)
                positions.append(SIMD3(half - Float(row) * 2, height, half - Float(column) * 2))
            }
        }
        let picker = LunarExplorerHeightFieldPicker(posts: posts, spacingMeters: spacing,
            heights: heights, holeHalfExtentMeters: hole)
        var triangles: [(Int, Int, Int)] = []
        for row in 0..<(posts - 1) {
            for column in 0..<(posts - 1) {
                let center = positions[row * posts + column] - SIMD3<Float>(1, 0, 1)
                if abs(center.x) < Float(hole) && abs(center.z) < Float(hole) { continue }
                let a = row * posts + column
                triangles += [(a, a + 1, a + posts), (a + 1, a + posts + 1, a + posts)]
            }
        }
        let directions: [SIMD3<Float>] = [
            SIMD3(0, -1, 0), SIMD3(0.2, -1, -0.3), SIMD3(-0.4, -1, 0.4),
            SIMD3(1, -0.05, 0), SIMD3(0, 1, 0)
        ]
        for x in stride(from: -20, through: 20, by: 4) {
            for z in stride(from: -20, through: 20, by: 4) {
                let origin = SIMD3<Float>(Float(x), 12, Float(z))
                for direction in directions {
                    let direction = simd_normalize(direction)
                    var nearest = Float.infinity
                    for (a, b, c) in triangles {
                        if let t = LunarExplorerPinchGeometry.triangleDistance(origin: origin, direction: direction,
                            a: positions[a], b: positions[b], c: positions[c]) { nearest = min(nearest, t) }
                    }
                    let hit = picker.raycast(origin: origin, direction: direction)
                    if nearest.isFinite {
                        let hit = try #require(hit)
                        #expect(simd_distance(hit, origin + direction * nearest) < 0.0001)
                    } else { #expect(hit == nil) }
                }
            }
        }
    }

    @Test func nestedBandsKeepHoleOwnershipAndRegionalPrecision() throws {
        let near = LunarExplorerHeightFieldPicker(posts: 9, spacingMeters: 2,
            heights: Array(repeating: 1, count: 81))
        let outer = LunarExplorerHeightFieldPicker(posts: 9, spacingMeters: 4,
            heights: Array(repeating: 2, count: 81), holeHalfExtentMeters: 8)
        #expect(outer.raycast(origin: SIMD3(0, 100_000, 0), direction: SIMD3(0, -1, 0)) == nil)
        let hit = try #require(near.raycast(origin: SIMD3(0, 100_000, 0), direction: SIMD3(0, -1, 0)))
        #expect(hit.y == 1)
        #expect(outer.raycast(origin: SIMD3(12, 100_000, 0), direction: SIMD3(0, -1, 0))?.y == 2)
        #expect(near.raycast(origin: SIMD3(20, 1, 0), direction: SIMD3(0, 0, 1)) == nil)
        #expect(near.raycast(origin: .zero, direction: .zero) == nil)
    }
}
