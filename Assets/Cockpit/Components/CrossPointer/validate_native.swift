import Foundation
import RealityKit
@main struct CrossPointerValidation {
 @MainActor static func main() async throws {
  let dir=URL(fileURLWithPath:CommandLine.arguments[1]);let loaded=try await Entity(contentsOf:dir.appendingPathComponent("CrossPointer.usdz"))
  let root=loaded.findEntity(named:"CrossPointer")!
  func path(_ s:String)->Entity {s.split(separator:"/").dropFirst().reduce(root){p,n in let matches=p.children.filter{$0.name==n};precondition(matches.count==1);return matches[0]}}
  let fixed=path("/CrossPointer/Fixed"),moving=path("/CrossPointer/Needles")
  let l=path("/CrossPointer/Needles/LateralNeedle"),f=path("/CrossPointer/Needles/ForwardNeedle")
  precondition(simd_distance(root.position,.zero)<1e-6 && simd_distance(root.scale,[1,1,1])<1e-6)
  precondition(simd_distance(l.position,[0.003,0.003,0.0017])<1e-6 && simd_distance(f.position,[0.003,0.003,0.00215])<1e-6)
  let fixedBefore=fixed.transform,forwardBefore=f.transform
  l.position.x -= 0.016
  precondition(fixed.transform==fixedBefore && f.transform==forwardBefore)
  f.position.y += 0.016
  precondition(simd_distance(l.position,[-0.013,0.003,0.0017])<1e-6 && simd_distance(f.position,[0.003,0.019,0.00215])<1e-6)
  moving.isEnabled=false
  precondition(fixed.isEnabled)
  let result:[String:Any] = ["native_load":"PASS","identity_root":"PASS","independent_needles":"PASS","numeric_full_scale_positions":"PASS","invalid_hides_needles_keeps_face":"PASS","platform":"macOS RealityKit","simulation_frame_and_polarity":"owned by LM; not exercised here","visionOS":"NOT TESTED"]
  try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("native-validation.json"));print("CROSSPOINTER NATIVE PASS")
 }
}
