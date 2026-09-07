import simd

/// Perspective sphere silhouette on the room-facing XY portal plane.
/// Clip the aperture to this silhouette while the disk first outgrows the frame;
/// a full rectangular aperture would expose the world's black clear color.
enum LunarExplorerPortalGeometry {
    static let width: Float = 1.6
    static let height: Float = 1.1
    static let cornerRadius: Float = 0.08
    /// Fixed Simulator camera calibration shared by gestures and frame projection.
    static let simulatorEyePosition = SIMD3<Float>(0, 1.60, 0)

    struct Projection {
        let center: SIMD2<Double>
        let major: SIMD2<Double>
        let minor: SIMD2<Double>
        let a: Double
        let b: Double
        var height: Double { 2 * sqrt(pow(a * major.y, 2) + pow(b * minor.y, 2)) }
        func contains(_ point: SIMD2<Float>) -> Bool {
            let delta = SIMD2<Double>(point) - center
            return pow(simd_dot(delta, major) / a, 2) + pow(simd_dot(delta, minor) / b, 2) <= 1
        }
        /// First contact with the rounded frame, including off-axis projection.
        var frameOverflow: Double {
            outline.map { point in
                let q = simd_abs(point) - SIMD2(LunarExplorerPortalGeometry.width / 2,
                    LunarExplorerPortalGeometry.height / 2) + SIMD2(repeating: LunarExplorerPortalGeometry.cornerRadius)
                return Double(simd_length(simd_max(q, .zero)) + min(max(q.x, q.y), 0)
                    - LunarExplorerPortalGeometry.cornerRadius)
            }.max() ?? -.infinity
        }
        var outline: [SIMD2<Float>] {
            (0..<192).map { index in
                let angle = Double(index) * 2 * .pi / 192
                return SIMD2<Float>(center + major * (a * cos(angle)) + minor * (b * sin(angle)))
            }
        }
    }

    static func project(center: SIMD3<Float>, radius: Float, eye: SIMD3<Float>,
                        planeCenter: SIMD3<Float>) -> Projection? {
        let c = SIMD3<Double>(center - eye), r = Double(radius)
        let depth = Double(eye.z - planeCenter.z)
        let horizontal = SIMD2(c.x, c.y)
        let base = c.z * c.z - r * r
        let k = simd_length_squared(c) - r * r
        guard depth > 0, c.z < 0, r > 0, base > 0, k > 0 else { return nil }
        let major = simd_length_squared(horizontal) > 1e-16
            ? simd_normalize(horizontal) : SIMD2<Double>(1, 0)
        let projectedCenter = horizontal * (-depth * c.z / base)
            + SIMD2<Double>(SIMD2(eye.x - planeCenter.x, eye.y - planeCenter.y))
        return Projection(center: projectedCenter, major: major, minor: SIMD2(-major.y, major.x),
                          a: depth * r * sqrt(k) / base, b: depth * r / sqrt(base))
    }

    static func rectangle(width: Float = LunarExplorerPortalGeometry.width,
                          height: Float = LunarExplorerPortalGeometry.height,
                          radius: Float = LunarExplorerPortalGeometry.cornerRadius) -> [SIMD2<Float>] {
        let centers = [SIMD2(width / 2 - radius, height / 2 - radius),
                       SIMD2(-width / 2 + radius, height / 2 - radius),
                       SIMD2(-width / 2 + radius, -height / 2 + radius),
                       SIMD2(width / 2 - radius, -height / 2 + radius)]
        return (0..<64).map { index in
            let quadrant = index / 16, step = index % 16
            let angle = Float(quadrant) * .pi / 2 + Float(step) / 15 * .pi / 2
            return centers[quadrant] + radius * SIMD2(cos(angle), sin(angle))
        }
    }

    static let frameOutline = rectangle()

    static func aperture(_ projection: Projection) -> [SIMD2<Float>] {
        if frameOutline.allSatisfy(projection.contains) { return frameOutline }
        var polygon = projection.outline
        func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
        for index in frameOutline.indices {
            let a = frameOutline[index], b = frameOutline[(index + 1) % frameOutline.count]
            let edge = b - a
            let input = polygon
            polygon.removeAll(keepingCapacity: true)
            guard var previous = input.last else { return [] }
            var previousDistance = cross(edge, previous - a)
            for point in input {
                let distance = cross(edge, point - a)
                if (distance >= 0) != (previousDistance >= 0) {
                    polygon.append(previous + (point - previous) * (previousDistance / (previousDistance - distance)))
                }
                if distance >= 0 { polygon.append(point) }
                previous = point; previousDistance = distance
            }
        }
        return polygon
    }
}
