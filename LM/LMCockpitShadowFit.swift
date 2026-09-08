import simd

/// A local cockpit/lander shadow map. Distant terrain is intentionally outside
/// its XY footprint; this does not change sunlight or simulation illumination.
struct LMCockpitShadowFit {
    struct GroundPlane {
        var point: SIMD3<Float>
        var normal: SIMD3<Float>
    }
    var origin: SIMD3<Float>
    var near: Float
    var far: Float
    /// Full width and height passed to RealityKit's orthographicScale.
    var span: Float

    static func fit(corners: [SIMD3<Float>], orientation: simd_quatf,
                    ground: GroundPlane?, downstreamDepth: Float = 45,
                    xyMargin: Float = 0.5, depthMargin: Float = 0.5,
                    maximumDepth: Float = 512) -> Self? {
        guard !corners.isEmpty, corners.allSatisfy(finite),
              finite(orientation.vector), simd_length(orientation.vector) > 0.00001,
              downstreamDepth.isFinite, downstreamDepth >= 0,
              xyMargin.isFinite, xyMargin >= 0,
              depthMargin.isFinite, depthMargin > 0.05 else { return nil }
        guard simd_length(orientation.vector).isFinite else { return nil }
        let q = simd_normalize(orientation)
        guard finite(q.vector) else { return nil }
        let lightCorners = corners.map { q.inverse.act($0) }
        var low = lightCorners[0], high = low
        for p in lightCorners { low = simd_min(low, p); high = simd_max(high, p) }
        if let ground {
            guard finite(ground.point), finite(ground.normal), simd_length(ground.normal) > 0.00001 else { return nil }
            let n = simd_normalize(ground.normal)
            let ray = q.act(SIMD3<Float>(0, 0, -1))
            let denominator = simd_dot(n, ray)
            guard denominator < -0.001 else { return nil }
            for p in corners {
                let t = simd_dot(ground.point - p, n) / denominator
                guard t.isFinite else { return nil }
                if t >= 0 { low.z = min(low.z, q.inverse.act(p + t * ray).z) }
            }
        } else {
            low.z -= downstreamDepth
        }
        let span = max(1, max(high.x - low.x, high.y - low.y) + 2 * xyMargin)
        let far = high.z - low.z + 2 * depthMargin
        guard span.isFinite, span <= 64, far.isFinite, far > 0.05, far <= maximumDepth else { return nil }
        let lightOrigin = SIMD3<Float>(low.x + (high.x - low.x) / 2, low.y + (high.y - low.y) / 2, high.z + depthMargin)
        let origin = q.act(lightOrigin)
        guard finite(origin) else { return nil }
        return Self(origin: origin, near: 0.05, far: far, span: span)
    }
    private static func finite(_ p: SIMD3<Float>) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
    private static func finite(_ p: SIMD4<Float>) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite && p.w.isFinite }
}
