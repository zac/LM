import Foundation
import Testing
import simd
@testable import LM

@Suite("Lunar terrain arrival")
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

    @Test func commonRefinementMatchesBothTriangleEndpointsAndContact() throws {
        let coarse = LMLunarTerrainMeshSnapshot(tiles: [tile(level: 0, spacing: 2, fine: false)])
        let fine = LMLunarTerrainMeshSnapshot(tiles: [tile(level: 1, spacing: 0.5, fine: true)])
        for (before, after) in [(coarse, fine), (fine, coarse)] {
            let morph = try LMLunarTerrainMorph(from: before, to: after)
            for weight: Float in [0, 0.1, 0.5, 0.9, 1] {
                let displayed = morph.snapshot(weight: weight)
                for i in 0..<40 {
                    let east = 0.07 + Double(i % 8) * 0.49, north = 0.13 + Double(i / 8) * 0.73
                    let a = try #require(before.sample(east: east, north: north)).elevation
                    let b = try #require(after.sample(east: east, north: north)).elevation
                    let expected = a + (b - a) * weight
                    let contact = try #require(displayed.sample(east: east, north: north)).elevation
                    let ray = try #require(displayed.raycast(origin: SIMD3(Float(north), 2, Float(-east)),
                                                            direction: SIMD3(0, -1, 0)))
                    #expect(abs(contact - expected) < 0.000001)
                    #expect(abs(ray.position.y - contact) < 0.000001)
                }
                // Native coarse posts never acquire the fine residual.
                for east in [0.0, 2, 4] {
                    for north in [0.0, 2, 4] {
                        let a = try #require(coarse.sample(east: east, north: north)).elevation
                        #expect(displayed.sample(east: east, north: north)?.elevation == a)
                    }
                }
            }
            // Fine ownership must remove every covered parent triangle.
            #expect(morph.tiles.first { $0.plan.id.level == 0 }?.end.indices.isEmpty == true)
        }
    }

    @Test func interruptedMorphCanStartFromTheDisplayedTriangles() throws {
        let coarse = LMLunarTerrainMeshSnapshot(tiles: [tile(level: 0, spacing: 2, fine: false)])
        let fine = LMLunarTerrainMeshSnapshot(tiles: [tile(level: 1, spacing: 0.5, fine: true)])
        let first = try LMLunarTerrainMorph(from: coarse, to: fine).snapshot(weight: 0.37)
        let restarted = try LMLunarTerrainMorph(from: first, to: coarse).snapshot(weight: 0)
        for i in 0..<30 {
            let east = 0.1 + Double(i % 6) * 0.61, north = 0.2 + Double(i / 6) * 0.71
            let a = try #require(first.sample(east: east, north: north)).elevation
            let b = try #require(restarted.sample(east: east, north: north)).elevation
            #expect(abs(a - b) < 0.000001)
        }
    }

    @Test func easingHasExactEndpointsAndMonotonicWeights() {
        #expect(LMLunarTerrainMorph.weight(fraction: -1) == 0)
        #expect(LMLunarTerrainMorph.weight(fraction: 2) == 1)
        var last: Float = 0
        for i in 0...100 {
            let next = LMLunarTerrainMorph.weight(fraction: Double(i) / 100)
            #expect(next >= last && next <= 1)
            last = next
        }
    }
}
