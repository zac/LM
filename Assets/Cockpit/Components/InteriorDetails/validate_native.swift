import Foundation
import RealityKit
@main struct ValidateInteriorDetails {
 @MainActor static func main() async throws {
  let directory = URL(fileURLWithPath: CommandLine.arguments[1])
  let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("interface.json"))) as! [String: Any]
  let asset = try await Entity(contentsOf: directory.appendingPathComponent("InteriorDetails.usdz"))
  guard let root = asset.findEntity(named: "InteriorDetails") else { fatalError("Missing root") }
  precondition(simd_length(root.position) < 0.000001)
  precondition(simd_length(root.scale - SIMD3<Float>(repeating: 1)) < 0.000001)
  precondition(abs(root.orientation.real) > 0.999999)
  var results = [[String: Any]]()
  for group in metadata["groups"] as! [[String: Any]] {
   let name = group["name"] as! String
   guard let entity = root.children.first(where: { $0.name == name }) else { fatalError("Missing group") }
   let original = root.children.map { $0.isEnabled }
   entity.isEnabled = false
   precondition(root.children.filter { $0 !== entity }.allSatisfy { $0.isEnabled })
   entity.isEnabled = true
   precondition(root.children.map { $0.isEnabled } == original)
   let bounds = entity.visualBounds(relativeTo: root)
   results.append(["name": name, "independentVisibility": true, "min": [bounds.min.x,bounds.min.y,bounds.min.z], "max": [bounds.max.x,bounds.max.y,bounds.max.z]])
  }
  var count = 0
  func inspect(_ entity: Entity) {
   count += 1
   precondition(entity.components[CollisionComponent.self] == nil)
   precondition(entity.components[InputTargetComponent.self] == nil)
   precondition(entity.components[PhysicsBodyComponent.self] == nil)
   precondition(entity.components[PointLightComponent.self] == nil)
   precondition(entity.components[SpotLightComponent.self] == nil)
   precondition(entity.components[DirectionalLightComponent.self] == nil)
   for child in entity.children { inspect(child) }
  }
  inspect(root)
  let result: [String: Any] = ["platform":"macOS RealityKit", "nativeLoad":"PASS", "identityRoot":"PASS", "noInputPhysicsLights":"PASS", "entitiesChecked":count, "groups":results, "VisionPro":"NOT TESTED"]
  try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: directory.appendingPathComponent("native-validation.json"))
  print("NATIVE_PASS \(results.count) independent groups, \(count) entities")
 }
}
