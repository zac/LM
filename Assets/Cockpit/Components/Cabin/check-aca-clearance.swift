// Adapted from pinned accepted integration checker (see evidence/foundation).
import Foundation
import RealityKit
import simd

@main struct Check {
 @MainActor static func main() throws {
  let base = URL(fileURLWithPath: CommandLine.arguments[1])
  let scene = Entity()
  let panels = try Entity.load(contentsOf: URL(fileURLWithPath:CommandLine.arguments[2]))
  let aca = try Entity.load(contentsOf: base.appendingPathComponent("HandControllers/ACA.usdz"))
  scene.addChild(panels); scene.addChild(aca)
  let root = aca.findEntity(named: "ACA_Mount")!
  root.position = [-0.49, 0.9075, -0.37]
  let roll = root.findEntity(named: "ACA_Roll")!, yaw = root.findEntity(named: "ACA_Yaw")!, pitch = root.findEntity(named: "ACA_Pitch")!
  func models(_ node: Entity) -> [Entity] { (node.components[ModelComponent.self] == nil ? [] : [node]) + node.children.flatMap { models($0) } }
  let panelModels = models(panels)
  var gap = Float.infinity; var closest = ""; var overlaps = Set<String>()
  let angle = Float.pi * 11 / 180
  for r in -4...4 { for y in -4...4 { for p in -4...4 {
   roll.orientation = simd_quatf(angle: -Float(r)/4*angle, axis: [0,0,1])
   yaw.orientation = simd_quatf(angle: Float(y)/4*angle, axis: [0,1,0])
   pitch.orientation = simd_quatf(angle: Float(p)/4*angle, axis: [1,0,0])
   let a = aca.visualBounds(relativeTo: scene)
   for node in panelModels {
    let b = node.visualBounds(relativeTo: scene)
    let d = simd_max(simd_max(a.min-b.max, b.min-a.max), .zero)
    let distance = simd_length(d)
    if distance < gap { gap = distance; closest = node.name }
    if distance == 0 { overlaps.insert(node.name) }
   }
  } } }
  let report: [String:Any] = ["method":"Native macOS RealityKit AABB separation for every Cabin mesh against whole ACA bounds; 729 sampled poses at 2.75 degrees; not continuous collision or hand clearance proof", "sample_count":729,"cabin_mesh_count":panelModels.count,"minimum_aabb_gap_m":gap,"closest_panel_mesh":closest,"possible_aabb_overlaps":overlaps.sorted()]
  print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
 }
}
