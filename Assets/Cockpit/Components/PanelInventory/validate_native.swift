// xcrun swiftc -parse-as-library validate_native.swift -o /tmp/panel-inventory-native
import Foundation
import RealityKit
@main struct Validate {
 @MainActor static func main() async throws {
  let dir=URL(fileURLWithPath:CommandLine.arguments[1]);let data=try Data(contentsOf:dir.appendingPathComponent("inventory.json"))
  let manifest=try JSONSerialization.jsonObject(with:data) as! [String:Any]
  let loaded=try await Entity(contentsOf:dir.appendingPathComponent("PanelInventory.usdz"))
  let root=loaded.findEntity(named:"PanelInventory")!
  func entity(_ path:String)->Entity {
   var e=root
   for name in path.split(separator:"/").dropFirst() {e=e.children.first(where:{$0.name==name})!}
   return e
  }
  let layer=entity(manifest["planning_label_layer"] as! String)
  var count=0
  for p in manifest["panels"] as! [[String:Any]] {
   let panel=entity(p["node"] as! String);let pose=p["pose"] as! [String:Any];let t=pose["translation_m"] as! [Double]
   precondition(simd_length(panel.position(relativeTo:root)-SIMD3<Float>(t.map(Float.init)))<0.000002)
   precondition(simd_length(panel.scale-SIMD3<Float>(repeating:1))<0.00001)
   let slots=p["slots"] as! [[String:Any]]
   for s in slots {
    let slot=entity(s["node"] as! String);let blank=entity(s["default_placeholder_node"] as! String);let label=entity(s["label_node"] as! String)
    precondition(blank.parent === slot);precondition(label.parent !== slot)
    let original=panel.transform;let siblingStates=panel.children.map{($0,$0.isEnabled,$0.transform)}
    blank.isEnabled=false
    precondition(panel.transform==original && label.isEnabled)
    for (e,enabled,transform) in siblingStates {precondition(e.isEnabled==enabled && e.transform==transform)}
    blank.isEnabled=true // failure/missing occupant retains blank
    layer.isEnabled=false;precondition(blank.isEnabled && panel.isEnabled)
    layer.isEnabled=true;count += 1
   }
  }
  layer.isEnabled=false
  let bounds=root.visualBounds(relativeTo:root)
  let report:[String:Any]=["platform":"macOS RealityKit","native_load":"PASS","slots_checked":count,"path_parentage":"PASS","metric_panel_translations":"PASS","placeholder_independence":"PASS","label_layer_independence":"PASS","boundsMin":[bounds.min.x,bounds.min.y,bounds.min.z],"boundsMax":[bounds.max.x,bounds.max.y,bounds.max.z],"visionOS":"NOT TESTED; coordinator owns packaging and simulator","actual_external_replacement":"NOT TESTED; no peer assets embedded"]
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("native-validation.json"))
  print("NATIVE_PASS \(count) slots")
 }
}
