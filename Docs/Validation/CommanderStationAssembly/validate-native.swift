import Foundation
import RealityKit
import simd
@main struct Check {
 @MainActor static func main() throws {
  let path = CommandLine.arguments[1] + "/"
  let root = try Entity.load(contentsOf: URL(fileURLWithPath: path + "Cabin.usdz"))
  let cabin = root.findEntity(named: "Cabin")!
  let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path + "mounts.json"))) as! [String:Any]
  var checks:[[String:Any]] = []
  for (name,value) in json["mounts"] as! [String:[String:Any]] {
   let n=cabin.findEntity(named:name)!
   let p=(value["position"] as! [NSNumber]).map(\.floatValue)
   let angle=(value["rotation_x_degrees"] as! NSNumber).floatValue
   let expected=Transform(rotation:simd_quatf(angle:angle * .pi / 180,axis:[1,0,0]),translation:[p[0],p[1],p[2]]).matrix
   let actual=n.transformMatrix(relativeTo:cabin)
   let error=(0..<4).map { simd_length(actual[$0]-expected[$0]) }.max()!
   checks.append(["mount":name,"maximumColumnError":error,"pass":error < 0.00001])
  }
  let lpd = LMLandingPointDesignator()
  var optical: [[String: Any]] = []
  for pane in LMLPDPane.allCases {
   let name = pane == .inner ? "CDR_Window_Inner" : "CDR_Window_Outer"
   let node = cabin.findEntity(named: name)!
   let pointError = simd_distance(node.position(relativeTo: cabin), lpd.windowCorners(on: pane)[0])
   let normalError = simd_distance(node.orientation(relativeTo: cabin).act([0,0,1]), lpd.paneOrientation(pane).act([0,0,1]))
   optical.append(["node": name, "cornerErrorMeters": pointError, "normalError": normalError, "pass": pointError < 0.00001 && normalError < 0.00001])
  }
  let data=try JSONSerialization.data(withJSONObject:["optical": optical, "runtime":"macOS RealityKit; no simulator or headset claim","rootRelativeMounts":checks.sorted { ($0["mount"] as! String) < ($1["mount"] as! String) }],options:[.prettyPrinted,.sortedKeys])
  print(String(decoding:data,as:UTF8.self))
  if !(checks + optical).allSatisfy({ $0["pass"] as? Bool == true }) { exit(1) }
 }
}
