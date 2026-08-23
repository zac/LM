import Foundation
import RealityKit

enum LMCockpitAssetContract {
    static let resourceName = "ApolloLMCabin"
    static let coordinateConvention = "+X LMP/right, +Y overhead, -Z forward; meters"

    enum Node: String, CaseIterable, Sendable {
        case cabinRoot = "LM_Cabin"
        case commanderEye = "CDR_Eye"
        case commanderWindowInner = "CDR_Window_Inner"
        case commanderWindowOuter = "CDR_Window_Outer"
        case landingPointDesignatorInner = "LPD_Inner"
        case landingPointDesignatorOuter = "LPD_Outer"
        case panelOne = "Panel_1"
        case instrumentMount = "FDAI_DSKY_Mount"
        case acaPivot = "ACA_Pivot"
        case rodPivot = "ROD_Pivot"
        case attitudeHoldPivot = "ATT_HOLD_Pivot"
    }

    enum ValidationIssue: Equatable, Sendable {
        case missingNode(Node)
        case rootScaleMustBeIdentity
    }

    @MainActor
    static func loadIfAvailable(bundle: Bundle = .main) async throws -> Entity? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "usdz") else {
            return nil
        }
        return try await Entity(contentsOf: url)
    }

    @MainActor
    static func validate(_ entity: Entity) -> [ValidationIssue] {
        var issues: [ValidationIssue] = Node.allCases.compactMap { node in
            entity.findEntity(named: node.rawValue) == nil
                ? ValidationIssue.missingNode(node)
                : nil
        }
        let scale = entity.scale(relativeTo: nil)
        if simd_distance(scale, SIMD3<Float>(repeating: 1)) > 0.0001 {
            issues.append(ValidationIssue.rootScaleMustBeIdentity)
        }
        return issues
    }
}
