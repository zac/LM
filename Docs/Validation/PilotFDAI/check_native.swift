// Read-only macOS resource check. App integration tests remain coordinator-owned.
import Foundation
import RealityKit
import simd

@main struct PilotFDAIResourceCheck {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let first = try Entity.load(contentsOf: url)
        let second = try Entity.load(contentsOf: url)
        func required(_ name: String, in parent: Entity) -> Entity {
            guard let entity = parent.findEntity(named: name) else { fatalError("Missing \(name)") }
            return entity
        }
        let a = required("FDAI_Mount", in: first), b = required("FDAI_Mount", in: second)
        let ballA = required("FDAI_Ball_Pivot", in: a), ballB = required("FDAI_Ball_Pivot", in: b)
        let fixedB = required("FDAI_Fixed", in: b)
        let fixedTransform = fixedB.transform
        precondition(a !== b && ballA !== ballB)
        for root in [a, b] {
            for name in ["FDAI_RollBug_Pivot"] + ["Rate", "Error"].flatMap({ kind in
                ["Roll", "Pitch", "Yaw"].map { "FDAI_\(kind)_\($0)_Pivot" }
            }) { required(name, in: root).isEnabled = false }
        }
        let bounds = b.visualBounds(relativeTo: b)
        precondition(bounds.min.x >= -0.075 && bounds.max.x <= 0.075 && bounds.min.y >= -0.075 && bounds.max.y <= 0.075)
        let untouchedA = ballA.transform
        ballB.orientation = simd_quatf(angle: .pi / 6, axis: [0, 1, 0])
        precondition(ballA.transform == untouchedA && fixedB.transform == fixedTransform)
        let result: [String: Any] = [
            "platform": "macOS RealityKit", "two_independent_loads": true,
            "pilot_motion_leaves_commander_unchanged": true, "fixed_housing_unchanged": true,
            "visual_bounds_min_m": [bounds.min.x, bounds.min.y, bounds.min.z],
            "visual_bounds_max_m": [bounds.max.x, bounds.max.y, bounds.max.z],
            "fits_150mm_xy_reservation": true,
            "app_tests": "not run here; coordinator owns simulator", "rendered_camera_acceptance": "pending"
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
