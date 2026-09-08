import AGC
import RealityKit
import UIKit

/// Display decoder only. Channel 163 supplies the flash phase and EL blanking.
struct LMDSKYSegmentState: Equatable {
    static let lamps: [(String, Int)] = [
        ("UPLINK_ACTY", 11), ("NO_ATT", 12), ("STBY", 13), ("KEY_REL", 14),
        ("OPR_ERR", 15), ("TEMP", 21), ("GIMBAL_LOCK", 22), ("PROG", 23),
        ("RESTART", 24), ("TRACKER", 25), ("ALT", 26), ("VEL", 27)
    ]
    static let digitSegments: [Character: String] = [
        "0": "ABCDEF", "1": "BC", "2": "ABDEG", "3": "ABCDG", "4": "BCFG",
        "5": "ACDFG", "6": "ACDEFG", "7": "ABC", "8": "ABCDEFG", "9": "ABCDFG"
    ]
    var illuminated = Set<String>()
    init(_ snapshot: DSKYSnapshot?) {
        guard let s = snapshot else { return }
        let elOn = s.channel163 & 0o1000 == 0
        for (field, value, count) in [("PROG", s.mode, 2), ("VERB", s.verb, 2),
                                      ("NOUN", s.noun, 2), ("R1", s.r1, 5),
                                      ("R2", s.r2, 5), ("R3", s.r3, 5)] {
            let register = count == 5
            let chars = Array(register ? String(value.dropFirst()) : value)
            let visible = elOn && (!(field == "VERB" || field == "NOUN") || !s.verbNounFlash)
            for index in 0..<count {
                let digit: Character = index < chars.count ? chars[index] : " "
                let segments = visible ? Self.digitSegments[digit, default: ""] : ""
                for segment in segments { illuminated.insert("DSKY_Digit_\(field)_\(index)_\(segment)") }
            }
            if register && elOn {
                if value.first == "+" { illuminated.insert("DSKY_Sign_\(field)_Plus") }
                if value.first == "+" || value.first == "-" { illuminated.insert("DSKY_Sign_\(field)_Minus") }
            }
        }
        for (name, id) in Self.lamps where s.lampTest || s.indicatorIsOn(id) {
            illuminated.insert("DSKY_Lamp_\(name)_Lens")
        }
        if s.lampTest || s.compActy { illuminated.insert("DSKY_COMP_ACTY_Lens") }
    }
}

@MainActor
final class LMImportedDSKY {
    enum ContractError: Error { case missingOrDuplicate(String), invalidParent(String) }
    let root: Entity
    let keys: [Int: Entity]
    private var surfaces: [String: [Entity]] = [:]
    private var neutral: [String: [ModelComponent]] = [:]
    private var previous: LMDSKYSegmentState?

    static func unique(_ name: String, in root: Entity) throws -> Entity {
        var matches: [Entity] = []
        func visit(_ node: Entity) {
            if node.name == name { matches.append(node) }
            for child in node.children { visit(child) }
        }
        visit(root)
        guard matches.count == 1 else { throw ContractError.missingOrDuplicate(name) }
        return matches[0]
    }

    init(asset: Entity) throws {
        root = try Self.unique("DSKY_Mount", in: asset)
        var bound: [Int: Entity] = [:]
        for placement in LMDSKYGeometry.keyPlacements {
            let name = LMDSKYGeometry.artistNodeName(for: placement.code)
            let key = try Self.unique(name, in: root)
            guard key.parent === root else { throw ContractError.invalidParent(name) }
            bound[placement.code.rawValue] = key
        }
        keys = bound
        var names: [String] = []
        for (field, count) in [("PROG", 2), ("VERB", 2), ("NOUN", 2), ("R1", 5), ("R2", 5), ("R3", 5)] {
            for index in 0..<count {
                for segment in "ABCDEFG" { names.append("DSKY_Digit_\(field)_\(index)_\(segment)") }
            }
            if count == 5 { names += ["DSKY_Sign_\(field)_Plus", "DSKY_Sign_\(field)_Minus"] }
        }
        names += LMDSKYSegmentState.lamps.map { "DSKY_Lamp_\($0.0)_Lens" }
        names.append("DSKY_COMP_ACTY_Lens")
        for name in names {
            let node = try Self.unique(name, in: root)
            var meshes: [Entity] = []
            func visit(_ entity: Entity) {
                if entity.components[ModelComponent.self] != nil { meshes.append(entity) }
                for child in entity.children { visit(child) }
            }
            visit(node)
            guard !meshes.isEmpty else { throw ContractError.missingOrDuplicate(name + " geometry") }
            surfaces[name] = meshes
            neutral[name] = meshes.compactMap { $0.components[ModelComponent.self] }
        }
        for key in keys.values {
            key.components.set(InputTargetComponent())
            key.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3(0.01778, 0.015748, 0.008))], mode: .trigger, filter: .sensor))
            key.components.set(HoverEffectComponent())
        }
    }

    func apply(_ snapshot: DSKYSnapshot?) {
        let state = LMDSKYSegmentState(snapshot)
        guard state != previous else { return }
        for (name, meshes) in surfaces {
            let on = state.illuminated.contains(name)
            for (index, mesh) in meshes.enumerated() {
                guard var model = neutral[name]?[index] else { continue }
                if on {
                    let status = LMDSKYSegmentState.lamps.prefix(5).contains { name == "DSKY_Lamp_\($0.0)_Lens" }
                    let color: UIColor = name.contains("Lamp") && !name.contains("COMP_ACTY")
                        ? (status ? .white : UIColor(red: 1, green: 0.65, blue: 0.12, alpha: 1))
                        : UIColor(red: 0.72, green: 1, blue: 0.2, alpha: 1)
                    model.materials = model.materials.map { _ in UnlitMaterial(color: color) }
                }
                mesh.components.set(model)
            }
        }
        previous = state
    }
}

/// A completed spatial tap is a bounded pulse. Cancelled gestures never call
/// this; task cancellation still releases PRO before another pulse can start.
enum LMDSKYInputPulse {
    static func run(key: DSKYKeyCode,
                    sendKey: (DSKYKeyCode) async -> Void,
                    sendPRO: (Bool) async -> Void) async {
        guard !Task.isCancelled else { return }
        if key == .pro {
            await sendPRO(true)
            try? await Task.sleep(for: .milliseconds(120))
            await sendPRO(false)
        } else {
            await sendKey(key)
        }
    }
}
