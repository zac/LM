// Read-only macOS RealityKit load/hierarchy/transform smoke test; no app integration.
import Foundation
import RealityKit
import CryptoKit
@main struct ValidateFDAI {
 @MainActor static func main() async throws {
  let url=URL(fileURLWithPath:CommandLine.arguments[1]); let start=Date()
  let scene=try await Entity(contentsOf:url)
  guard let root=scene.findEntity(named:"FDAI_Mount"),let fixed=root.findEntity(named:"FDAI_Fixed") else {fatalError("Missing root")}
  let fixedTransform=fixed.transform
  let names=["FDAI_Ball_Pivot","FDAI_RollBug_Pivot"]+["Rate","Error"].flatMap { k in ["Roll","Pitch","Yaw"].map { "FDAI_\(k)_\($0)_Pivot" } }
  for name in names {
   guard let p=root.findEntity(named:name),p.parent === root else {fatalError("Missing pivot \(name)")}
   precondition(!p.children.isEmpty)
   let original=p.transform;p.orientation=simd_quatf(angle:.pi/8,axis:SIMD3<Float>(0,0,1))
   precondition(fixed.transform==fixedTransform);p.transform=original
  }
  precondition(simd_length(root.scale-SIMD3<Float>(repeating:1))<0.00001)
  precondition(simd_length(root.position)<0.00001)
  precondition(abs(root.orientation.real-1)<0.00001)
  let result:[String:Any] = ["sha256":SHA256.hash(data:try Data(contentsOf:url)).map { String(format:"%02x",$0) }.joined(),"native_load":"PASS","direct_moving_groups":names.count,"fixed_transform_under_motion":"PASS","load_and_checks_seconds":Date().timeIntervalSince(start),"platform":"macOS RealityKit","renderer_appearance":"NOT TESTED","Vision_Pro":"NOT TESTED","live_bindings":"NOT TESTED"]
  print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
 }
}
