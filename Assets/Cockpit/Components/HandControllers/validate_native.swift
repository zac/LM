import Foundation
import RealityKit
@main struct Check {
 @MainActor static func main() async throws {
  let dir=URL(fileURLWithPath:CommandLine.arguments[1]); let meta=try JSONSerialization.jsonObject(with:Data(contentsOf:dir.appendingPathComponent("interface.json"))) as! [String:Any]
  var results=[[String:Any]]()
  for id in ["ACA","TTCA"] {
   let start=Date(); let scene=try await Entity(contentsOf:dir.appendingPathComponent(id+".usdz")); let root=scene.findEntity(named:id+"_Mount")!
   precondition(simd_length(root.scale-SIMD3<Float>(repeating:1))<0.00001)
   let fixed=root.findEntity(named:id+"_Fixed")!; let fixedTransform=fixed.transformMatrix(relativeTo:root)
   for e in meta["entities"] as! [[String:Any]] where (e["name"] as! String).hasPrefix(id) {
    let part=root.findEntity(named:e["name"] as! String)!; precondition(part.parent?.name==e["parent"] as? String)
    let original=part.transform; let axisName=e["axis"] as! String; let axis:SIMD3<Float>=axisName=="X" ? [1,0,0] : axisName=="Y" ? [0,1,0] : [0,0,1]
    if e["motion"] as! String == "rotation" {part.orientation=simd_quatf(angle:0.1,axis:axis)} else {part.position += axis*0.005}
    precondition(fixed.transformMatrix(relativeTo:root)==fixedTransform); part.transform=original
   }
   let b=root.visualBounds(relativeTo:root); results.append(["id":id,"load_and_check_seconds":Date().timeIntervalSince(start),"hierarchy_and_fixed_isolation":"PASS","bounds_min_m":[b.min.x,b.min.y,b.min.z],"bounds_max_m":[b.max.x,b.max.y,b.max.z]])
  }
  let out:[String:Any]=["platform":"macOS RealityKit","assets":results,"VisionPro":"NOT TESTED","live_bindings":"NOT IMPLEMENTED"]
  try JSONSerialization.data(withJSONObject:out,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("native-validation.json")); print("NATIVE PASS")
 }
}
