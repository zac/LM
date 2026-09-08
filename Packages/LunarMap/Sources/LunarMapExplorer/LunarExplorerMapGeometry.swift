import LunarMap
import simd

/// Cartographic placement in the same east/north/up display frame as the globe.
enum LunarExplorerMapGeometry {
    static func direction(to coordinate: LMSelenographicCoordinate,
                          centeredOn center: LMSelenographicCoordinate) -> SIMD3<Float> {
        let system = LMSelenographicCoordinateSystem()
        let frame = system.localFrame(at: center)
        let fixed = simd_normalize(system.moonCenteredPosition(for: coordinate).vector)
        let local = frame.localDirection(fixed)
        return SIMD3(Float(local.y), Float(local.x), Float(local.z))
    }

    /// Conservative horizon test in the initial viewer's placement frame.
    /// Depth testing additionally occludes geometry from the current viewpoint.
    static func isVisible(direction: SIMD3<Float>, globePosition: SIMD3<Float>, radius: Float) -> Bool {
        let point = globePosition + direction * radius
        return simd_dot(direction, simd_normalize(-point)) > 0.12
    }
}
