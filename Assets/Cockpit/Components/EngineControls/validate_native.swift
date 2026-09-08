import Foundation
import RealityKit
@main struct ValidateNative {
 @MainActor static func main() async throws {
  let dir=URL(fileURLWithPath:CommandLine.arguments[1]); var records=[[String:Any]]()
  for id in ["EngineButtons","LunarContact"] {
   let loaded=try await Entity(contentsOf:dir.appendingPathComponent(id+".usdz"));let root=loaded.findEntity(named:id+"_Mount")!
   precondition(simd_length(root.position)<0.00001);precondition(simd_length(root.scale-SIMD3<Float>(repeating:1))<0.00001)
   if id=="EngineButtons" {
    let start=root.findEntity(named:"EngineButtons__StartActuator")!;let stop=root.findEntity(named:"EngineButtons__StopActuator")!;let latch=root.findEntity(named:"EngineButtons__StopResetLatch")!
    precondition(start.parent === root && stop.parent === root && latch.parent === root)
    let neutral=start.transform;let other=stop.transform;start.position.z -= 0.002;precondition(stop.transform==other);start.transform=neutral
    precondition(start.findEntity(named:"EngineButtons__StartLightFace") != nil && stop.findEntity(named:"EngineButtons__StopLightFace") != nil)
   } else {
    let face=root.findEntity(named:"LunarContact__LightFace") as! ModelEntity;let lens=root.findEntity(named:"LunarContact__Lens")!;let neutral=lens.transform
    let materials=face.model!.materials;face.model!.materials=[UnlitMaterial(color:.blue)];precondition(lens.transform==neutral);face.model!.materials=materials
   }
   records.append(["id":id,"nativeLoad":"PASS","independentParts":"PASS","neutralRestored":"PASS"])
  }
  let result:[String:Any]=["platform":"macOS RealityKit","components":records,"VisionPro":"NOT TESTED","simulationBinding":"NOT TESTED; engine unavailable"]
  try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("native-validation.json"));print("NATIVE_PASS",records.count)
 }
}
