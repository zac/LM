import RealityKit

/// Local surface presentation only. Does not change mission lights, exposure,
/// instrument state, authored color/texture, glazing or physical transforms.
@MainActor
enum LMCockpitMaterialPolicy {
    enum Treatment: Equatable {
        case paintedStructure
        case attitudeBall
        case printedFace
        case fixedMarking
    }

    @discardableResult
    static func apply(_ treatment: Treatment, to root: Entity) -> Int {
        var changed = 0
        if var model = root.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                switch treatment {
                case .paintedStructure:
                    pbr.roughness.scale = max(pbr.roughness.scale, 0.9)
                    pbr.specular.scale = min(pbr.specular.scale, 0.08)
                case .attitudeBall:
                    // Preserve the dark hemisphere and fine printed lines.
                    // Emissive fill washes them gray in the native renderer.
                    pbr.roughness.scale = max(pbr.roughness.scale, 0.8)
                    pbr.specular.scale = min(pbr.specular.scale, 0.08)
                    pbr.emissiveColor = .init(color: .black)
                    pbr.emissiveIntensity = 0
                case .printedFace, .fixedMarking:
                    pbr.roughness.scale = max(pbr.roughness.scale, 0.8)
                    pbr.specular.scale = min(pbr.specular.scale, 0.08)
                    pbr.emissiveColor = .init(color: pbr.baseColor.tint)
                    pbr.emissiveColor.texture = pbr.baseColor.texture
                    pbr.emissiveIntensity = treatment == .printedFace ? 0.20 : 0.35
                }
                changed += 1
                return pbr
            }
            root.components.set(model)
        }
        for child in root.children { changed += apply(treatment, to: child) }
        return changed
    }

    @discardableResult
    static func apply(_ treatment: Treatment, in root: Entity,
                      matching predicate: (String) -> Bool) -> Int {
        if predicate(root.name) { return apply(treatment, to: root) }
        return root.children.reduce(0) { $0 + apply(treatment, in: $1, matching: predicate) }
    }
}
