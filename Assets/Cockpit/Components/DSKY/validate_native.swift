// macOS RealityKit smoke check, not a Vision Pro interaction test.
// xcrun swiftc -parse-as-library validate_native.swift -o scratch/validate-native
// scratch/validate-native /absolute/path/to/DSKY.usdz
import Foundation
import RealityKit

@main struct ValidateNative {
    @MainActor static func main() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let scene = try await Entity(contentsOf: url)
        guard let root = scene.findEntity(named: "DSKY_Mount") else {
            fatalError("Missing DSKY_Mount")
        }
        let names = ["VERB", "NOUN", "PLUS", "7", "8", "9", "CLR", "MINUS", "4", "5", "6", "PRO", "0", "1", "2", "3", "KEY_REL", "ENTR", "RSET"]
        for suffix in names {
            guard let key = root.findEntity(named: "DSKY_Key_" + suffix), key.parent === root else {
                fatalError("Missing or misparented key " + suffix)
            }
            precondition(!key.children.isEmpty)
        }
        precondition(root.findEntity(named: "DSKY_Face")?.parent === root)
        precondition(root.findEntity(named: "DSKY_Display_Mount")?.parent === root)
        precondition(simd_length(root.scale - SIMD3<Float>(repeating: 1)) < 0.00001)
        let bindingsURL = url.deletingLastPathComponent().appendingPathComponent("bindings.json")
        let bindings = try JSONSerialization.jsonObject(with: Data(contentsOf: bindingsURL)) as! [String: Any]
        for entry in bindings["keys"] as! [[String: Any]] {
            let key = root.findEntity(named: entry["name"] as! String)!
            let v = entry["neutral_usd_m"] as! [Double]
            precondition(simd_length(key.position(relativeTo: root) - SIMD3<Float>(Float(v[0]), Float(v[1]), Float(v[2]))) < 0.000001)
        }
        let result: [String: Any] = ["file":url.lastPathComponent,"native_load":"PASS","direct_keys":19,
          "positions_and_scale":"PASS", "platform":"macOS RealityKit", "hover_pinch":"NOT TESTED", "RCP_GUI":"NOT TESTED"]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
    }
}
