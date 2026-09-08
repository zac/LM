import Foundation
import RealityKit
import Testing
@testable import LMKit

private struct Inventory: Decodable {
    struct Pose: Decodable {
        let space: String
        let translation_m: [Float]
        let quaternion_xyzw: [Float]
        let scale: [Float]
        func transform() throws -> Transform {
            try #require(translation_m.count == 3 && quaternion_xyzw.count == 4 && scale.count == 3)
            return Transform(scale: SIMD3(scale[0], scale[1], scale[2]),
                rotation: simd_quatf(vector: SIMD4(quaternion_xyzw[0], quaternion_xyzw[1], quaternion_xyzw[2], quaternion_xyzw[3])),
                translation: SIMD3(translation_m[0], translation_m[1], translation_m[2]))
        }
    }
    struct Slot: Decodable {
        let id, node, default_placeholder_node, label_node: String
        let pose: Pose
        let replacement_allowed, physical_blank_omitted: Bool
        let installation_status: String?
    }
    struct Panel: Decodable { let node: String; let pose: Pose; let slots: [Slot] }
    let schema, units, root, planning_label_layer: String
    let root_pose: Pose
    let planning_labels_default_visible: Bool
    let panels: [Panel]
}

@MainActor private func path(_ path: String, root: Entity) throws -> Entity {
    let names = path.split(separator: "/").map(String.init)
    try #require(names.first == root.name)
    return try names.dropFirst().reduce(root) { parent, name in
        let children = parent.children.filter { $0.name == name }
        try #require(children.count == 1)
        return try #require(children.first)
    }
}

private func near(_ lhs: simd_float4x4, _ rhs: simd_float4x4) -> Bool {
    (0..<4).allSatisfy { simd_length(lhs[$0] - rhs[$0]) < 0.00001 }
}

@Test @MainActor func packagedInventoryPreservesSlotPosesAndBlockedReservations() throws {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Assets/Cockpit/Components/PanelInventory")
    for (url, name) in [(LMKitAssets.panelInventoryURL, "PanelInventory.usdz"),
                        (LMKitAssets.panelInventoryManifestURL, "inventory.json")] {
        #expect(try Data(contentsOf: url) == Data(contentsOf: source.appendingPathComponent(name)))
    }
    let manifest = try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: LMKitAssets.panelInventoryManifestURL))
    #expect(manifest.schema == "lmkit.panel-inventory.v1" && manifest.units == "meters")
    let scene = try Entity.load(contentsOf: LMKitAssets.panelInventoryURL)
    let root = try #require(scene.findEntity(named: "PanelInventory"))
    #expect(near(root.transformMatrix(relativeTo: scene.parent), try manifest.root_pose.transform().matrix))
    let labels = try path(manifest.planning_label_layer, root: root)
    #expect(!manifest.planning_labels_default_visible)
    // RealityKit does not map authored ancestor USD visibility to isEnabled.
    // Consumers must apply the explicit presentation intent when installing it.
    labels.isEnabled = manifest.planning_labels_default_visible
    #expect(!labels.isEnabled)
    let slots = manifest.panels.flatMap(\.slots)
    #expect(slots.count == 66 && Set(slots.map(\.id)).count == 66)
    #expect(manifest.panels.count == 28)
    for panel in manifest.panels {
        let entity = try path(panel.node, root: root)
        #expect(panel.pose.space == "Cabin-relative")
        #expect(near(entity.transformMatrix(relativeTo: root), try panel.pose.transform().matrix))
        for slot in panel.slots {
            let mount = try path(slot.node, root: root)
            let placeholder = try path(slot.default_placeholder_node, root: root)
            let label = try path(slot.label_node, root: root)
            #expect(slot.pose.space == "parent-local")
            #expect(near(mount.transformMatrix(relativeTo: entity), try slot.pose.transform().matrix))
            #expect(placeholder.parent === mount)
            let peerStates = mount.parent!.children.map { ($0, $0.isEnabled) }
            placeholder.isEnabled = false
            #expect(label.isEnabled)
            for (peer, enabled) in peerStates { #expect(peer.isEnabled == enabled) }
            placeholder.isEnabled = true
            if !slot.replacement_allowed {
                #expect(slot.id == "Panel5__Timer")
                #expect(slot.physical_blank_omitted && slot.installation_status == "blocked-by-ACA-clearance")
                #expect(placeholder.components[ModelComponent.self] == nil && placeholder.children.isEmpty)
            }
        }
    }
    labels.isEnabled = true
    #expect(slots.allSatisfy { (try? path($0.default_placeholder_node, root: root).isEnabled) == true })
}
