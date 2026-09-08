import Foundation
import RealityKit
struct Pose:Decodable {let position_m:[Float];let rotation_quaternion_xyzw:[Float];let scale:[Float]}
struct Ref:Decodable {let component:String;let path:String;let pose:Pose}
struct Group:Decodable {let path:String;let casts_shadows:Bool}
struct Contract:Decodable {let root:String;let root_pose:Pose;let groups:[Group];let suppressions:[Ref];let protected_mounts:[Ref]}
@main struct Validate {
 @MainActor static func main() async throws {
 let dir=URL(fileURLWithPath:CommandLine.arguments[1]);let c=try JSONDecoder().decode(Contract.self,from:Data(contentsOf:dir.appendingPathComponent("interface.json")));var checks=0
 func check(_ ok:Bool,_ m:String){precondition(ok,m);checks+=1}
 func root(_ loaded:Entity,_ name:String)->Entity {if loaded.name==name{return loaded};return loaded.findEntity(named:name)!}
 func path(_ root:Entity,_ full:String)->Entity {let parts=full.split(separator:"/").map(String.init);precondition(parts.first==root.name);return parts.dropFirst().reduce(root){parent,name in parent.children.first(where:{$0.name==name})!}}
 func verify(_ e:Entity,_ relative:Entity,_ p:Pose){let t=e.transformMatrix(relativeTo:relative);let pos=SIMD3(t.columns.3.x,t.columns.3.y,t.columns.3.z);check(simd_length(pos-SIMD3(p.position_m[0],p.position_m[1],p.position_m[2]))<2e-5,"position");let q=simd_quatf(t);let expected=simd_quatf(ix:p.rotation_quaternion_xyzw[0],iy:p.rotation_quaternion_xyzw[1],iz:p.rotation_quaternion_xyzw[2],r:p.rotation_quaternion_xyzw[3]);check(abs(simd_dot(q.vector,expected.vector))>0.99999,"rotation");check(abs(simd_determinant(t)-1)<1e-4,"proper transform")}
 let loaded=try await Entity(contentsOf:dir.appendingPathComponent("WindowSurrounds.usdz"));let overlay=root(loaded,"WindowSurrounds");check(simd_length(overlay.position)<1e-6 && simd_length(overlay.scale-SIMD3(repeating:1))<1e-6,"identity overlay")
 var modelCount=0
 func count(_ e:Entity){if e.components[ModelComponent.self] != nil {modelCount+=1};for ch in e.children{count(ch)}}
 for g in c.groups {let e=path(overlay,g.path);check(g.casts_shadows,"replacement walls must cast shadows");check(e.parent === overlay,"top level side group");count(e)}
 for component in ["Cabin","WindowsLPD"] {let asset=try await Entity(contentsOf:dir.deletingLastPathComponent().appendingPathComponent(component+"/"+component+".usdz"));let source=root(asset,component)
  for ref in c.suppressions+c.protected_mounts where ref.component==component {let e=path(source,ref.path);verify(e,source,ref.pose);if c.suppressions.contains(where:{$0.path==ref.path}){check(e.components[ModelComponent.self] != nil && e.children.isEmpty,"suppression is a leaf mesh");e.isEnabled=false;check(!e.isEnabled,"leaf disabled");e.isEnabled=true}}
 }
 let result:[String:Any]=["status":"PASS","platform":"macOS RealityKit","checks":checks,"new_models":modelCount,"suppression_leaves":c.suppressions.count,"protected_mounts":c.protected_mounts.count,"limits":["No native render/headset acceptance","No actor input or simulation behavior","Optical alignment qualification remains unchanged"]];print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys,.prettyPrinted]),as:UTF8.self))
 }
}
