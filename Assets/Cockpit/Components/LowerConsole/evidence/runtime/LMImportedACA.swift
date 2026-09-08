import Foundation
import LMKit
import RealityKit
import simd

/// Only this proxy (or the procedural fallback root) receives ACA gestures.
struct LMACAInteractionTarget: Component {}

@MainActor
final class LMImportedACA {
    let root: Entity
    let fixed: Entity
    let roll: Entity
    let yaw: Entity
    let pitch: Entity
    let interactionTarget = Entity()

    /// Existing pedestal center is pivot Y - .040, height .055. Seat the
    /// provisional housing bottom on its top. This is not a flight datum.
    static let registration = SIMD3<Float>(0, -0.040 + 0.055 / 2, 0)

    static func load() throws -> LMImportedACA {
        try LMImportedACA(asset: Entity.load(contentsOf: LMKitAssets.handControllerURL(.aca)),
                          interfaceData: Data(contentsOf: LMKitAssets.handControllerInterfacesURL))
    }

    init(asset: Entity, interfaceData: Data) throws {
        struct Manifest: Decodable {
            struct Node: Decodable {
                let name: String
                let parent: String
                let neutral_origin_m: [Float]
                let axis: String
                let motion: String
            }
            let entities: [Node]
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: interfaceData)
        root = try LMImportedDSKY.unique("ACA_Mount", in: asset)
        fixed = try LMImportedDSKY.unique("ACA_Fixed", in: root)
        roll = try LMImportedDSKY.unique("ACA_Roll", in: root)
        yaw = try LMImportedDSKY.unique("ACA_Yaw", in: root)
        pitch = try LMImportedDSKY.unique("ACA_Pitch", in: root)
        let expected: [(Entity, Entity, SIMD3<Float>, String)] = [
            (roll, root, [0, 0.061, 0], "Z"),
            (yaw, roll, [0, 0.062, 0], "Y"),
            (pitch, yaw, [0, 0.077, 0], "X")
        ]
        guard fixed.parent === root,
              simd_length(root.position) < 0.00001,
              simd_length(root.scale - SIMD3(repeating: 1)) < 0.00001,
              abs(root.orientation.real) > 0.99999 else {
            throw LMImportedDSKY.ContractError.invalidParent("ACA root/fixed")
        }
        for (node, parent, position, axis) in expected {
            let entries = manifest.entities.filter { $0.name == node.name }
            guard entries.count == 1, let entry = entries.first,
                  entry.parent == parent.name, entry.axis == axis, entry.motion == "rotation",
                  entry.neutral_origin_m.count == 3,
                  simd_distance(SIMD3(entry.neutral_origin_m[0], entry.neutral_origin_m[1], entry.neutral_origin_m[2]), position) < 0.00001,
                  node.parent === parent, simd_distance(node.position, position) < 0.00001,
                  simd_length(node.scale - SIMD3(repeating: 1)) < 0.00001,
                  abs(node.orientation.real) > 0.99999 else {
                throw LMImportedDSKY.ContractError.invalidParent(node.name)
            }
        }
        // One grip-sized proxy follows every articulated pivot. Imported mesh
        // children never add competing colliders or PTT behavior.
        for node in LMCommanderStationAssembly.descendants(root) {
            node.components.remove(CollisionComponent.self)
            node.components.remove(InputTargetComponent.self)
            node.components.remove(HoverEffectComponent.self)
        }
        interactionTarget.name = "ACA grip interaction proxy"
        interactionTarget.position = [0, 0.025, 0]
        interactionTarget.components.set(LMACAInteractionTarget())
        interactionTarget.components.set(InputTargetComponent())
        interactionTarget.components.set(HoverEffectComponent())
        interactionTarget.components.set(CollisionComponent(shapes: [.generateBox(size: [0.075, 0.11, 0.09])]))
        pitch.addChild(interactionTarget)
    }

    func apply(_ input: LMACANormalizedInput) {
        let travel = LMCommanderStationGeometry.acaProportionalTravelDegrees * .pi / 180
        // Preserve LM's established visual signs, in the authored local basis:
        // pitch +X (top crewward), yaw +Y, roll -Z (grip right).
        // These are presentation angles, not new AGC/vehicle-axis semantics.
        pitch.orientation = simd_quatf(angle: Float(input.clamped.pitch) * travel, axis: [1, 0, 0])
        yaw.orientation = simd_quatf(angle: Float(input.clamped.yaw) * travel, axis: [0, 1, 0])
        roll.orientation = simd_quatf(angle: -Float(input.clamped.roll) * travel, axis: [0, 0, 1])
    }
}
