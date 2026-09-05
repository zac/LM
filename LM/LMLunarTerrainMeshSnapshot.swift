import simd

/// CPU copy of the exact vertices submitted to RealityKit. Parent morphs and
/// landing contact use the same NW/NE/SW, NE/SE/SW triangles as the renderer.
struct LMLunarTerrainMeshTile: Sendable {
    let plan: LMTerrainTilePlan
    let mesh: LMProgressiveTerrainMeshData
    // During arrival, these are the same endpoints and weight consumed by the
    // render mesh. Contact evaluates only its three vertices, without copying
    // every resident mesh on each frame.
    var startMesh: LMProgressiveTerrainMeshData? = nil
    var morphWeight: Float = 1

    func position(at index: Int) -> SIMD3<Float> {
        guard let startMesh, morphWeight < 1 else { return mesh.positions[index] }
        if morphWeight <= 0 { return startMesh.positions[index] }
        let a = startMesh.positions[index], b = mesh.positions[index]
        return SIMD3(a.x.addingProduct(b.x - a.x, morphWeight),
                     a.y.addingProduct(b.y - a.y, morphWeight),
                     a.z.addingProduct(b.z - a.z, morphWeight))
    }

    func normal(at index: Int) -> SIMD3<Float> {
        guard let startMesh, morphWeight < 1 else { return mesh.normals[index] }
        if morphWeight <= 0 { return startMesh.normals[index] }
        return startMesh.normals[index] + (mesh.normals[index] - startMesh.normals[index]) * morphWeight
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
