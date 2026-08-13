import Foundation
import simd
import LMCore

/// Maps LMCore SI state into RealityKit tabletop space.
///
/// LMCore body: +Z = NASA +X (DPS/up), +X = NASA +Y, +Y = NASA +Z.
/// RealityKit: +Y up, −Z forward, +X right.
struct LMWorldMapper: Equatable, Sendable {
    var highAltitudeMeters: Double
    var highVisualMeters: Double
    var nearAltitudeMeters: Double
    var nearVisualMeters: Double

    static let tabletop = LMWorldMapper(
        highAltitudeMeters: 48_814.0 * 0.3048,
        highVisualMeters: 1.0,
        nearAltitudeMeters: 200.0 * 0.3048,
        nearVisualMeters: 0.35
    )

    func visualAltitude(_ altitudeMeters: Double) -> Double {
        let altitude = max(0, altitudeMeters)
        if altitude <= nearAltitudeMeters {
            let span = max(nearAltitudeMeters, 1e-9)
            return altitude * (nearVisualMeters / span)
        }
        let remaining = max(highAltitudeMeters - nearAltitudeMeters, 1e-9)
        return nearVisualMeters + (altitude - nearAltitudeMeters) * (highVisualMeters / remaining)
    }

    func position(from si: LMVector3D) -> SIMD3<Float> {
        let horizontalScale = highVisualMeters / max(highAltitudeMeters, 1e-9)
        return SIMD3(
            Float(si.x * horizontalScale),
            Float(visualAltitude(si.z)),
            Float(-si.y * horizontalScale)
        )
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

    func pose(from state: LMVehicleStateSnapshot) -> (position: SIMD3<Float>, orientation: simd_quatf) {
        (position(from: state.positionMeters), orientation(from: state.attitude))
    }

    private func orthonormalized(_ matrix: simd_float3x3) -> simd_float3x3 {
        let x = simd_normalize(matrix.columns.0)
        let z = simd_normalize(simd_cross(x, matrix.columns.1))
        let y = simd_normalize(simd_cross(z, x))
        return simd_float3x3(columns: (x, y, z))
    }
}
