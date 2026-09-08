import Foundation
import RealityKit
import simd

@main struct MeasureACA {
    @MainActor static func main() throws {
        let asset = try Entity.load(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let root = asset.findEntity(named: "ACA_Mount")!
        let roll = root.findEntity(named: "ACA_Roll")!
        let yaw = root.findEntity(named: "ACA_Yaw")!
        let pitch = root.findEntity(named: "ACA_Pitch")!
        let neutral = root.visualBounds(relativeTo: root)
        var lower = SIMD3<Float>(repeating: .infinity)
        var upper = SIMD3<Float>(repeating: -.infinity)
        let angle = Float.pi * 11 / 180
        // All combinations at 2.75 degree spacing, including center and stops.
        for r in -4...4 { for y in -4...4 { for p in -4...4 {
            roll.orientation = simd_quatf(angle: -Float(r) / 4 * angle, axis: [0,0,1])
            yaw.orientation = simd_quatf(angle: Float(y) / 4 * angle, axis: [0,1,0])
            pitch.orientation = simd_quatf(angle: Float(p) / 4 * angle, axis: [1,0,0])
            let bounds = root.visualBounds(relativeTo: root)
            lower = simd_min(lower, bounds.min); upper = simd_max(upper, bounds.max)
        } } }
        func array(_ v: SIMD3<Float>) -> [Float] { [v.x,v.y,v.z] }
        let registration = SIMD3<Float>(-0.49, 0.92 - 0.0125, -0.37)
        let report: [String: Any] = [
            "method": "Native macOS RealityKit visualBounds; sampled AABB, not collision or continuous swept-volume proof",
            "samples": 729, "travel_degrees": 11,
            "neutral_asset_min": array(neutral.min), "neutral_asset_max": array(neutral.max),
            "sampled_asset_min": array(lower), "sampled_asset_max": array(upper),
            "sampled_cabin_min": array(lower + registration), "sampled_cabin_max": array(upper + registration),
            "root_cabin_registration": array(registration)
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
