import Foundation
import RealityKit
@main struct ValidateConsole {
 @MainActor static func main() async throws {
  let dir=URL(fileURLWithPath:CommandLine.arguments[1])
  let loaded=try await Entity(contentsOf:dir.appendingPathComponent("InstrumentConsole.usdz"))
  guard let root=loaded.findEntity(named:"InstrumentConsole") else {fatalError("Missing console root")}
  var checks=0
  func check(_ ok:Bool) {precondition(ok);checks += 1}
  func all(_ e:Entity)->[Entity] {[e]+e.children.flatMap{all($0)}}
  check(simd_distance(root.position,.zero)<1e-6 && simd_distance(root.scale,[1,1,1])<1e-6 && abs(root.orientation.real)>0.99999)
  let entities=all(root),models=entities.filter{$0.components[ModelComponent.self] != nil}
  check(models.count==39)
  for n in ["Faces","Enclosure","Seams"] {
   let matches=root.children.filter{$0.name==n};check(matches.count==1)
   check(all(matches[0]).contains{$0.components[ModelComponent.self] != nil})
  }
  for e in models {
   check(!e.visualBounds(relativeTo:root).isEmpty)
   check(e.components[InputTargetComponent.self]==nil && e.components[CollisionComponent.self]==nil)
  }
  check(!entities.contains{["FDAI_Ball_Pivot","DSKY_Key_PRO","PlanningLabels"].contains($0.name)})
  let report:[String:Any]=["native_load":"PASS","assertions":checks,"model_entities":models.count,"root_identity":"PASS","platform":"macOS RealityKit","visionOS":"NOT RUN","input_geometry":"absent; structural overlay only"]
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("native-validation.json"))
  print("PASS",checks,"native assertions")
 }
}
