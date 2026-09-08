#if DEBUG
import Foundation
import RealityKit
import simd

/// Assembly review cameras, in cabin coordinates. Does not alter local mounts.
@MainActor
enum LMCommanderStationAssemblyObserver {
    enum View: String { case exterior, front, side, cdr, lmp, lpd, rear, overhead, timers, contact, crewEye = "crew-eye", controls = "control-closeup", details = "detail-side", crossPointer = "cross-pointer" }
    static func selected(arguments: [String]) -> View? {
        guard !arguments.contains("--instrument-validation"),
              let flag = arguments.first(where: { $0.hasPrefix("--assembly-validation-view=") }) else { return nil }
        return View(rawValue: String(flag.dropFirst("--assembly-validation-view=".count)))
    }
    static func pose(for view: View) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        switch view {
        case .lpd:
            let optics = LMLandingPointDesignator()
            let center = LMLPDWindowCorner.allCases.reduce(SIMD3<Float>.zero) {
                $0 + optics.windowCorner($1, on: .inner)
            } / Float(LMLPDWindowCorner.allCases.count)
            return (optics.commanderEyeMeters, center)
        case .exterior: return ([9, 6, 9], [0, -1.6, 0])
        case .timers: return ([-0.245, 1.79, -0.27], [-0.245, 1.84, -0.91])
        case .contact: return ([-0.245, 1.72, -0.28], [-0.204, 1.70, -0.90])
        case .front: return ([-0.15, 1.60, 0.48], [-0.15, 1.30, -0.55])
        case .crossPointer: return (LMLandingPointDesignator().commanderEyeMeters, [-0.315, 1.703, -0.902])
        case .controls: return ([-0.32, 1.56, 0.04], [-0.30, 1.28, -0.72])
        case .details: return ([0.1, 1.56, 0.15], [-0.83, 0.95, 0.05])
        case .side: return ([-0.78, 1.57, 0.30], [-0.15, 1.30, -0.55])
        case .crewEye, .cdr: return (LMLandingPointDesignator().commanderEyeMeters, [-0.15, 1.43, -0.65])
        case .lmp: return ([0.5588, 1.78, -0.38], [0.20, 1.43, -0.70])
        case .rear: return ([0, 1.65, -0.10], [0, 1.25, 0.95])
        case .overhead: return ([0, 1.60, 0.20], [-0.25, 2.12, -0.20])
        }
    }
    static func frame(_ root: Entity, arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let view = selected(arguments: arguments) else { return }
        let pose = pose(for: view)
        let eye = pose.eye + LMCommanderStationGeometry.cabinFrameOffsetMeters
        let forward = simd_normalize(pose.target - pose.eye)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let inverse = simd_quatf(simd_float3x3(columns: (right, up, -forward))).inverse
        root.orientation = inverse
        root.position = inverse.act(-eye)
    }
}
#endif
