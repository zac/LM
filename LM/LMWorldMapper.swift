import Foundation
import simd
import LMCore

/// Maps LMCore SI state into RealityKit tabletop space.
///
/// LMCore body: +Z = NASA +X (DPS/up), +X = NASA +Y, +Y = NASA +Z.
/// RealityKit: +Y up, −Z forward, +X right.
///
/// The pad is a landing theater, not a map. The kinematic LM stays over the
/// pad (altitude and attitude) until range is inside the last few kilometers.
/// The range bead is the map for the rest of the descent, including overshoot
/// past the site. PROG 64 is not high gate on this trajectory, so it must not
/// hide the bead or slam the LM onto the pad rim.
struct LMWorldMapper: Equatable, Sendable {
    var highAltitudeMeters: Double
    var highVisualMeters: Double
    var nearAltitudeMeters: Double
    var nearVisualMeters: Double
    var pdiRangeMeters: Double
    var stripLengthMeters: Double
    var padRadiusMeters: Double

    static let tabletop = LMWorldMapper(
        highAltitudeMeters: 48_814.0 * 0.3048,
        highVisualMeters: 1.0,
        nearAltitudeMeters: 200.0 * 0.3048,
        nearVisualMeters: 0.35,
        pdiRangeMeters: Luminary99LandingPadLoad.pdiGroundRangeMeters,
        stripLengthMeters: 0.9,
        padRadiusMeters: 0.45
    )

    /// Horizontal site-relative motion fits the pad inside this radius.
    var theaterRangeMeters: Double {
        highAltitudeMeters * padRadiusMeters / max(highVisualMeters, 1e-9)
    }

    func showsSiteRelativeHorizontal(rangeMeters: Double) -> Bool {
        rangeMeters <= theaterRangeMeters
    }

    func visualAltitude(_ altitudeMeters: Double) -> Double {
        let altitude = max(0, altitudeMeters)
        if altitude <= nearAltitudeMeters {
            let span = max(nearAltitudeMeters, 1e-9)
            return altitude * (nearVisualMeters / span)
        }
        let remaining = max(highAltitudeMeters - nearAltitudeMeters, 1e-9)
        return nearVisualMeters + (altitude - nearAltitudeMeters) * (highVisualMeters / remaining)
    }

    func position(from si: LMVector3D, program: Int? = nil) -> SIMD3<Float> {
        _ = program
        return position(from: si, rangeMeters: hypot(si.x, si.y))
    }

    func position(from si: LMVector3D, rangeMeters: Double) -> SIMD3<Float> {
        let altitude = Float(visualAltitude(si.z))
        guard showsSiteRelativeHorizontal(rangeMeters: rangeMeters) else {
            return SIMD3(0, altitude, 0)
        }
        let scale = highVisualMeters / max(highAltitudeMeters, 1e-9)
        let limit = padRadiusMeters
        return SIMD3(
            Float(clamped(si.x * scale, limit: limit)),
            altitude,
            Float(clamped(-si.y * scale, limit: limit))
        )
    }

    /// Site at the pad (z = 0). PDI is the far end (−Z). East past the site
    /// continues toward the viewer so overshoot stays on the ribbon.
    func stripBeadOffset(rangeMeters: Double) -> SIMD3<Float> {
        stripBeadOffset(downrangeMeters: -rangeMeters)
    }

    func stripBeadOffset(downrangeMeters: Double) -> SIMD3<Float> {
        let pdi = max(pdiRangeMeters, 1e-9)
        let fraction = min(max(-downrangeMeters / pdi, -0.5), 1.05)
        return SIMD3(0, 0.024, Float(-fraction * stripLengthMeters))
    }

    func direction(from si: LMVector3D) -> SIMD3<Float> {
        Self.attitudeDirection(from: si)
    }

    func orientation(from attitude: LMQuaternion) -> simd_quatf {
        Self.attitudeOrientation(from: attitude)
    }

    /// Shared simulation-to-RealityKit convention used by the tabletop and
    /// full-scale cockpit worlds: +X north, +Y up, and -Z east.
    static func attitudeDirection(from si: LMVector3D) -> SIMD3<Float> {
        simd_normalize(SIMD3(Float(si.x), Float(si.z), Float(-si.y)))
    }

    static func attitudeOrientation(from attitude: LMQuaternion) -> simd_quatf {
        let columnX = attitudeDirection(from: attitude.rotated(LMVector3D(x: 1)))
        let columnY = attitudeDirection(from: attitude.rotated(LMVector3D(z: 1)))
        let columnZ = attitudeDirection(from: attitude.rotated(LMVector3D(y: -1)))
        var matrix = simd_float3x3(columns: (columnX, columnY, columnZ))
        matrix = sharedOrthonormalized(matrix)
        return simd_quatf(matrix)
    }

    static func sharedOrthonormalized(_ matrix: simd_float3x3) -> simd_float3x3 {
        let x = simd_normalize(matrix.columns.0)
        let z = simd_normalize(simd_cross(x, matrix.columns.1))
        let y = simd_normalize(simd_cross(z, x))
        return simd_float3x3(columns: (x, y, z))
    }

    func pose(from state: LMVehicleStateSnapshot, program: Int? = nil) -> (position: SIMD3<Float>, orientation: simd_quatf) {
        _ = program
        let altitude = Float(visualAltitude(state.altitudeMeters))
        guard showsSiteRelativeHorizontal(rangeMeters: state.groundRangeMeters) else {
            return (SIMD3(0, altitude, 0), orientation(from: state.attitude))
        }
        let scale = highVisualMeters / max(highAltitudeMeters, 1e-9)
        let limit = padRadiusMeters
        let si = state.positionMeters
        return (
            SIMD3(
                Float(clamped(si.x * scale, limit: limit)),
                altitude,
                Float(clamped(-si.y * scale, limit: limit))
            ),
            orientation(from: state.attitude)
        )
    }

    private func clamped(_ value: Double, limit: Double) -> Double {
        min(max(value, -limit), limit)
    }

}
