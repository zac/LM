#if DEBUG
import Foundation
import RealityKit
import simd

/// Explicit visual-only travel review. Never sends simulation commands or
/// claims a recognized hand gesture; normal startup does not enable this.
@MainActor
enum LMACAValidation {
    static var pose: LMACANormalizedInput? {
        guard let flag = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--aca-visual-review=") }) else { return nil }
        switch String(flag.dropFirst("--aca-visual-review=".count)) {
        case "neutral": return .neutral
        case "positive": return .init(pitch: 1, yaw: 1, roll: 1)
        case "negative": return .init(pitch: -1, yaw: -1, roll: -1)
        default: return nil
        }
    }
    static func frame(_ root: Entity) {
        guard pose != nil else { return }
        let eye = SIMD3<Float>(-0.70, 1.27, 0.10)
        let target = SIMD3<Float>(-0.49, 1.04, -0.37)
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let inverse = simd_quatf(simd_float3x3(columns: (right, up, -forward))).inverse
        root.orientation = inverse
        root.position = inverse.act(-(eye + LMCommanderStationGeometry.cabinFrameOffsetMeters))
    }
}
#endif
