import LunarMap
import Foundation
import LMCore
import simd

/// Full-scale coordinate mapping for the first-person LM cockpit.
///
/// The cockpit remains fixed around the wearer. The lunar world receives the
/// inverse of the simulated vehicle pose, so translation and attitude are
/// presented without moving the visionOS camera or adding hidden stabilization.
struct LMCockpitWorldMapper: Equatable, Sendable {
    static let fullScale = LMCockpitWorldMapper()

    func realityPosition(from si: LMVector3D) -> SIMD3<Float> {
        SIMD3(Float(si.x), Float(si.z), Float(-si.y))
    }

    func vehicleMatrix(
        position: LMVector3D,
        attitude: LMQuaternion
    ) -> simd_float4x4 {
        var matrix = simd_float4x4(LMWorldMapper.attitudeOrientation(from: attitude))
        let translation = realityPosition(from: position)
        matrix.columns.3 = SIMD4(translation.x, translation.y, translation.z, 1)
        return matrix
    }

    func lunarWorldMatrix(
        position: LMVector3D,
        attitude: LMQuaternion,
        surfaceElevationMeters: Double = 0
    ) -> simd_float4x4 {
        var terrainDatum = matrix_identity_float4x4
        terrainDatum.columns.3.y = -Float(surfaceElevationMeters)
        return simd_inverse(vehicleMatrix(position: position, attitude: attitude)) * terrainDatum
    }

    func lunarWorldMatrix(
        from state: LMVehicleStateSnapshot,
        surfaceElevationMeters: Double = 0
    ) -> simd_float4x4 {
        lunarWorldMatrix(
            position: state.positionMeters,
            attitude: state.attitude,
            surfaceElevationMeters: surfaceElevationMeters
        )
    }
}
