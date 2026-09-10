// macOS RealityKit smoke validation; no Vision Pro optics or interaction claim.
import Foundation
import RealityKit
@main struct ValidateCabin {
 @MainActor static func main() async throws {
  let url=URL(fileURLWithPath:CommandLine.arguments[1])
  let scene=try await Entity(contentsOf:url)
  guard let root=scene.findEntity(named:"Cabin") else { fatalError("Missing Cabin") }
  precondition(simd_length(root.scale-SIMD3<Float>(repeating:1))<1e-5)
  let eye=root.findEntity(named:"CDR_Eye")!
  precondition(simd_length(eye.position(relativeTo:root)-SIMD3<Float>(-0.5588,1.78,-0.38))<1e-5)
  let data=try Data(contentsOf:url.deletingLastPathComponent().appendingPathComponent("mounts.json"))
  let manifest=try JSONSerialization.jsonObject(with:data) as! [String:Any]
  let mounts=manifest["mounts"] as! [String:[String:Any]]
  for (name,row) in mounts {
   let node=root.findEntity(named:name)!
   let p=row["position"] as! [Double]
   precondition(simd_length(node.position(relativeTo:root)-SIMD3<Float>(Float(p[0]),Float(p[1]),Float(p[2])))<1e-5)
  }
  for layer in ["Inner","Outer"] {
   let pane=root.findEntity(named:"CDR_Window_"+layer)!
   precondition(pane.findEntity(named:"LPD_"+layer)?.parent === pane)
   let actual=pane.orientation(relativeTo:root).act(SIMD3<Float>(0,0,1))
   let optics=manifest["optical"] as! [String:[String:Any]]
   let n=optics["CDR_Window_"+layer]!["normal"] as! [Double]
   precondition(simd_length(actual-SIMD3<Float>(Float(n[0]),Float(n[1]),Float(n[2])))<1e-5)
  }
  for name in ["Forward_Hatch_Closed", "Transfer_Hatch_Closed", "Docking_Window_Opening", "Cutaway_Aft", "Cutaway_Ceiling", "Cabin_Deck"] {
   precondition(root.findEntity(named:name) != nil)
  }
  let hatch=root.findEntity(named:"Forward_Hatch_Closed")!
  let leaf=hatch.findEntity(named:"Forward_Hatch_Leaf")!
  let old=leaf.position(relativeTo:root);hatch.position.x += 0.01
  precondition(abs(leaf.position(relativeTo:root).x-old.x-0.01)<1e-5)
  hatch.position.x -= 0.01
  for name in ["Panel_1_Reservation", "CDR_Glareshield", "CDR_Pane_Inner", "CDR_Frame_Inner_0"] { precondition(root.findEntity(named:name) == nil) }
  let bounds=root.visualBounds(relativeTo:root)
  let output:[String:Any] = ["native_load":"PASS","platform":"macOS RealityKit","mount_positions":"PASS","mount_count":mounts.count,"eye_and_pane_basis":"PASS","separate_lpd_layers":"PASS","bounds_min":[bounds.min.x,bounds.min.y,bounds.min.z],"bounds_max":[bounds.max.x,bounds.max.y,bounds.max.z],"Vision_Pro":"NOT TESTED"]
  print(String(decoding:try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
 }
}
