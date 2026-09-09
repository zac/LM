import Foundation
import RealityKit
import simd

/// Source-qualified structural replacements. These never claim a functional slot.
@MainActor
struct LMCockpitConsoleEnclosure {
    enum Kind: String, CaseIterable { case instrument = "InstrumentConsole", lower = "LowerConsole", windows = "WindowSurrounds" }
    struct Pose: Decodable {
        let position_m: [Float]
        let rotation_quaternion_xyzw: [Float]
        let scale: [Float]
        func matrix() throws -> simd_float4x4 {
            // Native matrix decomposition carries Float roundoff (e.g. 0.99999988).
            // Preserve that measured scale in the matrix; reject actual rescaling.
            guard scale.count == 3, scale.allSatisfy({ $0.isFinite && abs($0 - 1) <= 0.000001 }) else {
                throw LMCommanderStationAssembly.AssemblyError.invalidContract("Enclosure scale")
            }
            var transform = try LMCommanderStationAssembly.Inventory.Pose(translation_m: position_m,
                quaternion_xyzw: rotation_quaternion_xyzw, scale: [1, 1, 1]).transform()
            transform.scale = SIMD3(scale[0], scale[1], scale[2])
            return transform.matrix
        }
    }
    struct Reference: Decodable { let component: String; let path: String; let pose: Pose }
    struct Group: Decodable { let path: String; let casts_shadows: Bool }
    struct Contract: Decodable {
        let schema: String; let component_id: String; let root: String
        let units: String; let parent_space: String; let root_pose: Pose
        let groups: [Group]; let suppressions: [Reference]; let protected_mounts: [Reference]
    }
    let kind: Kind
    let contract: Contract
    let root: Entity
    let castingGroups: [Entity]

    init(kind: Kind, asset: Entity, interfaceData: Data) throws {
        self.kind = kind
        contract = try JSONDecoder().decode(Contract.self, from: interfaceData)
        guard contract.schema == "lmkit.console-enclosure.v1", contract.component_id == kind.rawValue,
              contract.root == "/" + kind.rawValue, contract.units == "meters", contract.parent_space == "Cabin",
              LMCommanderStationAssembly.near(try contract.root_pose.matrix(), matrix_identity_float4x4),
              Set(contract.suppressions.map(\.path)) == Self.expectedSuppressions(kind),
              contract.suppressions.count == Self.expectedSuppressions(kind).count,
              Set(contract.protected_mounts.map(\.path)) == Self.expectedProtectedMounts(kind),
              contract.protected_mounts.count == Self.expectedProtectedMounts(kind).count else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Enclosure identity or replacement scope")
        }
        root = try LMCockpitComponentSupport.neutralRoot(kind.rawValue, asset: asset)
        let all = LMCommanderStationAssembly.descendants(root)
        for node in all {
            guard node.components[InputTargetComponent.self] == nil, node.components[CollisionComponent.self] == nil,
                  node.components[DirectionalLightComponent.self] == nil, node.components[PointLightComponent.self] == nil,
                  node.components[SpotLightComponent.self] == nil else {
                throw LMCommanderStationAssembly.AssemblyError.invalidContract("Interactive/lit enclosure")
            }
        }
        var covered = Set<ObjectIdentifier>()
        var casters: [Entity] = []
        guard !contract.groups.isEmpty else { throw LMCommanderStationAssembly.AssemblyError.invalidContract("Empty enclosure groups") }
        for group in contract.groups {
            let node = try LMCommanderStationAssembly.path(group.path, in: root)
            let descendants = LMCommanderStationAssembly.descendants(node)
            guard descendants.contains(where: { $0.components[ModelComponent.self] != nil }) else {
                throw LMCommanderStationAssembly.AssemblyError.invalidContract("Empty enclosure group")
            }
            for descendant in descendants {
                guard covered.insert(ObjectIdentifier(descendant)).inserted else {
                    throw LMCommanderStationAssembly.AssemblyError.invalidContract("Overlapping enclosure groups")
                }
            }
            if group.casts_shadows { casters.append(node) }
        }
        guard all.filter({ $0.components[ModelComponent.self] != nil }).allSatisfy({ covered.contains(ObjectIdentifier($0)) }),
              !casters.isEmpty, kind != .windows || contract.groups.allSatisfy(\.casts_shadows) else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Uncovered enclosure geometry or missing shell shadows")
        }
        castingGroups = casters
        LMCockpitComponentSupport.removeInput(root)
        LMCockpitMaterialPolicy.apply(.paintedStructure, to: root)
        for group in casters {
            for node in LMCommanderStationAssembly.descendants(group) where node.components[ModelComponent.self] != nil {
                node.components.set(DynamicLightShadowComponent(castsShadow: true))
            }
        }
    }

    static func expectedSuppressions(_ kind: Kind) -> Set<String> {
        switch kind {
        case .instrument: return [
            "/CommanderPanels/Panel_1/Panel_1_Shell",
            "/CommanderPanels/Panel_1/Panel_1_Trim",
            "/CommanderPanels/Panel_1/Panel_1_RemovableBacking",
            "/PanelInventory/Panels/Panel2/Frame",
            "/PanelInventory/Panels/Panel3/Frame",
            "/PanelInventory/Panels/Panel1/Panel1__FDAI/Placeholder",
            "/PanelInventory/Panels/Panel1/Panel1__Warning/Placeholder",
            "/PanelInventory/Panels/Panel1/Panel1__Timers/Placeholder",
            "/PanelInventory/Panels/Panel1/Panel1__CrossPointer/Placeholder",
            "/PanelInventory/Panels/Panel1/Panel1__Propulsion/Placeholder",
            "/PanelInventory/Panels/Panel1/Panel1__RangeThrust/Placeholder",
            "/PanelInventory/Panels/Panel1/Panel1__Guidance/Placeholder",
            "/PanelInventory/Panels/Panel2/Panel2__FDAI/Placeholder",
            "/PanelInventory/Panels/Panel2/Panel2__Caution/Placeholder",
            "/PanelInventory/Panels/Panel2/Panel2__RCSECS/Placeholder",
            "/PanelInventory/Panels/Panel2/Panel2__CrossPointer/Placeholder",
            "/PanelInventory/Panels/Panel2/Panel2__Systems/Placeholder",
            "/PanelInventory/Panels/Panel2/Panel2__Lower/Placeholder",
            "/PanelInventory/Panels/Panel3/Panel3__EngineRadar/Placeholder",
            "/PanelInventory/Panels/Panel3/Panel3__Stability/Placeholder",
            "/PanelInventory/Panels/Panel3/Panel3__TimerHeaters/Placeholder",
            "/PanelInventory/Panels/Panel3/Panel3__Lighting/Placeholder",
        ]
        case .lower: return [
            "/CommanderPanels/Panel_4/Panel_4_Shell",
            "/CommanderPanels/Panel_4/Panel_4_RemovableBacking",
            "/CommanderPanels/Panel_4/Panel_4_Trim",
            "/CommanderPanels/Panel_4/Panel_4_Fasteners",
        ]
        case .windows: return [
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Inboard_00",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Inboard_01",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Lower_00",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Lower_01",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Lower_02",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_00",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_01",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_02",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_03",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_04",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_05",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_06",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_07",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_08",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_09",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_10",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_11",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_12",
            "/Cabin/Shell/Cutaway_Forward/CDR_Front_Upper_13",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Inboard_00",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Inboard_01",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Lower_00",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Lower_01",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Lower_02",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_00",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_01",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_02",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_03",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_04",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_05",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_06",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_07",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_08",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_09",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_10",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_11",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_12",
            "/Cabin/Shell/Cutaway_Forward/LMP_Front_Upper_13",
        ]
        }
    }

    static func expectedProtectedMounts(_ kind: Kind) -> Set<String> {
        switch kind {
        case .instrument: return [
            "/PanelInventory/Panels/Panel1",
            "/PanelInventory/Panels/Panel1/Panel1__FDAI",
            "/PanelInventory/Panels/Panel1/Panel1__Warning",
            "/PanelInventory/Panels/Panel1/Panel1__Timers",
            "/PanelInventory/Panels/Panel1/Panel1__CrossPointer",
            "/PanelInventory/Panels/Panel1/Panel1__Propulsion",
            "/PanelInventory/Panels/Panel1/Panel1__RangeThrust",
            "/PanelInventory/Panels/Panel1/Panel1__Guidance",
            "/PanelInventory/Panels/Panel2",
            "/PanelInventory/Panels/Panel2/Panel2__FDAI",
            "/PanelInventory/Panels/Panel2/Panel2__Caution",
            "/PanelInventory/Panels/Panel2/Panel2__RCSECS",
            "/PanelInventory/Panels/Panel2/Panel2__CrossPointer",
            "/PanelInventory/Panels/Panel2/Panel2__Systems",
            "/PanelInventory/Panels/Panel2/Panel2__Lower",
            "/PanelInventory/Panels/Panel3",
            "/PanelInventory/Panels/Panel3/Panel3__EngineRadar",
            "/PanelInventory/Panels/Panel3/Panel3__Stability",
            "/PanelInventory/Panels/Panel3/Panel3__TimerHeaters",
            "/PanelInventory/Panels/Panel3/Panel3__Lighting",
            "/Cabin/Mounts/Mount_Panel_1",
            "/Cabin/Mounts/Mount_Panel_1/Mount_FDAI",
            "/Cabin/Mounts/Mount_Panel_2",
            "/Cabin/Mounts/Mount_Panel_3",
        ]
        case .lower: return [
            "/Cabin/Mounts/Mount_Panel_4",
            "/Cabin/Mounts/Mount_Panel_4/Mount_DSKY",
            "/Cabin/Mounts/Mount_Panel_5",
            "/PanelInventory/Panels/Panel5/Panel5__Engine",
            "/PanelInventory/Panels/Panel5/Panel5__Timer",
        ]
        case .windows: return [
            "/WindowsLPD/CDR_FlightWindow/CDR_Window_Inner",
            "/WindowsLPD/CDR_FlightWindow/CDR_Window_Outer",
            "/WindowsLPD/Datums/CDR_Eye",
            "/WindowsLPD/Datums/LMP_Eye",
            "/WindowsLPD/LMP_FlightWindow/LMP_Window_Inner",
            "/WindowsLPD/LMP_FlightWindow/LMP_Window_Outer",
        ]
        }
    }
}
