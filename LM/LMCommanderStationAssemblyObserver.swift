#if DEBUG
import Foundation
import RealityKit
import simd

/// Assembly review cameras, in cabin coordinates. Does not alter local mounts.
@MainActor
enum LMCommanderStationAssemblyObserver {
    enum View: String { case front, side, cdr, lmp, rear, overhead, crewEye = "crew-eye" }
    static func selected(arguments: [String]) -> View? {
        guard !arguments.contains("--instrument-validation"),
              let flag = arguments.first(where: { $0.hasPrefix("--assembly-validation-view=") }) else { return nil }
        return View(rawValue: String(flag.dropFirst("--assembly-validation-view=".count)))
    }
    static func pose(for view: View) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        switch view {
        case .front: return ([-0.15, 1.60, 0.48], [-0.15, 1.30, -0.55])
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
