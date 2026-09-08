import Foundation
import RealityKit
import simd
@main struct Validate {
 @MainActor static func main() async throws {
  let dir=URL(fileURLWithPath:CommandLine.arguments[1]);let e=try await Entity(contentsOf:dir.appendingPathComponent("BreakerBanks.usdz"));guard let root=e.findEntity(named:"BreakerBanks") else {fatalError("No root")}
  precondition(simd_length(root.position)<1e-6 && simd_length(root.scale-SIMD3<Float>(repeating:1))<1e-6 && abs(root.orientation.real-1)<1e-6)
  let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:dir.appendingPathComponent("interface.json"))) as! [String:Any];let slots=manifest["slots"] as! [[String:Any]]
  func pose(_ p:[String:Any])->simd_float4x4 {let t=p["translation_m"] as! [Double],q=p["quaternion_xyzw"] as! [Double];var m=simd_float4x4(simd_quatf(ix:Float(q[0]),iy:Float(q[1]),iz:Float(q[2]),r:Float(q[3])));m.columns.3=SIMD4<Float>(Float(t[0]),Float(t[1]),Float(t[2]),1);return m}
  var rows=0
  for s in slots {let id=s["id"] as! String;guard let n=root.findEntity(named:id) else {fatalError("Missing slot")};let want=pose(s["panel_pose"] as! [String:Any])*pose(s["slot_pose"] as! [String:Any]);let actual=n.transformMatrix(relativeTo:root)
   for c in 0..<4 {precondition(simd_length(actual[c]-want[c])<1e-5)};rows+=1
  }
  func all(_ n:Entity)->[Entity] {[n]+n.children.flatMap{all($0)}}
  let nodes=all(root);let models=nodes.filter{$0.components[ModelComponent.self] != nil};precondition(models.count==(manifest["budget"] as! [String:Any])["mesh_count"] as! Int)
  precondition(nodes.allSatisfy{$0.components[CollisionComponent.self] == nil && $0.components[InputTargetComponent.self] == nil})
  let first=root.findEntity(named:slots[0]["id"] as! String)!;let last=root.findEntity(named:slots.last!["id"] as! String)!;let old=last.transformMatrix(relativeTo:root);first.position.z += 0.01;precondition(last.transformMatrix(relativeTo:root)==old)
  let out:[String:Any] = ["status":"PASS","platform":"macOS RealityKit","exact_slot_full_transform_checks":rows,"model_count":models.count,"optional_rows_independent":true,"no_collision_or_input_components":true,"live_bindings":false,"VisionPro":"NOT TESTED"]
  print(String(decoding:try JSONSerialization.data(withJSONObject:out,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
 }
}
