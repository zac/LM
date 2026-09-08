import Foundation
import LMKit
import RealityKit
import simd

/// Detached, validated visual foundation. Spacecraft state and live instruments stay in LM.
@MainActor
final class LMCommanderStationAssembly {
    enum AssemblyError: Error { case invalidContract(String) }
    struct Manifest: Decodable {
        struct Mount: Decodable {
            let position: [Float]
            let rotation_x_degrees: Float
            let path: String
        }
        let units: String
        let coordinate_space: String
        let mounts: [String: Mount]
    }
    struct Inventory: Decodable {
        struct Pose: Decodable {
            let translation_m: [Float]
            let quaternion_xyzw: [Float]
            let scale: [Float]
            func transform() throws -> Transform {
                guard translation_m.count == 3, quaternion_xyzw.count == 4, scale == [1, 1, 1],
                      (translation_m + quaternion_xyzw).allSatisfy(\.isFinite) else {
                    throw AssemblyError.invalidContract("Inventory pose")
                }
                let q = simd_quatf(vector: SIMD4(quaternion_xyzw[0], quaternion_xyzw[1], quaternion_xyzw[2], quaternion_xyzw[3]))
                guard abs(simd_length(q.vector) - 1) < 0.00001 else {
                    throw AssemblyError.invalidContract("Inventory rotation")
                }
                return Transform(rotation: q, translation: SIMD3(translation_m[0], translation_m[1], translation_m[2]))
            }
        }
        struct Slot: Decodable {
            let id: String
            let node: String
            let pose: Pose
            let default_placeholder_node: String
            let label_node: String
            let external_occupant: String?
            let replacement_allowed: Bool
            let physical_blank_omitted: Bool
        }
        struct Panel: Decodable {
            let id: String
            let node: String
            let pose: Pose
            let slots: [Slot]
        }
        let schema: String
        let units: String
        let root: String
        let root_pose: Pose
        let planning_label_layer: String
        let panels: [Panel]
    }
    private struct WindowManifest: Decodable {
        struct Pane: Decodable {
            let position: [Float]
            let right: [Float]
            let up: [Float]
            let normal: [Float]
            let glass_path: String
        }
        let schema: String
        let units: String
        let root: String
        let pane_transforms: [String: Pane]
    }
    private struct Migration: Decodable {
        struct Removed: Decodable { let old_path: String }
        let removed_visual_nodes: [Removed]
        let new_cutaways: [String: String]
    }

    let root = Entity()
    let cabin: Entity
    let windows: Entity
    let panels: Entity
    let panelInventory: Entity
    let manifest: Manifest
    let inventory: Inventory
    private let planningLabels: Entity
    private var slots: [String: Inventory.Slot] = [:]
    private var installedSlots = Set<String>()
    private var installedPartialComponents = Set<String>()
    private(set) var slotOccupancy: [String: LMCockpitSlotOccupancy] = [:]
    private var planningLabelSources: [String: Entity] = [:]
    private var planningLabelBounds: [String: BoundingBox] = [:]
    private(set) var planningStatusLabels: [String: Entity] = [:]

    static func load() throws -> LMCommanderStationAssembly {
        try LMCommanderStationAssembly(asset: Entity.load(contentsOf: LMKitAssets.cabinURL),
            manifestData: Data(contentsOf: LMKitAssets.cabinMountsURL))
    }

    init(asset: Entity, manifestData: Data,
         loadPanels: @MainActor () throws -> Entity = { try Entity.load(contentsOf: LMKitAssets.commanderPanelsURL) },
         loadWindows: @MainActor () throws -> Entity = { try Entity.load(contentsOf: LMKitAssets.windowsURL) },
         loadInventory: @MainActor () throws -> Entity = { try Entity.load(contentsOf: LMKitAssets.panelInventoryURL) },
         inventoryData: Data? = nil, windowManifestData: Data? = nil,
         cabinInterfaceData: Data? = nil, windowInterfaceData: Data? = nil,
         migrationData: Data? = nil) throws {
        manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.units == "meters", manifest.coordinate_space.contains("NOT parent-local") else {
            throw AssemblyError.invalidContract("Mount coordinate space")
        }
        cabin = try Self.component("Cabin", from: asset)
        panels = try Self.component("CommanderPanels", from: loadPanels())
        windows = try Self.component("WindowsLPD", from: loadWindows())
        panelInventory = try Self.component("PanelInventory", from: loadInventory())
        inventory = try JSONDecoder().decode(Inventory.self,
            from: inventoryData ?? Data(contentsOf: LMKitAssets.panelInventoryManifestURL))
        guard inventory.schema == "lmkit.panel-inventory.v1", inventory.units == "meters",
              inventory.root == "/PanelInventory", Self.near(try inventory.root_pose.transform().matrix, matrix_identity_float4x4) else {
            throw AssemblyError.invalidContract("Inventory root")
        }
        planningLabels = try Self.path(inventory.planning_label_layer, in: panelInventory)
        root.name = "CommanderStationFoundation"
        // Each asset already uses Cabin coordinates. Siblings avoid ambiguous optical metadata.
        for component in [cabin, panels, windows, panelInventory] { root.addChild(component) }
        for (name, mount) in manifest.mounts {
            let entity = try Self.path(mount.path, in: cabin)
            guard entity.name == name, mount.position.count == 3 else {
                throw AssemblyError.invalidContract(name)
            }
            let expected = Transform(rotation: simd_quatf(angle: mount.rotation_x_degrees * .pi / 180, axis: [1, 0, 0]),
                translation: SIMD3(mount.position[0], mount.position[1], mount.position[2]))
            guard Self.near(entity.transformMatrix(relativeTo: cabin), expected.matrix) else {
                throw AssemblyError.invalidContract("Root-relative mount mismatch: \(name)")
            }
        }
        let migration = try JSONDecoder().decode(Migration.self,
            from: migrationData ?? Data(contentsOf: LMKitAssets.cabinMigrationURL))
        for removed in migration.removed_visual_nodes {
            if (try? Self.path(removed.old_path, in: cabin)) != nil {
                throw AssemblyError.invalidContract("Old cabin visual survives: \(removed.old_path)")
            }
        }
        for path in migration.new_cutaways.values {
            try Self.path(path, in: cabin).isEnabled = true
        }
        try Self.path("/Cabin/Shell/Hatches", in: cabin).isEnabled = true
        let lpd = LMLandingPointDesignator()
        let eye = try Self.path("/Cabin/Optical/CDR_Eye", in: cabin)
        guard simd_distance(eye.position(relativeTo: cabin), lpd.commanderEyeMeters) < 0.00001 else {
            throw AssemblyError.invalidContract("CDR eye")
        }
        let windowManifest = try JSONDecoder().decode(WindowManifest.self,
            from: windowManifestData ?? Data(contentsOf: LMKitAssets.windowManifestURL))
        guard windowManifest.schema == "lmkit.windows-lpd.manifest.v1", windowManifest.units == "meters",
              windowManifest.root == "/WindowsLPD", Set(windowManifest.pane_transforms.keys) == ["CDR_Window_Inner", "CDR_Window_Outer", "LMP_Window_Inner", "LMP_Window_Outer"] else {
            throw AssemblyError.invalidContract("Window manifest")
        }
        for (name, pane) in windowManifest.pane_transforms {
            let glass = try Self.path(pane.glass_path, in: windows)
            guard let node = glass.parent, node.name == name,
                  Self.matches(node, relativeTo: windows, position: pane.position, right: pane.right, up: pane.up, normal: pane.normal),
                  Self.descendants(glass).contains(where: { $0.components[ModelComponent.self] != nil }) else {
                throw AssemblyError.invalidContract("Window pane: \(name)")
            }
        }
        for pane in LMLPDPane.allCases {
            let suffix = pane == .inner ? "Inner" : "Outer"
            let node = try Self.path("/WindowsLPD/CDR_FlightWindow/CDR_Window_\(suffix)", in: windows)
            let metadata = try Self.path("/Cabin/Optical/CDR_Window_\(suffix)", in: cabin)
            // Outer metadata uses a ray-projected point; Windows uses a normal-offset
            // origin. They must describe the same plane, not the same tangent point.
            let normal = node.orientation(relativeTo: windows).act(SIMD3<Float>(0, 0, 1))
            guard abs(simd_dot(node.position(relativeTo: windows) - metadata.position(relativeTo: cabin), normal)) < 0.00001,
                  abs(simd_dot(node.position(relativeTo: windows) - lpd.windowCorners(on: pane)[0], normal)) < 0.00001,
                  simd_distance(normal, metadata.orientation(relativeTo: cabin).act([0, 0, 1])) < 0.00001,
                  simd_distance(normal, lpd.paneOrientation(pane).act([0, 0, 1])) < 0.00001 else {
                throw AssemblyError.invalidContract("CDR pane registration")
            }
            let marks = try Self.path("/WindowsLPD/CDR_FlightWindow/CDR_Window_\(suffix)/LPD_\(suffix)", in: windows)
            guard Self.descendants(marks).contains(where: { $0.components[ModelComponent.self] != nil }) else {
                throw AssemblyError.invalidContract("Missing imported LPD geometry")
            }
        }
        try Self.validateInterfaces(cabin: cabin, windows: windows,
            cabinData: cabinInterfaceData ?? Data(contentsOf: LMKitAssets.cabinInterfaceURL),
            windowData: windowInterfaceData ?? Data(contentsOf: LMKitAssets.windowInterfacesURL))
        for name in ["DSKY", "FDAI"] {
            let interface = try Self.unique(name + "_Interface", in: panels)
            let reservation = try Self.unique("Mount_" + name, in: cabin)
            guard interface.children.isEmpty, interface.components[ModelComponent.self] == nil,
                  Self.near(interface.transformMatrix(relativeTo: panels), reservation.transformMatrix(relativeTo: cabin)) else {
                throw AssemblyError.invalidContract("Commander panel interface: \(name)")
            }
        }
        guard !Self.descendants(root).contains(where: { $0.name == "DSKY_Key_PRO" || $0.name == "FDAI_Ball_Pivot" }) else {
            throw AssemblyError.invalidContract("Duplicate live instruments")
        }
        for panel in inventory.panels {
            let panelNode = try Self.path(panel.node, in: panelInventory)
            guard Self.near(panelNode.transformMatrix(relativeTo: panelInventory), try panel.pose.transform().matrix) else {
                throw AssemblyError.invalidContract("Panel pose: \(panel.id)")
            }
            for slot in panel.slots {
                guard slots[slot.id] == nil else { throw AssemblyError.invalidContract("Duplicate slot: \(slot.id)") }
                let node = try Self.path(slot.node, in: panelInventory)
                let placeholder = try Self.path(slot.default_placeholder_node, in: panelInventory)
                let label = try Self.path(slot.label_node, in: panelInventory)
                planningLabelSources[slot.id] = label
                planningLabelBounds[slot.id] = label.visualBounds(relativeTo: label)
                guard node.parent === panelNode, placeholder.parent === node,
                      Self.isDescendant(label, of: planningLabels),
                      Self.near(node.transformMatrix(relativeTo: panelNode), try slot.pose.transform().matrix),
                      slot.physical_blank_omitted == !Self.descendants(placeholder).contains(where: { $0.components[ModelComponent.self] != nil }) else {
                    throw AssemblyError.invalidContract("Slot hierarchy or blank: \(slot.id)")
                }
                slots[slot.id] = slot
            }
        }
        guard let timer = slots["Panel5__Timer"], !timer.replacement_allowed, timer.physical_blank_omitted else {
            throw AssemblyError.invalidContract("Panel 5 timer clearance block")
        }
        // Inventory owns these blank surfaces; retain the separate shell, fasteners
        // and aperture collars. Both layers otherwise occupy the same face plane.
        for index in [1, 4] {
            try Self.path("/CommanderPanels/Panel_\(index)/Panel_\(index)_RemovableBacking", in: panels).isEnabled = false
        }
        LMCockpitMaterialPolicy.apply(.paintedStructure, to: cabin)
        LMCockpitMaterialPolicy.apply(.paintedStructure, to: panels)
        LMCockpitMaterialPolicy.apply(.paintedStructure, to: try Self.path("/PanelInventory/Panels", in: panelInventory))
        planningLabels.isEnabled = false
        Self.removeInput(in: root)
        Self.noShadows(in: root)
    }

    func setPlanningLabelsVisible(_ visible: Bool) { planningLabels.isEnabled = visible }
    var planningLabelsVisible: Bool { planningLabels.isEnabled }

    /// Existing live instrument has passed its binder; hide only its own reservation.
    func confirmExternalOccupant(slotID: String, occupantName: String) throws {
        guard let slot = slots[slotID], slot.replacement_allowed, slot.external_occupant == occupantName else {
            throw AssemblyError.invalidContract("External occupant: \(slotID)")
        }
        try Self.path(slot.default_placeholder_node, in: panelInventory).isEnabled = false
        installedSlots.insert(slotID)
        recordOccupancy(slotID: slotID, occupancy: .init(coverage: .occupiedRegion, componentIDs: [occupantName], note: nil))
    }

    /// Future component installation is transactional per slot, including load/validation failures.
    func installOccupant(slotID: String, componentID: String = "Equipment", loadAndValidate: @MainActor () throws -> Entity) throws {
        guard let slot = slots[slotID], slot.replacement_allowed, slot.external_occupant == nil,
              !installedSlots.contains(slotID) else {
            throw AssemblyError.invalidContract("Unavailable or blocked slot: \(slotID)")
        }
        let mount = try Self.path(slot.node, in: panelInventory)
        let placeholder = try Self.path(slot.default_placeholder_node, in: panelInventory)
        let occupant = try loadAndValidate()
        guard occupant.parent == nil, Self.near(occupant.transform.matrix, matrix_identity_float4x4),
              Self.descendants(occupant).contains(where: { $0.components[ModelComponent.self] != nil }) else {
            throw AssemblyError.invalidContract("Non-neutral or empty slot occupant")
        }
        mount.addChild(occupant)
        placeholder.isEnabled = false
        installedSlots.insert(slotID)
        recordOccupancy(slotID: slotID, occupancy: .init(coverage: .occupiedRegion, componentIDs: [componentID], note: nil))
    }

    /// Validate every mapped datum before publishing a multi-slot overlay or hiding blanks.
    func installStaticOverlay(_ overlay: LMCockpitStaticOverlay) throws {
        guard overlay.root.parent == nil, Self.near(overlay.root.transform.matrix, matrix_identity_float4x4),
              Set(overlay.slots.map(\.id)).count == overlay.slots.count else {
            throw AssemblyError.invalidContract("Static overlay root or duplicate slots")
        }
        var placeholders: [Entity] = []
        for mapped in overlay.slots {
            guard let slot = slots[mapped.id], slot.replacement_allowed, mapped.replacement_allowed,
                  slot.external_occupant == nil, !installedSlots.contains(slot.id),
                  slot.default_placeholder_node == mapped.default_placeholder_node else {
                throw AssemblyError.invalidContract("Static overlay slot ownership")
            }
            let live = try Self.path(slot.node, in: panelInventory)
            let authored = try Self.path(mapped.overlay_path, in: overlay.root)
            let expected = try mapped.panel_pose.transform().matrix * mapped.slot_pose.transform().matrix
            guard let livePanel = live.parent, let authoredPanel = authored.parent,
                  Self.near(livePanel.transformMatrix(relativeTo: panelInventory), try mapped.panel_pose.transform().matrix),
                  Self.near(authoredPanel.transformMatrix(relativeTo: overlay.root), try mapped.panel_pose.transform().matrix),
                  Self.near(live.transform.matrix, try mapped.slot_pose.transform().matrix),
                  Self.near(authored.transform.matrix, try mapped.slot_pose.transform().matrix),
                  Self.near(live.transformMatrix(relativeTo: panelInventory), expected),
                  Self.near(authored.transformMatrix(relativeTo: overlay.root), expected) else {
                throw AssemblyError.invalidContract("Static overlay mapped datum: \(slot.id)")
            }
            placeholders.append(try Self.path(slot.default_placeholder_node, in: panelInventory))
        }
        root.addChild(overlay.root)
        for placeholder in placeholders { placeholder.isEnabled = false }
        installedSlots.formUnion(overlay.slots.map(\.id))
        for mapped in overlay.slots {
            recordOccupancy(slotID: mapped.id, occupancy: .init(coverage: .occupiedRegion,
                componentIDs: [overlay.root.name], note: "Visual hardware only"))
        }
    }

    /// Partial equipment leaves the original neutral region backing in place.
    /// A failed optional component cannot remove a peer or publish an empty slot.
    func installPartialOccupant(slotID: String, componentID: String,
                                pose: Transform = Transform(), backingMaterial: (any Material)? = nil,
                                loadAndValidate: @MainActor () throws -> Entity) throws {
        guard let slot = slots[slotID], slot.replacement_allowed, slot.external_occupant == nil,
              !installedSlots.contains(slotID), !installedPartialComponents.contains(componentID),
              pose.translation.x.isFinite, pose.translation.y.isFinite, pose.translation.z.isFinite,
              pose.rotation.vector.x.isFinite, pose.rotation.vector.y.isFinite,
              pose.rotation.vector.z.isFinite, pose.rotation.vector.w.isFinite,
              abs(simd_length(pose.rotation.vector) - 1) < 0.00001,
              simd_distance(pose.scale, SIMD3<Float>(repeating: 1)) < 0.00001 else {
            throw AssemblyError.invalidContract("Unavailable partial slot: \(slotID)")
        }
        let mount = try Self.path(slot.node, in: panelInventory)
        let occupant = try loadAndValidate()
        guard occupant.parent == nil, Self.near(occupant.transform.matrix, matrix_identity_float4x4),
              Self.descendants(occupant).contains(where: { $0.components[ModelComponent.self] != nil }) else {
            throw AssemblyError.invalidContract("Non-neutral or empty partial occupant")
        }
        let backing = try Self.path(slot.default_placeholder_node, in: panelInventory)
        occupant.transform = pose
        mount.addChild(occupant)
        if let backingMaterial {
            for node in Self.descendants(backing) {
                guard var model = node.components[ModelComponent.self] else { continue }
                model.materials = model.materials.map { _ in backingMaterial }
                node.components.set(model)
            }
        }
        installedPartialComponents.insert(componentID)
        installedSlots.insert(slotID)
        recordOccupancy(slotID: slotID, occupancy: .init(coverage: .partialRegion, componentIDs: [componentID], note: nil))
    }

    /// Called only after the corresponding installer has completed validation.
    /// Complementary installers can publish all registered component IDs here;
    /// this metadata method deliberately does not grant installation permission.
    func recordOccupancy(slotID: String, occupancy: LMCockpitSlotOccupancy) {
        slotOccupancy[slotID] = occupancy
        guard let source = planningLabelSources[slotID], let parent = source.parent,
              let sourceBounds = planningLabelBounds[slotID] else { return }
        let mesh = MeshResource.generateText(occupancy.planningText, extrusionDepth: 0,
            font: .monospacedSystemFont(ofSize: 0.008, weight: .medium),
            containerFrame: .zero, alignment: .center, lineBreakMode: .byWordWrapping)
        let materials = Self.descendants(source).compactMap { $0.components[ModelComponent.self] }.first?.materials ?? []
        let text = ModelEntity(mesh: mesh, materials: materials)
        let bounds = text.visualBounds(relativeTo: text)
        let scale = min(1, min(max(sourceBounds.extents.x, 0.025) / max(bounds.extents.x, 0.001),
                               max(sourceBounds.extents.y, 0.020) / max(bounds.extents.y, 0.001)))
        text.scale = SIMD3(repeating: scale)
        text.position = sourceBounds.center - bounds.center * scale
        // Planning-only annotation clears raised instrument faces; hardware and
        // the original authored label datum remain unchanged.
        text.position.z += 0.10
        let replacement = Entity()
        replacement.name = "PlanningStatus__" + slotID
        replacement.transform = source.transform
        replacement.addChild(text)
        LMCockpitComponentSupport.readableMarkings(replacement)
        Self.removeInput(in: replacement)
        Self.noShadows(in: replacement)
        planningStatusLabels[slotID]?.removeFromParent()
        parent.addChild(replacement)
        source.isEnabled = false
        planningStatusLabels[slotID] = replacement
    }

    private static func validateInterfaces(cabin: Entity, windows: Entity, cabinData: Data, windowData: Data) throws {
        guard let a = try JSONSerialization.jsonObject(with: cabinData) as? [String: Any],
              let b = try JSONSerialization.jsonObject(with: windowData) as? [String: Any],
              a["schema"] as? String == "lmkit.cabin-foundation.interface.v2",
              b["schema"] as? String == "lmkit.windows-lpd.interface.v1",
              let openings = a["openings"] as? NSDictionary, let forward = b["forward"] as? NSDictionary,
              openings == forward, let docking = a["docking"] as? NSDictionary,
              let windowDocking = b["docking"] as? NSDictionary, docking == windowDocking,
              let center = (docking["center"] as? [NSNumber])?.map(\.floatValue), let right = (docking["right"] as? [NSNumber])?.map(\.floatValue),
              let up = (docking["up"] as? [NSNumber])?.map(\.floatValue), let normal = (docking["normal_toward_cabin"] as? [NSNumber])?.map(\.floatValue) else {
            throw AssemblyError.invalidContract("Cabin/Windows interface agreement")
        }
        let dockingNode = try path("/WindowsLPD/DockingWindow", in: windows)
        guard matches(dockingNode, relativeTo: windows, position: center, right: right, up: up, normal: normal) else {
            throw AssemblyError.invalidContract("Docking basis")
        }
    }
    private static func matches(_ node: Entity, relativeTo root: Entity, position: [Float], right: [Float], up: [Float], normal: [Float]) -> Bool {
        let values = [position, right, up, normal]
        guard values.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }) else { return false }
        let vectors = values.map { SIMD3($0[0], $0[1], $0[2]) }
        return simd_distance(node.scale(relativeTo: root), SIMD3<Float>(repeating: 1)) < 0.00001
            && simd_distance(node.position(relativeTo: root), vectors[0]) < 0.00001
            && zip([SIMD3<Float>(1, 0, 0), [0, 1, 0], [0, 0, 1]], vectors.dropFirst()).allSatisfy {
                simd_distance(node.orientation(relativeTo: root).act($0), $1) < 0.00001
            }
    }
    private static func component(_ name: String, from asset: Entity) throws -> Entity {
        let component = try unique(name, in: asset)
        guard near(component.transformMatrix(relativeTo: asset.parent), matrix_identity_float4x4),
              near(component.transform.matrix, matrix_identity_float4x4) else {
            throw AssemblyError.invalidContract("Non-neutral component: \(name)")
        }
        component.removeFromParent()
        return component
    }
    static func path(_ path: String, in root: Entity) throws -> Entity {
        let names = path.split(separator: "/").map(String.init)
        guard names.first == root.name else { throw AssemblyError.invalidContract(path) }
        return try names.dropFirst().reduce(root) { parent, name in
            let matches = parent.children.filter { $0.name == name }
            guard matches.count == 1, let node = matches.first else { throw AssemblyError.invalidContract(path) }
            return node
        }
    }
    static func unique(_ name: String, in root: Entity) throws -> Entity {
        let matches = descendants(root).filter { $0.name == name }
        guard matches.count == 1, let entity = matches.first else { throw AssemblyError.invalidContract(name) }
        return entity
    }
    static func descendants(_ root: Entity) -> [Entity] { [root] + root.children.flatMap { descendants($0) } }
    static func near(_ lhs: simd_float4x4, _ rhs: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { simd_length(lhs[$0] - rhs[$0]) < 0.00001 }
    }
    private static func isDescendant(_ node: Entity, of ancestor: Entity) -> Bool {
        var candidate: Entity? = node
        while let current = candidate { if current === ancestor { return true }; candidate = current.parent }
        return false
    }
    private static func removeInput(in root: Entity) {
        for entity in descendants(root) {
            entity.components.remove(InputTargetComponent.self)
            entity.components.remove(CollisionComponent.self)
            entity.components.remove(HoverEffectComponent.self)
        }
    }
    private static func noShadows(in root: Entity) {
        for entity in descendants(root) where entity.components[ModelComponent.self] != nil {
            entity.components.set(DynamicLightShadowComponent(castsShadow: false))
        }
    }
}
