import Foundation
import AGC
import RealityKit

enum LMCockpitAssetContract {
    static let resourceName = "ApolloLMCabin"
    static let coordinateConvention = "+X LMP/right, +Y overhead, -Z forward; meters"
    static let datumPositionToleranceMeters: Float = 0.003
    static let datumNormalToleranceDegrees: Float = 0.25
    static let reconstructedPositionToleranceMeters: Float = 0.015
    static let reconstructedNormalToleranceDegrees: Float = 1.0

    enum Node: String, CaseIterable, Sendable {
        case cabinRoot = "LM_Cabin"
        case cabinShell = "Cabin_Shell"
        case cabinDeck = "Cabin_Deck"
        case forwardHatch = "Forward_Hatch"
        case commanderEye = "CDR_Eye"
        case commanderWindowInner = "CDR_Window_Inner"
        case commanderWindowOuter = "CDR_Window_Outer"
        case landingPointDesignatorInner = "LPD_Inner"
        case landingPointDesignatorOuter = "LPD_Outer"
        case panelOne = "Panel_1"
        case panelTwo = "Panel_2"
        case panelThree = "Panel_3"
        case panelFour = "Panel_4"
        case panelFive = "Panel_5"
        case panelSix = "Panel_6"
        case commanderGlareShield = "CDR_Glareshield"
        case lmpGlareShield = "LMP_Glareshield"
        case fdaiMount = "FDAI_Mount"
        case dskyMount = "DSKY_Mount"
        case dskyFace = "DSKY_Face"
        case dskyDisplayMount = "DSKY_Display_Mount"
        case acaPivot = "ACA_Pivot"
        case rodPivot = "ROD_Pivot"
        case attitudeHoldPivot = "ATT_HOLD_Pivot"
    }

    enum ValidationIssue: Equatable, Sendable {
        case missingNode(Node)
        case rootScaleMustBeIdentity
        case nodePositionOutsideTolerance(Node)
        case nodeNormalOutsideTolerance(Node)
        case missingDSKYKey(Int)
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
        issues.append(contentsOf: LMDSKYGeometry.keyPlacements.compactMap { placement in
            entity.findEntity(named: LMDSKYGeometry.artistNodeName(for: placement.code)) == nil
                ? ValidationIssue.missingDSKYKey(placement.code.rawValue)
                : nil
        })
        let scale = entity.scale(relativeTo: nil)
        if simd_distance(scale, SIMD3<Float>(repeating: 1)) > 0.0001 {
            issues.append(ValidationIssue.rootScaleMustBeIdentity)
        }
        issues.append(contentsOf: validateOpticalDatums(entity))
        issues.append(contentsOf: validateStationDatums(entity))
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

    @MainActor
    private static func validateStationDatums(_ root: Entity) -> [ValidationIssue] {
        var issues = [ValidationIssue]()

        for surface in LMCommanderStationGeometry.reconstructedSurfaces {
            guard let nodeName = Node(rawValue: surface.id.rawValue),
                  let node = root.findEntity(named: nodeName.rawValue) else { continue }
            appendTransformIssues(
                node: node,
                nodeName: nodeName,
                expectedPosition: surface.centerMeters,
                expectedNormal: surface.faceNormalTowardCrew,
                root: root,
                positionTolerance: reconstructedPositionToleranceMeters,
                normalToleranceDegrees: reconstructedNormalToleranceDegrees,
                issues: &issues
            )
        }

        let mountDatums: [(Node, SIMD3<Float>, SIMD3<Float>?)] = [
            (
                .fdaiMount,
                LMCommanderStationGeometry.fdaiMountPositionMeters,
                LMCommanderStationGeometry.fdaiMountOrientation.act(SIMD3(0, 0, 1))
            ),
            (
                .dskyMount,
                LMCommanderStationGeometry.dskyMountPositionMeters,
                LMCommanderStationGeometry.dskyMountOrientation.act(SIMD3(0, 0, 1))
            ),
            (.acaPivot, LMCommanderStationGeometry.acaPivotPositionMeters, nil),
            (.rodPivot, LMCommanderStationGeometry.rodPivotPositionMeters, nil),
            (
                .attitudeHoldPivot,
                LMCommanderStationGeometry.attitudeHoldPivotPositionMeters,
                LMCommanderStationGeometry.attitudeHoldOrientation.act(SIMD3(0, 0, 1))
            ),
        ]
        for (nodeName, expectedPosition, expectedNormal) in mountDatums {
            guard let node = root.findEntity(named: nodeName.rawValue) else { continue }
            appendTransformIssues(
                node: node,
                nodeName: nodeName,
                expectedPosition: expectedPosition,
                expectedNormal: expectedNormal,
                root: root,
                positionTolerance: datumPositionToleranceMeters,
                normalToleranceDegrees: datumNormalToleranceDegrees,
                issues: &issues
            )
        }

        return issues
    }

    @MainActor
    private static func appendTransformIssues(
        node: Entity,
        nodeName: Node,
        expectedPosition: SIMD3<Float>,
        expectedNormal: SIMD3<Float>?,
        root: Entity,
        positionTolerance: Float,
        normalToleranceDegrees: Float,
        issues: inout [ValidationIssue]
    ) {
        if simd_distance(node.position(relativeTo: root), expectedPosition) > positionTolerance {
            issues.append(.nodePositionOutsideTolerance(nodeName))
        }
        guard let expectedNormal else { return }
        let actualNormal = simd_normalize(
            node.orientation(relativeTo: root).act(SIMD3<Float>(0, 0, 1))
        )
        let cosine = min(max(simd_dot(actualNormal, simd_normalize(expectedNormal)), -1), 1)
        let errorDegrees = acos(cosine) * 180 / .pi
        if errorDegrees > normalToleranceDegrees {
            issues.append(.nodeNormalOutsideTolerance(nodeName))
        }
    }
}
