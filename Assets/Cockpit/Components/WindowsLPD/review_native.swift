// Small offscreen macOS SceneKit review of the delivered USDZ, not a headset check.
import Foundation
import AppKit
import SceneKit
import Metal
let base=URL(fileURLWithPath:CommandLine.arguments[1])
let scene=try SCNScene(url:base.appendingPathComponent("WindowsLPD.usdz"),options:nil)
let c=SIMD3<Float>(-0.6635188,1.6528591,-0.6746884)
let n=simd_normalize(SIMD3<Float>(0.5412868,0.4393564,0.7169201))
for name in ["LMP_FlightWindow","DockingWindow"] {scene.rootNode.childNode(withName:name,recursively:true)?.isHidden=true}
let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=0.46;camera.camera!.zNear=0.01;camera.simdPosition=c+n*1.2;scene.rootNode.addChildNode(camera);camera.look(at:SCNVector3(c))
let backing=SCNNode();backing.simdPosition=c-n*0.20;backing.simdOrientation=simd_quatf(from:SIMD3<Float>(0,0,1),to:n);scene.rootNode.addChildNode(backing)
for x in -4...4 {for y in -4...4 {let g=SCNPlane(width:0.10,height:0.10);let m=SCNMaterial();m.lightingModel = .constant;m.diffuse.contents=NSColor(white:(x+y)%2==0 ? 0.6:0.24,alpha:1);g.materials=[m];let p=SCNNode(geometry:g);p.position=SCNVector3(Float(x)*0.10,Float(y)*0.10,0);backing.addChildNode(p)}}
let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera;renderer.autoenablesDefaultLighting=true;scene.background.contents=NSColor.darkGray
for hidden in [false,true] {
 for name in ["CDR_Glazing_Inner","CDR_Glazing_Outer"] {scene.rootNode.childNode(withName:name,recursively:true)?.isHidden=hidden}
 let img=renderer.snapshot(atTime:0,with:CGSize(width:640,height:640),antialiasingMode:.multisampling4X)
 let rep=NSBitmapImageRep(data:img.tiffRepresentation!)!;try rep.representation(using:.png,properties:[:])!.write(to:base.appendingPathComponent("reviews/native-"+(hidden ? "without-glass":"with-glass")+".png"))
}
print("Native SceneKit comparison saved; independent RealityKit load validation is separate.")
