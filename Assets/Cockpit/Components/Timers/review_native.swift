// Native SceneKit appearance preview, separate from RealityKit load/material checks.
import Foundation
import AppKit
import SceneKit
import Metal
let dir=URL(fileURLWithPath:CommandLine.arguments[1]);let c=try JSONSerialization.jsonObject(with:Data(contentsOf:dir.appendingPathComponent("interface.json"))) as! [String:Any];let masks=c["digit_masks"] as! [String:[String]]
for asset in c["assets"] as! [[String:Any]] where asset["kind"] as! String == "readout" {
 let root=asset["root"] as! String;let scene=try SCNScene(url:dir.appendingPathComponent(asset["filename"] as! String),options:nil);let digits=asset["digits"] as! [[String:Any]]
 let sample=root=="MissionTimer" ? "1005049":"0215"
 for (d,ch) in zip(digits,sample) {for (seg,name) in d["segments"] as! [String:String] {let node=scene.rootNode.childNode(withName:name,recursively:true)!;let material=SCNMaterial();material.lightingModel = .constant;material.diffuse.contents=masks[String(ch)]!.contains(seg) ? NSColor(calibratedRed:0.63,green:0.82,blue:0.60,alpha:1):NSColor(calibratedWhite:0.02,alpha:1);node.geometry!.materials=[material]}}
 let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=root=="MissionTimer" ? 0.022:0.025;camera.camera!.zNear=0.001;camera.position=SCNVector3(0,0,0.4);scene.rootNode.addChildNode(camera);camera.look(at:SCNVector3Zero);let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera;renderer.autoenablesDefaultLighting=true;scene.background.contents=NSColor.darkGray
 for hidden in [false,true] {scene.rootNode.childNode(withName:root+"_Lens",recursively:true)?.isHidden=hidden;let image=renderer.snapshot(atTime:0,with:CGSize(width:1200,height:400),antialiasingMode:.multisampling4X);let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!;try rep.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent("reviews/"+root+"-native-"+(hidden ? "without-lens":"with-lens")+".png"))}
}
