import Foundation
import RealityKit
import simd
@main struct Validate {
 @MainActor static func main() async throws {
  let dir=URL(fileURLWithPath:CommandLine.arguments[1]);let container=try await Entity(contentsOf:dir.appendingPathComponent("LowerConsole.usdz"));let root=container.findEntity(named:"LowerConsole")!
  let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:dir.appendingPathComponent("interface.json"))) as! [String:Any]
  func all(_ n:Entity)->[Entity]{[n]+n.children.flatMap{all($0)}}
  func resolve(_ path:String,in root:Entity)->Entity {let parts=path.split(separator:"/").map(String.init);precondition(parts.first==root.name);var e=root;for p in parts.dropFirst(){let children=e.children.filter{$0.name==p};precondition(children.count==1,"Exact path: \(path)");e=children.first!};return e}
  func pose(_ p:[String:Any])->simd_float4x4 {let t=p["position_m"] as! [Double],q=p["rotation_quaternion_xyzw"] as! [Double],s=p["scale"] as! [Double];var m=simd_float4x4(simd_quatf(ix:Float(q[0]),iy:Float(q[1]),iz:Float(q[2]),r:Float(q[3])));for i in 0..<3 {m[i] *= Float(s[i])};m.columns.3=SIMD4(Float(t[0]),Float(t[1]),Float(t[2]),1);return m}
  func equal(_ a:simd_float4x4,_ b:simd_float4x4){for i in 0..<4 {precondition(simd_length(a[i]-b[i])<0.00001)}}
  equal(root.transform.matrix,matrix_identity_float4x4)
  let models=all(root).filter{$0.components[ModelComponent.self] != nil};let budget=manifest["budget"] as! [String:Int];precondition(models.count==budget["meshes"]!)
  let groups=manifest["groups"] as! [[String:Any]];var grouped:Set<ObjectIdentifier>=[]
  for group in groups {let e=resolve(group["path"] as! String,in:root);for m in all(e) where m.components[ModelComponent.self] != nil {precondition(grouped.insert(ObjectIdentifier(m)).inserted)}}
  precondition(grouped.count==models.count);precondition(all(root).allSatisfy{$0.components[CollisionComponent.self]==nil && $0.components[InputTargetComponent.self]==nil})
  var peers:[String:Entity]=[:];let entries=(manifest["suppressions"] as! [[String:Any]])+(manifest["protected_mounts"] as! [[String:Any]])
  for entry in entries {let component=entry["component"] as! String
   if peers[component]==nil {let e=try await Entity(contentsOf:dir.deletingLastPathComponent().appendingPathComponent(component+"/"+component+".usdz"));peers[component]=e.findEntity(named:component)!}
   let peer=peers[component]!,node=resolve(entry["path"] as! String,in:peer);equal(node.transformMatrix(relativeTo:peer),pose(entry["pose"] as! [String:Any]))
  }
  let bounds=root.visualBounds(relativeTo:root);let expected=manifest["native_conservative_bounds_m"] as! [String:[Double]];for i in 0..<3 {precondition(abs(bounds.min[i]-Float(expected["min"]![i]))<0.0001);precondition(abs(bounds.max[i]-Float(expected["max"]![i]))<0.0001)}
  let result:[String:Any]=["status":"PASS","platform":"macOS RealityKit","meshes":models.count,"disjoint_complete_shadow_groups":groups.count,"full_component_relative_pose_checks":entries.count,"identity_root":true,"bounds_match":true,"no_authored_collision_or_input":true,"VisionPro":"not tested"]
  let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]);try data.write(to:dir.appendingPathComponent("validation-native.json"));print(String(decoding:data,as:UTF8.self))
 }
}
