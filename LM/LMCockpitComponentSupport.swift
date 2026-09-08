import Foundation
import RealityKit
import simd

@MainActor
enum LMCockpitComponentSupport {
    static func neutralRoot(_ name: String, asset: Entity) throws -> Entity {
        let root = try LMCommanderStationAssembly.unique(name, in: asset)
        guard LMCommanderStationAssembly.near(root.transform.matrix, matrix_identity_float4x4),
              LMCommanderStationAssembly.near(root.transformMatrix(relativeTo: asset.parent), matrix_identity_float4x4),
              LMCommanderStationAssembly.descendants(root).contains(where: { $0.components[ModelComponent.self] != nil }) else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Non-neutral/empty component: \(name)")
        }
        root.removeFromParent()
        return root
    }
    static func vector(_ values: [Float]) throws -> SIMD3<Float> {
        guard values.count == 3, values.allSatisfy(\.isFinite) else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Component vector")
        }
        return SIMD3(values[0], values[1], values[2])
    }
    static func removeInput(_ root: Entity) {
        for entity in LMCommanderStationAssembly.descendants(root) {
            entity.components.remove(InputTargetComponent.self)
            entity.components.remove(CollisionComponent.self)
            entity.components.remove(HoverEffectComponent.self)
            if entity.components[ModelComponent.self] != nil {
                entity.components.set(DynamicLightShadowComponent(castsShadow: false))
            }
        }
    }
    /// Bounded legibility treatment for dial markings only. Preserve authored colors
    /// and textures; avoid making reflective housings or windows self-illuminating.
    static func readableMarkings(_ root: Entity) {
        for entity in LMCommanderStationAssembly.descendants(root) {
            guard var model = entity.components[ModelComponent.self] else { continue }
            model.materials = model.materials.map { material in
                guard let pbr = material as? PhysicallyBasedMaterial else { return material }
                var readable = UnlitMaterial()
                readable.color = .init(tint: pbr.baseColor.tint, texture: pbr.baseColor.texture)
                return readable
            }
            entity.components.set(model)
        }
    }
}
