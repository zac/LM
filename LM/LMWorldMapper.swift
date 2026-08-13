import Foundation
import simd
import LMCore

/// Maps LMCore SI state into RealityKit tabletop space.
///
/// LMCore body: +Z = NASA +X (DPS/up), +X = NASA +Y, +Y = NASA +Z.
/// RealityKit: +Y up, −Z forward, +X right.
///
/// The pad is a landing theater, not a map. Until PROG 64 the LM stays over
/// the pad (altitude and attitude only). P63 range-to-go is a separate strip.
struct LMWorldMapper: Equatable, Sendable {
    var highAltitudeMeters: Double
    var highVisualMeters: Double
    var nearAltitudeMeters: Double
    var nearVisualMeters: Double
    var pdiRangeMeters: Double
    var stripLengthMeters: Double
    var padRadiusMeters: Double

    /// High gate / approach. Horizontal site-relative motion is shown from here.
    static let landingProgram = 64

    static let tabletop = LMWorldMapper(
        highAltitudeMeters: 48_814.0 * 0.3048,
        highVisualMeters: 1.0,
        nearAltitudeMeters: 200.0 * 0.3048,
        nearVisualMeters: 0.35,
        pdiRangeMeters: Luminary99LandingPadLoad.pdiGroundRangeMeters,
        stripLengthMeters: 0.9,
        padRadiusMeters: 0.45
    )

    func showsSiteRelativeHorizontal(program: Int?) -> Bool {
        (program ?? 0) >= Self.landingProgram
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
        let altitude = Float(visualAltitude(si.z))
        guard showsSiteRelativeHorizontal(program: program) else {
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

    /// Site at the pad (z = 0). PDI is the far end, further into the scene (−Z).
    func stripBeadOffset(rangeMeters: Double) -> SIMD3<Float> {
        let pdi = max(pdiRangeMeters, 1e-9)
        let fraction = min(max(rangeMeters / pdi, 0), 1)
        return SIMD3(0, 0.024, Float(-fraction * stripLengthMeters))
    }

    func direction(from si: LMVector3D) -> SIMD3<Float> {
        simd_normalize(SIMD3(Float(si.x), Float(si.z), Float(-si.y)))
    }

    func orientation(from attitude: LMQuaternion) -> simd_quatf {
        let columnX = direction(from: attitude.rotated(LMVector3D(x: 1)))
        let columnY = direction(from: attitude.rotated(LMVector3D(z: 1)))
        let columnZ = direction(from: attitude.rotated(LMVector3D(y: -1)))
        var matrix = simd_float3x3(columns: (columnX, columnY, columnZ))
        matrix = orthonormalized(matrix)
        return simd_quatf(matrix)
    }

    func pose(from state: LMVehicleStateSnapshot, program: Int? = nil) -> (position: SIMD3<Float>, orientation: simd_quatf) {
        (position(from: state.positionMeters, program: program), orientation(from: state.attitude))
    }

    private func clamped(_ value: Double, limit: Double) -> Double {
        min(max(value, -limit), limit)
    }

    private func orthonormalized(_ matrix: simd_float3x3) -> simd_float3x3 {
        let x = simd_normalize(matrix.columns.0)
        let z = simd_normalize(simd_cross(x, matrix.columns.1))
        let y = simd_normalize(simd_cross(z, x))
        return simd_float3x3(columns: (x, y, z))
    }
}
