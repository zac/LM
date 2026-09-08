import Foundation
import RealityKit
@main struct ValidateNative {
 @MainActor static func main() async throws {
  let dir=URL(fileURLWithPath:CommandLine.arguments[1]);let obj=try JSONSerialization.jsonObject(with:Data(contentsOf:dir.appendingPathComponent("interface.json"))) as! [String:Any]
  var records=[[String:Any]]()
  for item in obj["components"] as! [[String:Any]] {
   let id=item["id"] as! String;let loaded=try await Entity(contentsOf:dir.appendingPathComponent(item["asset"] as! String));let root=loaded.findEntity(named:item["mount"] as! String)!;let part=root.findEntity(named:item["actuator"] as! String)!;let backing=root.findEntity(named:item["neutral_backing"] as! String)!
   precondition(part.parent === root);precondition(simd_length(root.position)<0.00001);precondition(simd_length(root.scale-SIMD3<Float>(repeating:1))<0.00001)
   let target=item["actuator_neutral_position_m"] as! [Double];precondition(simd_length(part.position-SIMD3<Float>(target.map(Float.init)))<0.000001)
   let saved=part.transform;let fixed=backing.transform
   let baseline=id=="DescentRate" ? simd_quatf(angle:-Float.pi/2,axis:[0,1,0]):simd_quatf(angle:0,axis:[1,0,0])
   for degree:Float in [-17,0,17] {
    part.orientation=baseline*simd_quatf(angle:degree*Float.pi/180,axis:[1,0,0]);precondition(backing.transform==fixed)
    let tip=part.convert(position:[0,0,0.023],to:root);if degree != 0 {precondition((tip.y-part.position.y>0)==(degree<0))}
   }
   part.transform=saved;precondition(part.transform==saved)
   backing.isEnabled=false;precondition(part.isEnabled);backing.isEnabled=true
   records.append(["id":id,"nativeLoad":"PASS","independentActuator":"PASS","inputPoseDirections":"PASS","neutralRestored":"PASS","backingToggleIndependent":"PASS"])
  }
  let result:[String:Any]=["platform":"macOS RealityKit","components":records,"VisionPro":"NOT TESTED","simulationBinding":"NOT TESTED: coordinator responsibility"]
  try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("native-validation.json"));print("NATIVE_PASS",records.count)
 }
}
