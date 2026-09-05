import Foundation
import simd

/// A common refinement of two published, aligned clipmaps. Each endpoint is
/// sampled from the displayed triangles, never from the procedural generator.
struct LMLunarTerrainMorph: Sendable {
    struct Tile: Sendable {
        let plan: LMTerrainTilePlan
        let start: LMProgressiveTerrainMeshData
        let end: LMProgressiveTerrainMeshData

        func displayed(weight: Float) -> LMLunarTerrainMeshTile {
            .init(plan: plan, mesh: end, startMesh: start, morphWeight: min(1, max(0, weight)))
        }
    }
    let tiles: [Tile]

    init(from: LMLunarTerrainMeshSnapshot, to: LMLunarTerrainMeshSnapshot) throws {
        var candidates = Dictionary(uniqueKeysWithValues: from.tiles.map { ($0.plan.id, $0) })
        for tile in to.tiles { candidates[tile.plan.id] = tile }
        let ordered = candidates.values.sorted {
            if $0.plan.sampleSpacingMeters != $1.plan.sampleSpacingMeters {
                return $0.plan.sampleSpacingMeters < $1.plan.sampleSpacingMeters
            }
            if $0.plan.id.northIndex != $1.plan.id.northIndex { return $0.plan.id.northIndex < $1.plan.id.northIndex }
            return $0.plan.id.eastIndex < $1.plan.id.eastIndex
        }
        var result = [Tile]()
        for candidate in ordered {
            try Task.checkCancellation()
            let plan = candidate.plan
            let half = plan.sizeMeters / 2
            func overlaps(_ other: LMLunarTerrainMeshTile) -> Bool {
                let extent = (plan.sizeMeters + other.plan.sizeMeters) / 2
                return abs(plan.centerEastMeters - other.plan.centerEastMeters) <= extent &&
                    abs(plan.centerNorthMeters - other.plan.centerNorthMeters) <= extent
            }
            let before = LMLunarTerrainMeshSnapshot(tiles: from.tiles.filter(overlaps))
            let after = LMLunarTerrainMeshSnapshot(tiles: to.tiles.filter(overlaps))
            let finer = ordered.filter { $0.plan.sampleSpacingMeters < plan.sampleSpacingMeters && overlaps($0) }
            let side = Int((plan.sizeMeters / plan.sampleSpacingMeters).rounded()) + 1
            guard candidate.mesh.positions.count == side * side else { throw MorphError.invalidGrid }
            var a = candidate.mesh.positions, b = a
            var an = candidate.mesh.normals, bn = an
            for row in 0..<side {
                try Task.checkCancellation()
                for column in 0..<side {
                    let i = row * side + column
                    let east = plan.centerEastMeters - half + Double(column) * plan.sampleSpacingMeters
                    let north = plan.centerNorthMeters + half - Double(row) * plan.sampleSpacingMeters
                    let old = before.sample(east: east, north: north, normalizeNormal: false)
                    let new = after.sample(east: east, north: north, normalizeNormal: false)
                    // Newly covered outer terrain has no preceding surface. Its
                    // available endpoint is retained; interior coverage is shared.
                    guard let first = old ?? new, let last = new ?? old else { throw MorphError.missingSurface }
                    a[i].y = first.elevation
                    b[i].y = last.elevation
                    an[i] = first.normal
                    bn[i] = last.normal
                }
            }
            var indices = [UInt32]()
            for row in 0..<(side - 1) {
                for column in 0..<(side - 1) {
                    let east = plan.centerEastMeters - half + (Double(column) + 0.5) * plan.sampleSpacingMeters
                    let north = plan.centerNorthMeters + half - (Double(row) + 0.5) * plan.sampleSpacingMeters
                    if finer.contains(where: {
                        abs(east - $0.plan.centerEastMeters) < $0.plan.sizeMeters / 2 &&
                        abs(north - $0.plan.centerNorthMeters) < $0.plan.sizeMeters / 2
                    }) { continue }
                    let nw = UInt32(row * side + column), ne = nw + 1, sw = nw + UInt32(side)
                    indices += [nw, ne, sw, ne, sw + 1, sw]
                }
            }
            func mesh(_ positions: [SIMD3<Float>], _ normals: [SIMD3<Float>]) -> LMProgressiveTerrainMeshData {
                var tangents = [SIMD3<Float>](), bitangents = [SIMD3<Float>]()
                for value in normals {
                    let n = simd_normalize(value), east = SIMD3<Float>(0, 0, -1)
                    let tangent = simd_normalize(east - n * simd_dot(n, east))
                    tangents.append(tangent)
                    bitangents.append(simd_cross(n, tangent))
                }
                return .init(positions: positions, normals: normals, tangents: tangents, bitangents: bitangents,
                             addedReliefNormalDistribution: .flat,
                             textureCoordinates: candidate.mesh.textureCoordinates, indices: indices)
            }
            result.append(.init(plan: plan, start: mesh(a, an), end: mesh(b, bn)))
        }
        tiles = result
    }

    func snapshot(weight: Float) -> LMLunarTerrainMeshSnapshot {
        .init(tiles: tiles.map { $0.displayed(weight: weight) })
    }

    static func weight(fraction: Double) -> Float {
        let t = Float(min(1, max(0, fraction)))
        return t * t * (3 - 2 * t)
    }

    enum MorphError: Error { case invalidGrid, missingSurface }
}
