import Foundation
import RealityKit
import simd
@main struct Validate {
 @MainActor static func main() async throws {
  let dir=URL(fileURLWithPath:CommandLine.arguments[1]);let e=try await Entity(contentsOf:dir.appendingPathComponent("CautionWarning.usdz"));let root=e.findEntity(named:"CautionWarning")!
  let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:dir.appendingPathComponent("interface.json"))) as! [String:Any];let slots=manifest["slots"] as! [[String:Any]],lamps=manifest["lamps"] as! [[String:Any]]
  precondition(root.position == .zero && simd_length(root.scale-SIMD3<Float>(repeating:1))<1e-6 && abs(root.orientation.real-1)<1e-6)
  func pose(_ p:[String:Any])->simd_float4x4 {let t=p["translation_m"] as! [Double],q=p["quaternion_xyzw"] as! [Double];var m=simd_float4x4(simd_quatf(ix:Float(q[0]),iy:Float(q[1]),iz:Float(q[2]),r:Float(q[3])));m.columns.3=SIMD4(Float(t[0]),Float(t[1]),Float(t[2]),1);return m}
  for s in slots {let n=root.findEntity(named:s["id"] as! String)!;let actual=n.transformMatrix(relativeTo:root),expected=pose(s["panel_pose"] as! [String:Any])*pose(s["slot_pose"] as! [String:Any]);for i in 0..<4 {precondition(simd_length(actual[i]-expected[i])<1e-5)}}
  for l in lamps {let lens=root.findEntity(named:"Lens_"+(l["id"] as! String));precondition(lens?.components[ModelComponent.self] != nil)}
  precondition(lamps.count==40 && (manifest["named_lamps"] as! Int)==31 && (manifest["blank_cells"] as! Int)==9)
  let a=root.findEntity(named:lamps[0]["id"] as! String)!, b=root.findEntity(named:lamps.last!["id"] as! String)!;let fixed=b.transformMatrix(relativeTo:root);a.position.z += 0.001;precondition(b.transformMatrix(relativeTo:root)==fixed)
  func all(_ n:Entity)->[Entity]{[n]+n.children.flatMap{all($0)}}
  precondition(all(root).allSatisfy{$0.components[CollisionComponent.self] == nil && $0.components[InputTargetComponent.self] == nil});precondition(root.findEntity(named:"MasterAlarmReference")==nil)
  let specimen=try await Entity(contentsOf:dir.appendingPathComponent("MasterAlarmReference.usdz"));precondition(specimen.findEntity(named:"MasterAlarm_Button") != nil && specimen.findEntity(named:"MasterAlarm_Lens")?.components[ModelComponent.self] != nil)
  let output:[String:Any] = ["status":"PASS","platform":"macOS RealityKit","full_slot_matrices":slots.count,"individual_lenses":lamps.count,"named_lamps":31,"blank_cells":9,"independent_cells":true,"master_reference_loaded_separately":true,"live_bindings":false,"VisionPro":"NOT TESTED"]
  print(String(decoding:try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
 }
}
