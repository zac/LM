import Foundation
import RealityKit
import AppKit
struct Digit:Decodable {let name:String;let position_m:[Float];let segments:[String:String]}
struct Control:Decodable {let pivot:String;let stem:String;let position_m:[Float];let angles_degrees:[Float]}
struct Asset:Decodable {let filename:String;let root:String;let kind:String;let digits:[Digit]?;let controls:[Control]?}
struct Contract:Decodable {let assets:[Asset];let digit_masks:[String:[String]]}
@main struct Validate {
 @MainActor static func main() async throws {
 let dir=URL(fileURLWithPath:CommandLine.arguments[1]);let c=try JSONDecoder().decode(Contract.self,from:Data(contentsOf:dir.appendingPathComponent("interface.json")));var checks=0;var loadedAssets=[String]()
 func check(_ ok:Bool,_ message:String){precondition(ok,message);checks+=1}
 for a in c.assets {
  let entity=try await Entity(contentsOf:dir.appendingPathComponent(a.filename));guard let root=entity.findEntity(named:a.root) else {fatalError("missing root")};loadedAssets.append(a.filename)
  check(simd_length(root.position)<1e-6 && simd_length(root.scale-SIMD3(repeating:1))<1e-6,"neutral root")
  let fixed=root.findEntity(named:a.root+"_Fixed")!;let fixedTransform=fixed.transform
  for d in a.digits ?? [] {
   let digit=root.findEntity(named:d.name)!;check(simd_length(digit.position-SIMD3(d.position_m[0],d.position_m[1],d.position_m[2]))<1e-6,"digit pose")
   for n in 0...9 {
    for (segment,name) in d.segments {let e=digit.findEntity(named:name)!;check(e.parent === digit,"segment parent");guard var model=e.components[ModelComponent.self] else {fatalError("missing segment model")};let on=c.digit_masks[String(n)]!.contains(segment);model.materials=[UnlitMaterial(color:on ? NSColor(calibratedRed:0.63,green:0.82,blue:0.60,alpha:1):NSColor(calibratedWhite:0.02,alpha:1))];e.components.set(model);check(e.isEnabled && model.materials.count==1,"native material mutation")}
   }
  }
  for control in a.controls ?? [] {let e=root.findEntity(named:control.pivot)!;let base=e.position;check(e.parent === root,"pivot parent");check(e.findEntity(named:control.stem)?.parent === e,"stem child");for angle in control.angles_degrees {e.orientation=simd_quatf(angle:angle * .pi/180,axis:SIMD3(1,0,0));check(simd_length(e.position-base)<1e-6,"pivot stationary");check(abs(e.orientation.angle-abs(angle * .pi/180))<1e-5,"throwangle")};e.orientation=simd_quatf(angle:0,axis:SIMD3(1,0,0))}
  check(fixed.transform==fixedTransform,"face fixed")
 }
 let result:[String:Any]=["status":"PASS","platform":"macOS RealityKit","checks":checks,"loaded_assets":loadedAssets,"digit_states":"Every digit all ten seven-segment masks; native material swaps","control_states":"Every pivot each of three detents","limitations":["No simulator/headset","No real clock behavior exercised","Native material mutation is not rendered-appearance acceptance"]];print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
 }
}
