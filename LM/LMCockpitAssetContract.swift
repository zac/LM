import Foundation
import RealityKit

enum LMCockpitAssetContract {
    static let resourceName = "ApolloLMCabin"
    static let coordinateConvention = "+X LMP/right, +Y overhead, -Z forward; meters"
    static let datumPositionToleranceMeters: Float = 0.003
    static let datumNormalToleranceDegrees: Float = 0.25

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
        case nodePositionOutsideTolerance(Node)
        case nodeNormalOutsideTolerance(Node)
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
        issues.append(contentsOf: validateOpticalDatums(entity))
        return issues
    }

    @MainActor
    private static func validateOpticalDatums(_ root: Entity) -> [ValidationIssue] {
        let lpd = LMLandingPointDesignator()
        var issues = [ValidationIssue]()

        if let eye = root.findEntity(named: Node.commanderEye.rawValue),
           simd_distance(eye.position(relativeTo: root), lpd.commanderEyeMeters)
               > datumPositionToleranceMeters {
            issues.append(.nodePositionOutsideTolerance(.commanderEye))
        }

        for (nodeName, pane) in [
            (Node.commanderWindowInner, LMLPDPane.inner),
            (Node.commanderWindowOuter, LMLPDPane.outer),
        ] {
            guard let node = root.findEntity(named: nodeName.rawValue) else { continue }
            let expectedPlane = lpd.panePlane(pane)
            if simd_distance(
                node.position(relativeTo: root),
                expectedPlane.referencePointMeters
            ) > datumPositionToleranceMeters {
                issues.append(.nodePositionOutsideTolerance(nodeName))
            }

            let actualNormal = simd_normalize(
                node.orientation(relativeTo: root).act(SIMD3<Float>(0, 0, 1))
            )
            let cosine = min(max(
                simd_dot(actualNormal, expectedPlane.normalTowardEye),
                -1
            ), 1)
            let errorDegrees = acos(cosine) * 180 / .pi
            if errorDegrees > datumNormalToleranceDegrees {
                issues.append(.nodeNormalOutsideTolerance(nodeName))
            }
        }

        return issues
    }
}
