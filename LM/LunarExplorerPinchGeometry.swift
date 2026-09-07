import simd

/// Geometry shared by gesture handling and numerical regression tests.
enum LunarExplorerPinchGeometry {
    struct Ray {
        let origin: SIMD3<Float>
        let direction: SIMD3<Float>
        init(origin: SIMD3<Float>, through point: SIMD3<Float>) {
            self.origin = origin
            direction = simd_normalize(point - origin)
        }
    }

    /// Exact intersection over the disk interior. The final 2% of squared
    /// radial clearance eases to the tangent, then releases along the limb.
    /// This preserves the fixed sphere depth and the complete zoom-out range.
    static func sphereDirection(ray: Ray, center: SIMD3<Float>, radius: Float,
                                releaseAtLimb: Bool) -> SIMD3<Float>? {
        let offset = center - ray.origin
        let distance = simd_dot(offset, ray.direction)
        guard distance > 0, radius > 0 else { return nil }
        let nearest = ray.origin + distance * ray.direction - center
        let clearance = radius * radius - simd_length_squared(nearest)
        if !releaseAtLimb && clearance < 0 { return nil }
        let band = radius * radius * 0.02
        let depth: Float
        if releaseAtLimb && clearance < band {
            let t = max(0, clearance / band)
            depth = sqrt(band) * t * t * (2.5 - 1.5 * t)
        } else { depth = sqrt(max(0, clearance)) }
        return simd_normalize(nearest - depth * ray.direction)
    }

    static func point(_ point: SIMD3<Float>, transformedBy matrix: simd_float4x4) -> SIMD3<Float> {
        let p = matrix * SIMD4(point, 1)
        return SIMD3(p.x, p.y, p.z) / p.w
    }

    static func direction(_ direction: SIMD3<Float>, transformedBy matrix: simd_float4x4) -> SIMD3<Float> {
        let p = matrix * SIMD4(direction, 0)
        return SIMD3(p.x, p.y, p.z)
    }

    /// Solve the two focus translations and distance along the original ray.
    static func panCorrection(point: SIMD3<Float>, north: SIMD3<Float>, east: SIMD3<Float>,
                              ray: Ray) -> SIMD2<Double>? {
        let basis = simd_float3x3(columns: (north, east, ray.direction))
        guard abs(basis.determinant) > 1e-12 else { return nil }
        let solution = basis.inverse * (point - ray.origin)
        guard solution.x.isFinite, solution.y.isFinite, solution.z > 0 else { return nil }
        return SIMD2(Double(solution.x), Double(solution.y))
    }

    static func intersectsBounds(origin: SIMD3<Float>, direction: SIMD3<Float>,
                                 minimum: SIMD3<Float>, maximum: SIMD3<Float>) -> Bool {
        var near: Float = 0, far = Float.infinity
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-12 {
                if origin[axis] < minimum[axis] || origin[axis] > maximum[axis] { return false }
            } else {
                let a = (minimum[axis] - origin[axis]) / direction[axis]
                let b = (maximum[axis] - origin[axis]) / direction[axis]
                near = max(near, min(a, b))
                far = min(far, max(a, b))
                if near > far { return false }
            }
        }
        return true
    }

    static func triangleDistance(origin: SIMD3<Float>, direction: SIMD3<Float>,
                                 a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) -> Float? {
        let e1 = b - a, e2 = c - a, p = simd_cross(direction, e2)
        let determinant = simd_dot(e1, p)
        guard abs(determinant) > 1e-9 else { return nil }
        let t = origin - a
        let u = simd_dot(t, p) / determinant
        guard u >= 0, u <= 1 else { return nil }
        let q = simd_cross(t, e1)
        let v = simd_dot(direction, q) / determinant
        guard v >= 0, u + v <= 1 else { return nil }
        let distance = simd_dot(e2, q) / determinant
        return distance > 0 ? distance : nil
    }
}
