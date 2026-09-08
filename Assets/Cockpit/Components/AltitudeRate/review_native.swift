// Native SceneKit USDZ visual check; no simulator or RealityKit rendered-appearance claim.
import Foundation
import AppKit
import SceneKit
import Metal
let base=URL(fileURLWithPath:CommandLine.arguments[1]);let scene=try SCNScene(url:base.appendingPathComponent("AltitudeRate.usdz"),options:nil)
let c=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("interface.json"))) as! [String:Any]
func q(_ val:Double,_ d:[String:Any])->Double {let odd=d["q_abs_knots"] != nil;let knots=(d["q_knots"] ?? d["q_abs_knots"]) as! [[Double]];let v=odd ? abs(val):val;for i in 1..<knots.count where v<=knots[i][0] {let lo=knots[i-1],hi=knots[i];return (lo[1]+(v-lo[0])/(hi[0]-lo[0])*(hi[1]-lo[1]))*(val<0 ? -1:1)};fatalError()}
for (key,current) in [("altitude",100.0),("altitude_rate",-5.0)] {
 let d=c[key] as! [String:Any];let tape=scene.rootNode.childNode(withName:d["group"] as! String,recursively:true)!
 for r in d["rows"] as! [[String:Any]] {let row=tape.childNode(withName:r["name"] as! String,recursively:true)!;let delta=q(r["value"] as! Double,d)-q(current,d);row.isHidden=abs(delta)>0.043;row.position=SCNVector3(0,Float(delta),0)}
}
let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=0.080;camera.camera!.zNear=0.001;camera.position=SCNVector3(0,0,0.4);scene.rootNode.addChildNode(camera);camera.look(at:SCNVector3Zero)
let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera;renderer.autoenablesDefaultLighting=true;scene.background.contents=NSColor.darkGray
for hidden in [false,true] {
 scene.rootNode.childNode(withName:"ProtectiveLens",recursively:true)?.isHidden=hidden
 let img=renderer.snapshot(atTime:0,with:CGSize(width:650,height:1000),antialiasingMode:.multisampling4X);let rep=NSBitmapImageRep(data:img.tiffRepresentation!)!;try rep.representation(using:.png,properties:[:])!.write(to:base.appendingPathComponent("reviews/native-"+(hidden ? "without-lens":"with-lens")+".png"))
}
print("SceneKit with/without protective lens captured; independent RealityKit loading tested separately")
