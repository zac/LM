import Foundation
import LMKit
import RealityKit
import simd

@MainActor
final class LMImportedCrossPointer {
    struct Contract: Decodable {
        struct Mounting: Decodable { let slot_id: String }
        struct Mode: Decodable { let id: String; let full_scale_abs_fps: Double }
        struct Needle: Decodable { let node: String; let neutral_translation_m: [Float]; let travel_axis: [Float]; let travel_m: [Float] }
        struct Needles: Decodable { let group: String; let lateral: Needle; let forward: Needle }
        struct Scale: Decodable { let multiplier_x10_node: String; let multiplier_x_point_1_node: String }
        let schema: String
        let units: String
        let root: String
        let root_pose: LMCommanderStationAssembly.Inventory.Pose
        let mounting: Mounting
        let supported_mode: Mode
        let needles: Needles
        let scale: Scale
    }
    let root: Entity
    let group: Entity
    let lateral: Entity
    let forward: Entity
    let contract: Contract
    private let lateralOrigin: SIMD3<Float>
    private let forwardOrigin: SIMD3<Float>
    private(set) var reading: LMCrossPointerReading?

    static func load() throws -> LMImportedCrossPointer {
        try .init(asset: Entity.load(contentsOf: LMKitAssets.crossPointerURL),
                  interfaceData: Data(contentsOf: LMKitAssets.crossPointerInterfaceURL))
    }
    init(asset: Entity, interfaceData: Data) throws {
        contract = try JSONDecoder().decode(Contract.self, from: interfaceData)
        guard contract.schema == "lmkit.cross-pointer.v1", contract.units == "meters", contract.root == "/CrossPointer",
              contract.mounting.slot_id == "Panel1__CrossPointer",
              contract.supported_mode.id == "simulation-horizontal-velocity-lo-mult-later-fly-to",
              contract.supported_mode.full_scale_abs_fps == 20,
              contract.needles.lateral.travel_axis == [1, 0, 0], contract.needles.forward.travel_axis == [0, 1, 0],
              contract.needles.lateral.travel_m == [-0.016, 0.016], contract.needles.forward.travel_m == [-0.016, 0.016],
              LMCommanderStationAssembly.near(try contract.root_pose.transform().matrix, matrix_identity_float4x4) else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Cross-pointer contract")
        }
        root = try LMCockpitComponentSupport.neutralRoot("CrossPointer", asset: asset)
        group = try LMCommanderStationAssembly.path(contract.needles.group, in: root)
        lateral = try LMCommanderStationAssembly.path(contract.needles.lateral.node, in: root)
        forward = try LMCommanderStationAssembly.path(contract.needles.forward.node, in: root)
        lateralOrigin = try LMCockpitComponentSupport.vector(contract.needles.lateral.neutral_translation_m)
        forwardOrigin = try LMCockpitComponentSupport.vector(contract.needles.forward.neutral_translation_m)
        guard lateral.parent === group, forward.parent === group,
              simd_distance(lateral.position, lateralOrigin) < 0.00001,
              simd_distance(forward.position, forwardOrigin) < 0.00001 else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Cross-pointer needle origin")
        }
        for path in [contract.scale.multiplier_x10_node, contract.scale.multiplier_x_point_1_node,
                     "/CrossPointer/Fixed/PowerFailureFlag"] {
            try LMCommanderStationAssembly.path(path, in: root).isEnabled = false
        }
        LMCockpitComponentSupport.removeInput(root)
        LMCockpitComponentSupport.readableMarkings(group)
        LMCockpitComponentSupport.readableMarkings(try LMCommanderStationAssembly.path("/CrossPointer/Fixed/Legends", in: root))
        apply(nil)
    }
    func apply(_ reading: LMCrossPointerReading?) {
        self.reading = reading
        group.isEnabled = reading != nil
        guard let reading else { return }
        lateral.position = lateralOrigin + SIMD3(0.016 * reading.lateralFraction, 0, 0)
        forward.position = forwardOrigin + SIMD3(0, 0.016 * reading.forwardFraction, 0)
    }
}
