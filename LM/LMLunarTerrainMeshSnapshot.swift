import simd

/// CPU copy of the exact vertices submitted to RealityKit. Parent morphs and
/// landing contact use the same NW/NE/SW, NE/SE/SW triangles as the renderer.
struct LMLunarTerrainMeshTile: Sendable {
    let plan: LMTerrainTilePlan
    let mesh: LMProgressiveTerrainMeshData

    struct Sample: Sendable {
        let elevation: Float
        let normal: SIMD3<Float>
        let spacing: Double
    }

    func sample(east: Double, north: Double) -> Sample? {
        let half = plan.sizeMeters / 2
        let x = (east - plan.centerEastMeters + half) / plan.sampleSpacingMeters
        let y = (plan.centerNorthMeters + half - north) / plan.sampleSpacingMeters
        let side = Int((plan.sizeMeters / plan.sampleSpacingMeters).rounded()) + 1
        guard x >= -1e-7, y >= -1e-7, x <= Double(side - 1) + 1e-7,
              y <= Double(side - 1) + 1e-7 else { return nil }
        let column = min(side - 2, max(0, Int(floor(x))))
        let row = min(side - 2, max(0, Int(floor(y))))
        let tx = Float(min(1, max(0, x - Double(column))))
        let ty = Float(min(1, max(0, y - Double(row))))
        let nw = row * side + column, ne = nw + 1, sw = nw + side, se = sw + 1
        let indices: SIMD3<Int>
        let weights: SIMD3<Float>
        if tx + ty <= 1 {
            indices = SIMD3(nw, ne, sw)
            weights = SIMD3(1 - tx - ty, tx, ty)
        } else {
            indices = SIMD3(ne, se, sw)
            weights = SIMD3(1 - ty, tx + ty - 1, 1 - tx)
        }
        let height = (0..<3).reduce(Float.zero) { $0 + mesh.positions[indices[$1]].y * weights[$1] }
        let normal = (0..<3).reduce(SIMD3<Float>.zero) { $0 + mesh.normals[indices[$1]] * weights[$1] }
        return Sample(elevation: height, normal: simd_normalize(normal), spacing: plan.sampleSpacingMeters)
    }
}

struct LMLunarTerrainMeshSnapshot: Sendable {
    /// Finest first. The owner selection matches the parent quad masks.
    let tiles: [LMLunarTerrainMeshTile]

    func sample(east: Double, north: Double, coarserThan spacing: Double = 0) -> LMLunarTerrainMeshTile.Sample? {
        for tile in tiles where tile.plan.sampleSpacingMeters > spacing {
            if let sample = tile.sample(east: east, north: north) { return sample }
        }
        return nil
    }
}
