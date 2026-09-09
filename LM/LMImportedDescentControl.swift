import Foundation
import LMKit
import RealityKit
import simd

struct LMDescentRateInteractionTarget: Component {}
struct LMAttitudeModeInteractionTarget: Component {}

@MainActor
final class LMImportedDescentControl {
    enum Kind: String { case attitudeMode = "AttitudeMode", descentRate = "DescentRate" }
    struct Contract: Decodable {
        struct State: Decodable {
            let angle_degrees: Float
            let runtime_value: String?
            let runtime_intent: String?
            let supported: Bool
            let id: String?
        }
        struct Control: Decodable {
            let id: String
            let mount: String
            let slot: String
            let actuator: String
            let actuator_neutral_position_m: [Float]
            let rotation_reference_quaternion_xyzw: [Float]
            let exported_neutral_quaternion_xyzw: [Float]
            let neutral_backing: String
            let states: [State]
        }
        let schema: String
        let units: String
        let components: [Control]
    }
    let kind: Kind
    let root: Entity
    let actuator: Entity
    let target = Entity()
    let definition: Contract.Control
    let backingMaterials: [any Material]
    private let rotationReference: simd_quatf
    private let neutralPosition: SIMD3<Float>

    static func load(_ kind: Kind) throws -> LMImportedDescentControl {
        try .init(kind: kind,
                  asset: Entity.load(contentsOf: kind == .attitudeMode ? LMKitAssets.attitudeModeURL : LMKitAssets.descentRateURL),
                  interfaceData: Data(contentsOf: LMKitAssets.descentControlsInterfaceURL))
    }
    init(kind: Kind, asset: Entity, interfaceData: Data) throws {
        self.kind = kind
        let manifest = try JSONDecoder().decode(Contract.self, from: interfaceData)
        let definitions = manifest.components.filter { $0.id == kind.rawValue }
        guard manifest.schema == "lmkit.descent-controls.v1", manifest.units == "meters",
              definitions.count == 1, let definition = definitions.first,
              definition.slot == (kind == .attitudeMode ? "Panel3__Stability" : "Panel5__Engine") else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Descent control contract")
        }
        self.definition = definition
        root = try LMCockpitComponentSupport.neutralRoot(definition.mount, asset: asset)
        actuator = try LMCommanderStationAssembly.unique(definition.actuator, in: root)
        neutralPosition = try LMCockpitComponentSupport.vector(definition.actuator_neutral_position_m)
        rotationReference = try Self.quaternion(definition.rotation_reference_quaternion_xyzw)
        let exported = try Self.quaternion(definition.exported_neutral_quaternion_xyzw)
        guard actuator.parent === root, simd_distance(actuator.position, neutralPosition) < 0.00001,
              abs(simd_dot(actuator.orientation.vector, exported.vector)) > 0.99999,
              simd_distance(actuator.scale, SIMD3<Float>(repeating: 1)) < 0.00001,
              definition.states.allSatisfy({ $0.angle_degrees.isFinite && abs($0.angle_degrees) <= 17.001 }) else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Descent control neutral pose")
        }
        if kind == .attitudeMode {
            guard definition.states.contains(where: { $0.runtime_value == "automatic" && $0.supported && $0.angle_degrees == -17 }),
                  definition.states.contains(where: { $0.runtime_value == "attitudeHold" && $0.supported && $0.angle_degrees == 0 }),
                  definition.states.contains(where: { !$0.supported && $0.angle_degrees == 17 }) else {
                throw LMCommanderStationAssembly.AssemblyError.invalidContract("Mode states")
            }
        } else {
            guard definition.states.contains(where: { $0.runtime_intent == "descendPlus" && $0.angle_degrees == -17 }),
                  definition.states.contains(where: { $0.runtime_intent == "descendMinus" && $0.angle_degrees == 17 }),
                  definition.states.contains(where: { $0.id == "center" && $0.angle_degrees == 0 }) else {
                throw LMCommanderStationAssembly.AssemblyError.invalidContract("DES RATE states")
            }
        }
        // Both are partial-region components. Keep inventory backing and remove
        // only the supplied duplicate neutral backing, never its upright/support.
        let backing = try LMCommanderStationAssembly.unique(definition.neutral_backing, in: root)
        // Direct cockpit light can wash a pale PBR region to white. Preserve the
        // authored mode face color independently so its white legends stay legible.
        if kind == .attitudeMode { LMCockpitComponentSupport.readableMarkings(backing) }
        backingMaterials = LMCommanderStationAssembly.descendants(backing).compactMap { $0.components[ModelComponent.self] }.flatMap(\.materials)
        guard !backingMaterials.isEmpty else { throw LMCommanderStationAssembly.AssemblyError.invalidContract("Missing control backing material") }
        backing.isEnabled = false
        if kind == .attitudeMode {
            for suffix in ["Heading", "PGNS", "AUTO", "ATTHOLD", "OFF"] {
                LMCockpitComponentSupport.readableMarkings(try LMCommanderStationAssembly.unique("AttitudeMode__" + suffix, in: root))
            }
        }
        LMCockpitComponentSupport.removeInput(root)
        target.name = kind.rawValue + " interaction proxy"
        target.position = [0, 0.01, 0.015]
        target.components.set(InputTargetComponent())
        target.components.set(HoverEffectComponent())
        target.components.set(CollisionComponent(shapes: [.generateBox(size: [0.035, 0.050, 0.045])]))
        if kind == .attitudeMode { target.components.set(LMAttitudeModeInteractionTarget()) }
        else { target.components.set(LMDescentRateInteractionTarget()) }
        actuator.addChild(target)
    }
    @discardableResult
    func apply(runtimeValue: String) -> Bool {
        guard let state = definition.states.first(where: {
            $0.supported && ($0.runtime_value == runtimeValue || $0.runtime_intent == runtimeValue || $0.id == runtimeValue)
        }) else { return false }
        actuator.position = neutralPosition
        actuator.orientation = rotationReference * simd_quatf(angle: state.angle_degrees * .pi / 180, axis: [1, 0, 0])
        return true
    }
    private static func quaternion(_ values: [Float]) throws -> simd_quatf {
        guard values.count == 4, values.allSatisfy(\.isFinite) else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Control rotation")
        }
        let q = simd_quatf(vector: SIMD4(values[0], values[1], values[2], values[3]))
        guard abs(simd_length(q.vector) - 1) < 0.00001 else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Control nonunit rotation")
        }
        return q
    }
}
