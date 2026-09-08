import Foundation
import LMKit
import RealityKit
import UIKit
import simd

struct LMEventTimerControlTarget: Component { let id: String }

@MainActor
final class LMImportedTimers {
    struct Contract: Decodable {
        struct Asset: Decodable {
            struct Digit: Decodable { let name: String; let place: String; let position_m: [Float]; let segments: [String: String] }
            struct Control: Decodable {
                let id: String; let pivot: String; let stem: String; let position_m: [Float]
                let axis: [Float]; let angles_degrees: [Float]; let positions: [String]; let neutral_index: Int
            }
            let root: String; let panel_slot: String?; let installation_allowed: Bool?
            let slot_local_pose: LMCommanderStationAssembly.Inventory.Pose?
            let digits: [Digit]?; let controls: [Control]?
        }
        let schema: String; let units: String; let assets: [Asset]
        let digit_masks: [String: [String]]
    }
    let readouts = Entity()
    let controls: Entity
    let controlsPose: Transform
    let contract: Contract
    private var segments: [[String: Entity]] = []
    private var off: [ObjectIdentifier: [any Material]] = [:]
    private var pivots: [String: Entity] = [:]
    private(set) var displayedEventDigits: [Int]?
    private(set) var missionTimeAvailable = false

    init(mission: Entity, event: Entity, controlsAsset: Entity, interfaceData: Data) throws {
        contract = try JSONDecoder().decode(Contract.self, from: interfaceData)
        guard contract.schema == "lmkit.timers.interface.v1", contract.units == "meters",
              let missionSpec = contract.assets.first(where: { $0.root == "MissionTimer" }),
              let eventSpec = contract.assets.first(where: { $0.root == "EventTimer" }),
              let controlSpec = contract.assets.first(where: { $0.root == "EventTimerControls" }),
              let blocked = contract.assets.first(where: { $0.root == "MissionTimerControls" }),
              blocked.installation_allowed == false, controlSpec.installation_allowed == true,
              missionSpec.panel_slot == "Panel1__Timers", eventSpec.panel_slot == "Panel1__Timers",
              controlSpec.panel_slot == "Panel3__TimerHeaters",
              let controlPose = controlSpec.slot_local_pose else { throw LMImportedSystemsHardware.invalid("Timer contract") }
        controlsPose = try controlPose.transform()
        controls = try LMCockpitComponentSupport.neutralRoot("EventTimerControls", asset: controlsAsset)
        readouts.name = "TimerReadouts"
        for (asset, spec, expectedCount, expectedX) in [(mission, missionSpec, 7, Float(-0.030)), (event, eventSpec, 4, Float(0.093))] {
            let root = try LMCockpitComponentSupport.neutralRoot(spec.root, asset: asset)
            guard let slotPose = spec.slot_local_pose, let digits = spec.digits, digits.count == expectedCount else { throw LMImportedSystemsHardware.invalid("Timer digits") }
            let pose = try slotPose.transform()
            guard simd_distance(pose.translation, [expectedX, 0, 0.004]) < 0.00001, abs(pose.rotation.real) > 0.99999 else { throw LMImportedSystemsHardware.invalid("Timer mounting") }
            for digit in digits {
                let node = try LMCommanderStationAssembly.unique(digit.name, in: root)
                guard simd_distance(node.position, try LMCockpitComponentSupport.vector(digit.position_m)) < 0.00001,
                      Set(digit.segments.keys) == Set("ABCDEFG".map(String.init)) else { throw LMImportedSystemsHardware.invalid("Timer segment inventory") }
                var mapped: [String: Entity] = [:]
                for (letter, name) in digit.segments {
                    let segment = try LMCommanderStationAssembly.unique(name, in: node)
                    let models = LMCommanderStationAssembly.descendants(segment).filter { $0.components[ModelComponent.self] != nil }
                    guard !models.isEmpty else { throw LMImportedSystemsHardware.invalid(name) }
                    for model in models { off[ObjectIdentifier(model)] = model.components[ModelComponent.self]!.materials }
                    mapped[letter] = segment
                }
                if spec.root == "EventTimer" { segments.append(mapped) }
            }
            LMCockpitComponentSupport.removeInput(root)
            root.transform = pose
            readouts.addChild(root)
        }
        guard simd_distance(controlsPose.translation, [0, 0.036, 0.004]) < 0.00001, abs(controlsPose.rotation.real) > 0.99999,
              let definitions = controlSpec.controls, definitions.count == 4 else { throw LMImportedSystemsHardware.invalid("Timer control placement") }
        LMCockpitComponentSupport.removeInput(controls)
        let ids = ["EventTimer_ResetCount", "EventTimer_TimerControl", "EventTimer_MinutesSlew", "EventTimer_SecondsSlew"]
        guard Set(definitions.map(\.id)) == Set(ids) else { throw LMImportedSystemsHardware.invalid("Timer control IDs") }
        for definition in definitions {
            let pivot = try LMCommanderStationAssembly.unique(definition.pivot, in: controls)
            guard definition.axis == [1, 0, 0], definition.angles_degrees == [-25, 0, 25], definition.neutral_index == 1,
                  simd_distance(pivot.position, try LMCockpitComponentSupport.vector(definition.position_m)) < 0.00001,
                  abs(pivot.orientation.real) > 0.99999 else { throw LMImportedSystemsHardware.invalid("Timer pivot") }
            _ = try LMCommanderStationAssembly.unique(definition.stem, in: pivot)
            pivots[definition.id] = pivot
            let proxy = Entity()
            proxy.name = definition.id + "_Input"
            proxy.components.set(LMEventTimerControlTarget(id: definition.id))
            proxy.components.set(InputTargetComponent())
            proxy.components.set(CollisionComponent(shapes: [.generateBox(size: [0.018, 0.030, 0.030])]))
            proxy.position = [0, 0, 0.015]
            pivot.addChild(proxy)
        }
    }
    static func load() throws -> LMImportedTimers {
        try .init(mission: Entity.load(contentsOf: LMKitAssets.missionTimerURL), event: Entity.load(contentsOf: LMKitAssets.eventTimerURL),
                  controlsAsset: Entity.load(contentsOf: LMKitAssets.eventTimerControlsURL), interfaceData: Data(contentsOf: LMKitAssets.timersInterfaceURL))
    }
    func apply(_ state: LMEventTimerState) {
        displayedEventDigits = state.digits
        for (index, digit) in segments.enumerated() {
            let active = state.digits.flatMap { contract.digit_masks[String($0[index])] } ?? []
            for (letter, segment) in digit {
                for entity in LMCommanderStationAssembly.descendants(segment) {
                    guard var model = entity.components[ModelComponent.self], let original = off[ObjectIdentifier(entity)] else { continue }
                    model.materials = active.contains(letter) ? [UnlitMaterial(color: UIColor(red: 0.63, green: 0.82, blue: 0.60, alpha: 1))] : original
                    entity.components.set(model)
                }
            }
        }
    }
    func setControl(_ id: String, position: Int) {
        guard let pivot = pivots[id], (0...2).contains(position) else { return }
        pivot.orientation = simd_quatf(angle: Float(position - 1) * 25 * .pi / 180, axis: [1, 0, 0])
    }
    func releaseControls(direction: LMEventTimerState.Direction) {
        // All event controls spring to center; selected count direction is logical state.
        for id in pivots.keys { setControl(id, position: 1) }
    }
}
