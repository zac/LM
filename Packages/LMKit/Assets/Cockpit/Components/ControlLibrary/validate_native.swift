// xcrun swiftc -parse-as-library validate_native.swift -o /tmp/control-library-native
// /tmp/control-library-native /absolute/path/to/ControlLibrary
import Foundation
import RealityKit
@main struct ValidateNative {
 @MainActor static func main() async throws {
  let directory=URL(fileURLWithPath:CommandLine.arguments[1])
  let metadata=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("components.json"))) as! [String:Any]
  var results=[[String:Any]]()
  for item in metadata["components"] as! [[String:Any]] {
   let id=item["id"] as! String
   let scene=try await Entity(contentsOf:directory.appendingPathComponent(id+".usdz"))
   guard let mount=scene.findEntity(named:item["mount"] as! String) else {fatalError("missing mount")}
   precondition(simd_length(mount.scale-SIMD3<Float>(repeating:1))<0.00001)
   let housing=mount.findEntity(named:id+"__Housing")!
   for name in item["moving"] as! [String] {
    let part=mount.findEntity(named:name)!
    precondition(part.parent === mount)
    let fixed=housing.transform; let original=part.transform
    part.position.z += 0.001
    precondition(housing.transform==fixed)
    part.transform=original
   }
   let bounds=mount.visualBounds(relativeTo:mount)
   precondition(bounds.min.z<0 && bounds.max.z>0)
   results.append(["id":id,"native_load":"PASS","independent_parts":"PASS","panel_orientation":"PASS","boundsMin":[bounds.min.x,bounds.min.y,bounds.min.z],"boundsMax":[bounds.max.x,bounds.max.y,bounds.max.z]])
  }
  let data=try JSONSerialization.data(withJSONObject:["platform":"macOS RealityKit","assets":results,"VisionPro":"NOT TESTED"],options:[.prettyPrinted,.sortedKeys])
  try data.write(to:directory.appendingPathComponent("native-validation.json")); print("NATIVE_PASS \(results.count) assets")
 }
}
