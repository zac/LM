import RealityKit

/// Runtime installation facts, separate from the authoring inventory and from
/// electrical/flight-system fidelity. Partial regions always retain that caveat.
struct LMCockpitSlotOccupancy: Equatable {
    enum Coverage: String { case partialRegion, occupiedRegion }
    let coverage: Coverage
    let componentIDs: [String]
    let note: String?

    var planningText: String {
        let names = componentIDs.map { id in
            switch id {
            case "AltitudeRate": "Altitude / rate"
            case "CrossPointer": "Cross-pointer"
            case "AttitudeMode": "Attitude mode"
            case "DescentRate": "Descent rate"
            case "BreakerBanks": "Breaker bank"
            default: id
            }
        }.joined(separator: " + ")
        let status = coverage == .partialRegion ? "PARTIAL REGION" : "INSTALLED EQUIPMENT"
        let caveat = coverage == .partialRegion ? (["Other equipment pending"] + [note].compactMap { $0 }).joined(separator: "\n") : note
        return ([status, names] + [caveat].compactMap { $0 }).joined(separator: "\n")
    }
}
