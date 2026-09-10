import Foundation
import RealityKit
@main struct ValidateWindows {
 @MainActor static func main() async throws {
  let url=URL(fileURLWithPath:CommandLine.arguments[1]);let entity=try await Entity(contentsOf:url)
  let root=entity.findEntity(named:"WindowsLPD")!
  precondition(simd_length(root.scale-SIMD3<Float>(repeating:1))<1e-5)
  let m=try JSONSerialization.jsonObject(with:Data(contentsOf:url.deletingLastPathComponent().appendingPathComponent("manifest.json"))) as! [String:Any]
  let panes=m["pane_transforms"] as! [String:[String:Any]]
  for (name,row) in panes {
   let p=root.findEntity(named:name)!;let xyz=row["position"] as! [Double];let n=row["normal"] as! [Double]
   precondition(simd_length(p.position(relativeTo:root)-SIMD3<Float>(Float(xyz[0]),Float(xyz[1]),Float(xyz[2])))<1e-5)
   precondition(simd_length(p.orientation(relativeTo:root).act(SIMD3<Float>(0,0,1))-SIMD3<Float>(Float(n[0]),Float(n[1]),Float(n[2])))<1e-5)
   for (key,axis) in [("right",SIMD3<Float>(1,0,0)),("up",SIMD3<Float>(0,1,0))] {let a=row[key] as! [Double];precondition(simd_length(p.orientation(relativeTo:root).act(axis)-SIMD3<Float>(Float(a[0]),Float(a[1]),Float(a[2])))<1e-5)}
  }
  for layer in ["Inner","Outer"] {let p=root.findEntity(named:"CDR_Window_"+layer)!;precondition(p.findEntity(named:"LPD_"+layer)?.parent === p)}
  precondition(root.findEntity(named:"DockingWindow") != nil)
  precondition(root.findEntity(named:"LMP_Window_Inner")!.findEntity(named:"LPD_Inner") == nil)
  let bounds=root.visualBounds(relativeTo:root)
  let result:[String:Any] = ["native_load":"PASS","platform":"macOS RealityKit","pane_transforms":"PASS","separate_lpd_layers":"PASS","bounds_min":[bounds.min.x,bounds.min.y,bounds.min.z],"bounds_max":[bounds.max.x,bounds.max.y,bounds.max.z],"headset_optics":"NOT TESTED","native_transparency_reflection_render":"NOT TESTED"]
  print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys,.prettyPrinted]),as:UTF8.self))
 }
}
