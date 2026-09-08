import LMCore
import RealityKit
import simd

/// Native LMKit ball basis: zero meridian +Z, positive latitude +X,
/// positive longitude toward -Y. GASTA outer/middle/inner axes become Z/-Y/X.
/// Uses the same site-local stable-frame reference as the current CDU path;
/// does not re-zero at PDI or invent an ORDEAL/reference selector.
enum LMImportedFDAIOrientation {
    static func ballOrientation(for attitude: LMQuaternion,
                                relativeTo reference: LMQuaternion = .identity) -> simd_quatf {
        let relative = FDAIOrientation.relativeAttitude(attitude, reference: reference)
        let cdu = LMIMUGimbalMap.cduRadians(from: relative)
        return simd_normalize(
            simd_quatf(angle: Float(-cdu.x), axis: SIMD3(0, 0, 1)) *
            simd_quatf(angle: Float(cdu.z), axis: SIMD3(0, 1, 0)) *
            simd_quatf(angle: Float(-cdu.y), axis: SIMD3(1, 0, 0))
        )
    }
}

@MainActor
final class LMImportedFDAI {
    let root: Entity
    let ball: Entity
    let fixed: Entity
    static let unboundNames = [
        "FDAI_RollBug_Pivot", "FDAI_Rate_Roll_Pivot", "FDAI_Rate_Pitch_Pivot",
        "FDAI_Rate_Yaw_Pivot", "FDAI_Error_Roll_Pivot", "FDAI_Error_Pitch_Pivot",
        "FDAI_Error_Yaw_Pivot"
    ]
    init(asset: Entity) throws {
        root = try LMImportedDSKY.unique("FDAI_Mount", in: asset)
        ball = try LMImportedDSKY.unique("FDAI_Ball_Pivot", in: root)
        fixed = try LMImportedDSKY.unique("FDAI_Fixed", in: root)
        for node in [ball, fixed] {
            guard node.parent === root else { throw LMImportedDSKY.ContractError.invalidParent(node.name) }
        }
        for name in Self.unboundNames {
            let node = try LMImportedDSKY.unique(name, in: root)
            guard node.parent === root else { throw LMImportedDSKY.ContractError.invalidParent(name) }
            // Hidden instead of a plausible but unauthoritative zero reading.
            node.isEnabled = false
        }
    }
    func apply(_ attitude: LMQuaternion) {
        ball.orientation = LMImportedFDAIOrientation.ballOrientation(for: attitude)
    }
}
