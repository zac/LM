import simd

/// Grid topology plus optional arrival endpoints. Use position(at:) and
/// normal(at:) for displayed values; mesh retains the original immutable grid.
/// Parent morphs and contact use the renderer's NW/NE/SW, NE/SE/SW triangles.
struct LMLunarTerrainMeshTile: Sendable {
    let plan: LMTerrainTilePlan
    let mesh: LMProgressiveTerrainMeshData
    // During arrival, these are the same endpoints and weight consumed by the
    // render mesh. Contact evaluates only its three vertices, without copying
    // every resident mesh on each frame.
    struct Arrival: Sendable {
        // Exactly the GPU endpoint layout: normal.xyz and elevation.w.
        let start: [SIMD4<Float>]
        let end: [SIMD4<Float>]
    }
    var arrival: Arrival? = nil
    var morphWeight: Float = 1

    func position(at index: Int) -> SIMD3<Float> {
        var position = mesh.positions[index]
        guard let arrival else { return position }
        let a = arrival.start[index].w, b = arrival.end[index].w
        position.y = morphWeight <= 0 ? a : (morphWeight >= 1 ? b : a.addingProduct(b - a, morphWeight))
        return position
    }

    func normal(at index: Int) -> SIMD3<Float> {
        guard let arrival else { return mesh.normals[index] }
        let a = SIMD3(arrival.start[index].x, arrival.start[index].y, arrival.start[index].z)
        let b = SIMD3(arrival.end[index].x, arrival.end[index].y, arrival.end[index].z)
        return morphWeight <= 0 ? a : (morphWeight >= 1 ? b : a + (b - a) * morphWeight)
    }

    struct Sample: Sendable {
        let elevation: Float
        let normal: SIMD3<Float>
        let spacing: Double
    }

    func sample(east: Double, north: Double, normalizeNormal: Bool = true) -> Sample? {
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
        let height = (0..<3).reduce(Float.zero) { $0 + position(at: indices[$1]).y * weights[$1] }
        let interpolated = (0..<3).reduce(SIMD3<Float>.zero) { $0 + self.normal(at: indices[$1]) * weights[$1] }
        return Sample(elevation: height, normal: normalizeNormal ? simd_normalize(interpolated) : interpolated, spacing: plan.sampleSpacingMeters)
    }
}

struct LMLunarTerrainMeshSnapshot: Sendable {
    /// Finest first. The owner selection matches the parent quad masks.
    let tiles: [LMLunarTerrainMeshTile]

    struct RayHit: Sendable {
        let position: SIMD3<Float>
        let distance: Float
        let plan: LMTerrainTilePlan
    }

    /// Inspection rays use only submitted triangles, including ownership holes.
    /// Unlike a height query, this can detect a distant parent occluding the focus.
    func raycast(origin: SIMD3<Float>, direction: SIMD3<Float>) -> RayHit? {
        let direction = simd_normalize(direction)
        var closest: RayHit?
        for tile in tiles {
            let offset = SIMD3(Float(tile.plan.centerNorthMeters), 0, Float(-tile.plan.centerEastMeters))
            let localOrigin = origin - offset
            let indices = tile.mesh.indices
            for index in stride(from: 0, to: indices.count, by: 3) {
                let a = tile.position(at: Int(indices[index]))
                let edge1 = tile.position(at: Int(indices[index + 1])) - a
                let edge2 = tile.position(at: Int(indices[index + 2])) - a
                let p = simd_cross(direction, edge2)
                let determinant = simd_dot(edge1, p)
                guard abs(determinant) > 1e-9 else { continue }
                let t = localOrigin - a
                let u = simd_dot(t, p) / determinant
                guard u >= 0, u <= 1 else { continue }
                let q = simd_cross(t, edge1)
                let v = simd_dot(direction, q) / determinant
                guard v >= 0, u + v <= 1 else { continue }
                let distance = simd_dot(edge2, q) / determinant
                guard distance > 0, distance < (closest?.distance ?? .infinity) else { continue }
                closest = RayHit(position: origin + direction * distance, distance: distance, plan: tile.plan)
            }
        }
        return closest
    }

    func sample(east: Double, north: Double, coarserThan spacing: Double = 0, normalizeNormal: Bool = true) -> LMLunarTerrainMeshTile.Sample? {
        for tile in tiles where tile.plan.sampleSpacingMeters > spacing {
            if let sample = tile.sample(east: east, north: north, normalizeNormal: normalizeNormal) { return sample }
        }
        return nil
    }
}
