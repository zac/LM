import Foundation
import RealityKit
@main struct ValidateCommanderPanels {
 @MainActor static func main() async throws {
  let url=URL(fileURLWithPath:CommandLine.arguments[1]); let scene=try await Entity(contentsOf:url)
  let root=scene.findEntity(named:"CommanderPanels")!
  let identity=matrix_identity_float4x4
  for i in 0..<4 { precondition(simd_length(root.transform.matrix[i]-identity[i])<1e-5) }
  let data=try Data(contentsOf:url.deletingLastPathComponent().appendingPathComponent("mounting.json"))
  let manifest=try JSONSerialization.jsonObject(with:data) as! [String:Any]
  let rows=manifest["interfaces"] as! [String:[String:Any]]
  for (name,row) in rows {
   let entity=root.findEntity(named:name+"_Interface")!
   let record=row["interface_cabin_relative"] as! [String:Any]
   let p=record["position"] as! [Double]
   precondition(simd_distance(entity.position(relativeTo:root),SIMD3<Float>(Float(p[0]),Float(p[1]),Float(p[2])))<1e-5)
   let degrees=record["rotation_x_degrees"] as! Double
   let expected=simd_quatf(angle:Float(degrees)*Float.pi/180,axis:[1,0,0])
   precondition(simd_distance(entity.orientation(relativeTo:root).act([0,0,1]),expected.act([0,0,1]))<1e-5)
   precondition(entity.children.isEmpty)
   let number=name=="FDAI" ? "1":"4"
   for suffix in ["Shell","Trim","Fasteners","RemovableBacking"] { precondition(root.findEntity(named:"Panel_"+number+"_"+suffix) != nil) }
  }
  let p4=root.findEntity(named:"Panel_4")!; let before=p4.transformMatrix(relativeTo:root)
  root.findEntity(named:"Panel_1_RemovableBacking")!.position.z += 0.01
  for i in 0..<4 { precondition(simd_length(p4.transformMatrix(relativeTo:root)[i]-before[i])<1e-5) }
  let result:[String:Any] = ["native_load":"PASS","platform":"macOS RealityKit","identity_root":"PASS","instrument_Cabin_transforms":"PASS","independent_backing":"PASS","empty_instrument_interfaces":"PASS","visionOS":"NOT TESTED","mechanical_fit":"NOT QUALIFIED"]
  print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
 }
}
