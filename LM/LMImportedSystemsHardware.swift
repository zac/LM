import Foundation
import LMKit
import RealityKit
import UIKit
import simd

/// Neutral hardware never implies availability of its historical electrical signal.
@MainActor
final class LMImportedSystemsHardware {
    let root: Entity
    let slot: String
    let pose: Transform
    init(asset: Entity, interfaceData: Data, kind: String) throws {
        let contract = try Self.json(interfaceData)
        if kind == "EngineButtons" {
            guard contract["schema"] as? String == "lmkit.engine-controls.v1",
                  let definition = (contract["components"] as? [[String: Any]])?.first(where: { $0["id"] as? String == kind }),
                  let placement = definition["placement"] as? [String: Any],
                  placement["parent"] as? String == "/PanelInventory/Panels/Panel5/Panel5__Engine" else { throw Self.invalid(kind) }
            root = try LMCockpitComponentSupport.neutralRoot("EngineButtons_Mount", asset: asset)
            slot = "Panel5__Engine"
            pose = try Self.pose(placement)
            guard LMCommanderStationAssembly.near(pose.matrix, matrix_identity_float4x4),
                  let neutral = definition["actuator_neutral"] as? [String: [String: Any]], neutral.count == 3 else { throw Self.invalid(kind) }
            for name in ["EngineButtons__StartActuator", "EngineButtons__StopActuator", "EngineButtons__StopResetLatch"] {
                let node = try LMCommanderStationAssembly.unique(name, in: root)
                guard let expected = neutral[name], LMCommanderStationAssembly.near(node.transform.matrix, try Self.pose(expected).matrix) else { throw Self.invalid(name) }
            }
            for name in ["EngineButtons__StartLightFace", "EngineButtons__StopLightFace"] {
                _ = try LMCommanderStationAssembly.unique(name, in: root)
            }
        } else {
            guard kind == "PropulsionInstruments", contract["schema"] as? String == "lmkit.propulsion-instruments.v1",
                  contract["root"] as? String == "/PropulsionInstruments",
                  let mounting = contract["mounting"] as? [String: Any], mounting["slot"] as? String == "Panel1__Propulsion",
                  let instruments = contract["instruments"] as? [String: [String: Any]] else { throw Self.invalid(kind) }
            root = try LMCockpitComponentSupport.neutralRoot(kind, asset: asset)
            slot = "Panel1__Propulsion"
            var placement = mounting
            placement["translation_m"] = mounting["slot_local_translation_m"]
            pose = try Self.pose(placement)
            guard simd_distance(pose.translation, [0, 0, 0.008]) < 0.00001,
                  abs(pose.rotation.real) > 0.99999 else { throw Self.invalid(kind) }
            var needleCount = 0, digitCount = 0
            for instrument in instruments.values {
                for needle in (instrument["needles"] as? [String: [String: Any]])?.values ?? [:].values {
                    guard let path = needle["node"] as? String, let parked = needle["parked_translation_m"] as? [Float] else { throw Self.invalid(kind) }
                    let node = try LMCommanderStationAssembly.path(path, in: root)
                    guard simd_distance(node.position, try LMCockpitComponentSupport.vector(parked)) < 0.00001 else { throw Self.invalid(path) }
                    node.isEnabled = false
                    needleCount += 1
                }
                for row in (instrument["rows"] as? [String: [String: Any]])?.values ?? [:].values {
                    guard let paths = row["digit_nodes"] as? [String], let segments = row["segment_children"] as? [String] else { throw Self.invalid(kind) }
                    for path in paths {
                        for segment in segments {
                            try LMCommanderStationAssembly.path(path + "/" + segment, in: root).isEnabled = false
                        }
                        digitCount += 1
                    }
                }
            }
            guard needleCount == 7, digitCount == 8 else { throw Self.invalid("Propulsion signal inventory") }
        }
        LMCockpitComponentSupport.removeInput(root)
    }
    static func json(_ data: Data) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], result["units"] as? String == "meters" else { throw invalid("Units") }
        return result
    }
    static func pose(_ data: [String: Any]) throws -> Transform {
        guard let position = data["translation_m"] as? [Float], let rotation = data["quaternion_xyzw"] as? [Float], rotation.count == 4,
              rotation.allSatisfy(\.isFinite), (data["scale"] as? [Float] ?? [1, 1, 1]) == [1, 1, 1] else { throw invalid("Pose") }
        let q = simd_quatf(vector: SIMD4(rotation[0], rotation[1], rotation[2], rotation[3]))
        guard abs(simd_length(q.vector) - 1) < 0.00001 else { throw invalid("Quaternion") }
        return Transform(rotation: q, translation: try LMCockpitComponentSupport.vector(position))
    }
    static func invalid(_ text: String) -> LMCommanderStationAssembly.AssemblyError { .invalidContract(text) }
}

@MainActor
final class LMImportedLunarContact {
    let root: Entity
    let instanceID: String
    let parentPath: String
    let slot: String?
    let pose: Transform
    private let faces: [Entity]
    private let offMaterials: [[any Material]]
    private(set) var probeContact: Bool?
    init(asset: Entity, interfaceData: Data, pilot: Bool) throws {
        let contract = try LMImportedSystemsHardware.json(interfaceData)
        let requestedID = pilot ? "PilotLunarContact" : "CommanderLunarContact"
        instanceID = requestedID
        guard contract["schema"] as? String == "lmkit.engine-controls.v1",
              let component = (contract["components"] as? [[String: Any]])?.first(where: { $0["id"] as? String == "LunarContact" }),
              let instance = (component["instances"] as? [[String: Any]])?.first(where: { $0["id"] as? String == requestedID }),
              let path = instance["parent"] as? String else { throw LMImportedSystemsHardware.invalid("Contact instance") }
        parentPath = path
        slot = instance["inventory_slot"] as? String
        pose = try LMImportedSystemsHardware.pose(instance)
        let expectedPath = pilot ? "/PanelInventory/Panels/Panel3/Panel3__Lighting" : "/PanelInventory/Panels/Panel1"
        let expectedPosition: SIMD3<Float> = pilot ? [0.078, 0.034, 0.0003] : [0.041, 0.099, 0.0003]
        guard path == expectedPath, slot == (pilot ? "Panel3__Lighting" : nil), simd_distance(pose.translation, expectedPosition) < 0.00001,
              abs(pose.rotation.real) > 0.99999 else { throw LMImportedSystemsHardware.invalid("Contact mounting") }
        root = try LMCockpitComponentSupport.neutralRoot("LunarContact_Mount", asset: asset)
        let face = try LMCommanderStationAssembly.unique("LunarContact__LightFace", in: root)
        faces = LMCommanderStationAssembly.descendants(face).filter { $0.components[ModelComponent.self] != nil }
        guard !faces.isEmpty else { throw LMImportedSystemsHardware.invalid("Contact face") }
        offMaterials = faces.map { $0.components[ModelComponent.self]!.materials }
        LMCockpitComponentSupport.removeInput(root)
    }
    /// Probe observation only; no modeled lamp power/test/stop-reset circuitry.
    func apply(_ value: Bool?) {
        probeContact = value
        for (index, face) in faces.enumerated() {
            guard var model = face.components[ModelComponent.self] else { continue }
            model.materials = value == true ? [UnlitMaterial(color: UIColor(red: 0.10, green: 0.36, blue: 1, alpha: 1))] : offMaterials[index]
            face.components.set(model)
        }
    }
}
