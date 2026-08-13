import Foundation
import LMCore

/// Maps Luminary ALLJETS numbers onto the USD quad labels.
///
/// Verified by sending `LMRCSGeometry` thrust/position through `LMWorldMapper.direction`
/// (sim +Z → RK +Y up, sim +Y → RK −Z forward, sim +X → RK +X right) and matching
/// `RCSThruster` body axes. Channel-5 U/V jets land on the four up/down quads.
/// Channel-6 P-axis jets whose quadrant has no matching lateral are assigned the
/// remaining unique cone of that axis.
enum LMRCSJetMapping {
    static let table: [LMRCSJet: RCSThruster] = [
        .jet10: .A1U,
        .jet14: .B2U,
        .jet6: .B4U,
        .jet2: .A3U,
        .jet13: .B1D,
        .jet9: .A2D,
        .jet1: .A4D,
        .jet5: .B3D,
        .jet3: .A1F,
        .jet8: .B4F,
        .jet7: .B3A,
        .jet4: .A2A,
        .jet11: .A4R,
        .jet16: .A3R,
        .jet15: .B2L,
        .jet12: .B1L
    ]

    static func thruster(for jet: LMRCSJet) -> RCSThruster? {
        table[jet]
    }

    static func thrusters(from commands: [LMRCSJetCommand]) -> Set<RCSThruster> {
        Set(commands.compactMap { table[$0.jet] })
    }
}
