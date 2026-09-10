import Foundation
import RealityKit
@main struct ValidatePropulsion {
 @MainActor static func main() async throws {
  let dir=URL(fileURLWithPath:CommandLine.arguments[1]);let data=try Data(contentsOf:dir.appendingPathComponent("interface.json"));let m=try JSONSerialization.jsonObject(with:data) as! [String:Any]
  let loaded=try await Entity(contentsOf:dir.appendingPathComponent("PropulsionInstruments.usdz"));let root=loaded.findEntity(named:"PropulsionInstruments")!
  var assertions=0
  func check(_ value:Bool) {precondition(value);assertions += 1}
  func path(_ p:String)->Entity {p.split(separator:"/").dropFirst().reduce(root){entity,n in let matches=entity.children.filter{$0.name==n};precondition(matches.count==1);return matches[0]}}
  func vector(_ x:Any)->SIMD3<Float> {let a=x as! [Double];return [Float(a[0]),Float(a[1]),Float(a[2])]}
  check(simd_distance(root.position,.zero)<1e-6 && simd_distance(root.scale,[1,1,1])<1e-6)
  let all=m["instruments"] as! [String:[String:Any]];let roots=all.values.map{path($0["root"] as! String)};let originalRoots=roots.map{$0.transform};var needleCount=0;var segmentCount=0
  for (_,r) in all {
   let instrument=path(r["root"] as! String);check(simd_distance(instrument.position,vector(r["translation_m"]!))<1e-6)
   let fixed=path((r["root"] as! String)+"/Fixed");let fixedOriginal=fixed.transform
   if let needles=r["needles"] as? [String:[String:Any]] {
    for (_,n) in needles {
     let needle=path(n["node"] as! String);let park=vector(n["parked_translation_m"]!);check(simd_distance(needle.position,park)<1e-6);let ys=n["scale_y_m"] as! [Double]
     for y in [ys[0],(ys[0]+ys[1])/2,ys[1]] {
      needle.position=[Float(n["valid_translation_x_m"] as! Double),Float(y),Float(n["valid_translation_z_m"] as! Double)];check(fixed.transform==fixedOriginal);check(zip(roots,originalRoots).allSatisfy{$0.transform==$1})
     }
     needle.position=park;check(needle.position.z<0);needleCount += 1
    }
   }
   if let rows=r["rows"] as? [String:[String:Any]] {
    for (_,row) in rows {
     for digitPath in row["digit_nodes"] as! [String] {
      let digit=path(digitPath);check(digit.children.count==7)
      for segmentName in row["segment_children"] as! [String] {
       let segment=path(digitPath+"/"+segmentName);let parked=segment.position;check(abs(parked.z-Float(r["parked_segment_z_m"] as! Double))<1e-6);let siblings=digit.children.map{($0,$0.transform)}
       segment.position.z=Float(r["active_segment_z_m"] as! Double);check(fixed.transform==fixedOriginal);check(siblings.filter{$0.0 !== segment}.allSatisfy{$0.0.transform==$0.1});segment.position=parked;segmentCount += 1
      }
     }
    }
   }
  }
  check(needleCount==7 && segmentCount==56)
  let report:[String:Any]=["platform":"macOS RealityKit","native_load":"PASS","assertions":assertions,"needle_channels":needleCount,"independent_segments":segmentCount,"neutral_unavailable":"PASS; all moving indicators parked","roots_preserved":"PASS","simulation_sources":"NOT SUPPLIED; asset does not fabricate readings","visionOS":"NOT TESTED"]
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("native-validation.json"));print("PROPULSION NATIVE PASS \(assertions) assertions")
 }
}
