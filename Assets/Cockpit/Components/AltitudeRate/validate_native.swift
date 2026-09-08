import Foundation
import RealityKit
struct Row: Decodable { let name: String; let value: Double; let major: Bool }
struct Channel: Decodable {
 let group: String; let pointer: String; let unavailable: String; let valid_range: [Double]; let origin_m: [Float]; let rows: [Row]
 let q_knots: [[Double]]?; let q_abs_knots: [[Double]]?; let unavailable_active_position_m: [Float]; let unavailable_parked_position_m: [Float]
 func q(_ value: Double) -> Double {
  let knots=q_knots ?? q_abs_knots!; let mag=q_abs_knots == nil ? value : abs(value)
  for i in 1..<knots.count where mag<=knots[i][0] {let lo=knots[i-1],hi=knots[i];return (lo[1]+(mag-lo[0])/(hi[0]-lo[0])*(hi[1]-lo[1]))*(value<0 ? -1:1)}
  fatalError("Outside tape transfer domain")
 }
}
struct Contract: Decodable {let altitude:Channel;let altitude_rate:Channel}
@main struct Validate {
 @MainActor static func main() async throws {
  let asset=URL(fileURLWithPath:CommandLine.arguments[1]);let c=try JSONDecoder().decode(Contract.self,from:Data(contentsOf:asset.deletingLastPathComponent().appendingPathComponent("interface.json")))
  let loaded=try await Entity(contentsOf:asset);guard let root=loaded.findEntity(named:"AltitudeRate") else {fatalError("Missing root")}
  precondition(simd_length(root.position)<1e-6 && simd_length(root.scale-SIMD3<Float>(repeating:1))<1e-6)
  var checks=0
  func expect(_ ok:Bool,_ text:String){precondition(ok,text);checks+=1}
  func vec(_ p:[Float])->SIMD3<Float>{SIMD3(p[0],p[1],p[2])}
  let lens=root.findEntity(named:"ProtectiveLens")!;let fixed=root.findEntity(named:"Fixed")!;let initialFixed=fixed.transform
  var boundMax:Float=0
  for (ch,values) in [(c.altitude,[0,100,333,1000,5000,10000,60000,-1,60001,Double.nan]),(c.altitude_rate,[-700,-100,-20,-5,0,5,20,100,700,701,Double.nan])] {
   let tape=root.findEntity(named:ch.group)!;expect(simd_length(tape.position-vec(ch.origin_m))<1e-6,"Tape origin")
   let shutter=root.findEntity(named:ch.unavailable)!;expect(shutter.parent===root,"Shutter direct root parent")
   expect(simd_length(shutter.position-vec(ch.unavailable_parked_position_m))<1e-6,"Shutter neutral parking")
   for row in ch.rows {
    let e=tape.findEntity(named:row.name)!;expect(e.parent===tape,"Row direct tape parent")
    let b=e.visualBounds(relativeTo:e);boundMax=max(boundMax,max(abs(b.min.y),abs(b.max.y)));expect(max(abs(b.min.y),abs(b.max.y))<=0.0035,"Row text height fits clipping margin")
   }
   for value in values {
    let valid=value.isFinite && ch.valid_range[0]<=value && value<=ch.valid_range[1]
    var shown=0
    for row in ch.rows {
     let e=tape.findEntity(named:row.name)!;let delta=valid ? ch.q(row.value)-ch.q(value):999
     e.isEnabled=valid && abs(delta)<=0.043
     if e.isEnabled {e.position=SIMD3(0,Float(delta),0);shown+=1;expect(abs(e.position.y)<=0.043001,"Aperture limit")}
     if valid && row.value==value {expect(e.isEnabled && abs(e.position.y)<1e-6,"Requested labeled/tick value aligns fixed pointer")}
    }
    shutter.position=vec(valid ? ch.unavailable_parked_position_m:ch.unavailable_active_position_m)
    expect(valid ? shown>0:shown==0,"Invalid data never reads zero/stale")
    expect(simd_length(shutter.position-vec(valid ? ch.unavailable_parked_position_m:ch.unavailable_active_position_m))<1e-6,"Shutter state")
    expect(fixed.transform==initialFixed,"Fixed bezel and pointer stable")
   }
  }
  expect(lens.findEntity(named:"Lens_Glass") != nil,"Independent lens")
  let result:[String:Any]=["native_load":"PASS","platform":"macOS RealityKit","checks":checks,"max_row_half_height_m":boundMax,"cases":21,"input_cases":"altitude zero/interior/piecewise/boundary/negative/overrange/NaN; rate positive/up negative/down/zero/piecewise/endpoints/overrange/NaN","parent_poses_and_shutters":"PASS","no_simulation_signal_fidelity_claim":true,"native_render":"not covered by this test","headset":"NOT TESTED"]
  print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
 }
}
