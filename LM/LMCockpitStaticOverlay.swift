import Foundation
import RealityKit

@MainActor
struct LMCockpitStaticOverlay {
    struct Slot: Decodable {
        let id: String
        let overlay_path: String
        let panel_pose: LMCommanderStationAssembly.Inventory.Pose
        let slot_pose: LMCommanderStationAssembly.Inventory.Pose
        let default_placeholder_node: String
        let replacement_allowed: Bool
    }
    private struct Mappings: Decodable { let slots: [Slot]? }
    let slots: [Slot]
    let root: Entity
    init(asset: Entity, interfaceData: Data, name: String, schema: String) throws {
        guard let contract = try JSONSerialization.jsonObject(with: interfaceData) as? [String: Any],
              contract["schema"] as? String == schema, contract["root"] as? String == "/" + name else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Optional overlay contract")
        }
        slots = try JSONDecoder().decode(Mappings.self, from: interfaceData).slots ?? []
        guard (name == "BreakerBanks" && slots.count == 9) || (name == "InteriorDetails" && slots.isEmpty) else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Overlay mapped slot count")
        }
        root = try LMCockpitComponentSupport.neutralRoot(name, asset: asset)
        for node in LMCommanderStationAssembly.descendants(root) {
            guard node.components[InputTargetComponent.self] == nil, node.components[CollisionComponent.self] == nil,
                  node.components[DirectionalLightComponent.self] == nil, node.components[PointLightComponent.self] == nil,
                  node.components[SpotLightComponent.self] == nil else {
                throw LMCommanderStationAssembly.AssemblyError.invalidContract("Interactive/lit static overlay")
            }
        }
        // Verify documented addressable groups before attaching the optional root.
        for group in contract["groups"] as? [[String: Any]] ?? [] {
            guard let path = group["path"] as? String else { throw LMCommanderStationAssembly.AssemblyError.invalidContract("Overlay group path") }
            _ = try LMCommanderStationAssembly.path(path, in: root)
        }
        for slot in contract["slots"] as? [[String: Any]] ?? [] {
            guard let path = slot["overlay_path"] as? String else { throw LMCommanderStationAssembly.AssemblyError.invalidContract("Overlay slot path") }
            _ = try LMCommanderStationAssembly.path(path, in: root)
        }
        LMCockpitComponentSupport.removeInput(root)
    }
}
