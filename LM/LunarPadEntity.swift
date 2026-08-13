import UIKit
import RealityKit

final class LunarPadEntity {
    let root = Entity()

    init() {
        root.name = "LunarPad"

        let discMesh = MeshResource.generateCylinder(height: 0.02, radius: 0.35)
        let discMaterial = SimpleMaterial(
            color: UIColor(red: 0.42, green: 0.41, blue: 0.38, alpha: 1),
            roughness: 0.85,
            isMetallic: false
        )
        let disc = ModelEntity(mesh: discMesh, materials: [discMaterial])
        disc.name = "PadSurface"
        disc.position = SIMD3(0, -0.01, 0)
        root.addChild(disc)

        let ringMesh = MeshResource.generateCylinder(height: 0.008, radius: 0.18)
        let ring = ModelEntity(
            mesh: ringMesh,
            materials: [UnlitMaterial(color: UIColor(red: 0.85, green: 0.78, blue: 0.45, alpha: 0.9))]
        )
        ring.name = "LandingRing"
        ring.position = SIMD3(0, 0.002, 0)
        root.addChild(ring)

        let collision = ShapeResource.generateBox(size: SIMD3(0.7, 0.04, 0.7))
        root.components.set(CollisionComponent(shapes: [collision]))
        root.components.set(InputTargetComponent())
        root.components.set(HoverEffectComponent())
    }
}
