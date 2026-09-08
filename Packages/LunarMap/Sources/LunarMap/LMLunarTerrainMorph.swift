import Foundation
import simd

/// A common refinement of two published, aligned clipmaps. Each endpoint is
/// sampled from the displayed triangles, never from the procedural generator.
struct LMLunarTerrainMorph: Sendable {
    struct Tile: Sendable {
        let plan: LMTerrainTilePlan
        /// Original immutable X/Z, UVs and grid, with common ownership indices.
        let mesh: LMProgressiveTerrainMeshData
        let endpoints: LMLunarTerrainMeshTile.Arrival
        let changesGeometry: Bool

        func displayed(weight: Float) -> LMLunarTerrainMeshTile {
            .init(plan: plan, mesh: mesh, arrival: endpoints, morphWeight: min(1, max(0, weight)))
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
            var a = [SIMD4<Float>]()
            var b = [SIMD4<Float>]()
            a.reserveCapacity(side * side)
            b.reserveCapacity(side * side)
            for row in 0..<side {
                try Task.checkCancellation()
                for column in 0..<side {
                    let east = plan.centerEastMeters - half + Double(column) * plan.sampleSpacingMeters
                    let north = plan.centerNorthMeters + half - Double(row) * plan.sampleSpacingMeters
                    let old = before.sample(east: east, north: north, normalizeNormal: false)
                    let new = after.sample(east: east, north: north, normalizeNormal: false)
                    // Newly covered outer terrain has no preceding surface. Its
                    // available endpoint is retained; interior coverage is shared.
                    guard let first = old ?? new, let last = new ?? old else { throw MorphError.missingSurface }
                    a.append(SIMD4(first.normal, first.elevation))
                    b.append(SIMD4(last.normal, last.elevation))
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
            let mesh = LMProgressiveTerrainMeshData(
                positions: candidate.mesh.positions, normals: candidate.mesh.normals,
                tangents: candidate.mesh.tangents, bitangents: candidate.mesh.bitangents,
                addedReliefNormalDistribution: .flat,
                textureCoordinates: candidate.mesh.textureCoordinates, indices: indices)
            // Covered parent samples are retained for contact lookup, but only
            // submitted vertices can make this render mesh dynamic.
            let changesGeometry = indices.contains {
                let i = Int($0)
                return a[i] != b[i]
            }
            result.append(.init(plan: plan, mesh: mesh, endpoints: .init(start: a, end: b), changesGeometry: changesGeometry))
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
