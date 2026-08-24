import Foundation
import simd

enum LMLPDPane: CaseIterable, Sendable {
    case inner
    case outer
}

enum LMLPDWindowCorner: CaseIterable, Hashable, Sendable {
    case upperOutboard
    case upperInboard
    case lower
}

struct LMLPDPlane: Sendable {
    let referencePointMeters: SIMD3<Float>
    let normalTowardEye: SIMD3<Float>

    func intersection(
        from eyeMeters: SIMD3<Float>,
        direction: SIMD3<Float>
    ) -> SIMD3<Float> {
        let denominator = simd_dot(normalTowardEye, direction)
        precondition(abs(denominator) > 1e-6, "LPD sightline must intersect the window pane")
        let distance = simd_dot(
            normalTowardEye,
            referencePointMeters - eyeMeters
        ) / denominator
        return eyeMeters + direction * distance
    }
}

/// Source-backed optical calibration for the commander's Landing Point Designator.
///
/// Coordinate conventions:
/// - Apollo body stations: +X overhead, +Y commander/outboard, +Z forward.
/// - RealityKit scene: +X LMP/right, +Y overhead, -Z forward.
///
/// Grumman course 30915 figure T30915-39 gives the commander's design eye at
/// X 279.25, Y 22, Z 54 inches. The same figure supplies the design-eye window
/// envelope. NASA TN D-7439 specifies the 25 by 28 by 24 inch triangular pane.
/// The procedural fallback reconstructs the oblique inner pane by intersecting
/// the three corner sight rays with those three physical side lengths. The LPD
/// marks on both panes then come from the same angular ray, preserving the
/// flight instrument's required parallax alignment at the design eye.
struct LMLandingPointDesignator: Sendable {
    static let metersPerInch: Float = 0.0254
    static let sourceDesignEyeInches = SIMD3<Float>(279.25, 22, 54)

    /// Top, inboard, and outboard sides from NASA TN D-7439.
    static let windowSideLengthsMeters = SIMD3<Float>(28, 24, 25) * metersPerInch

    /// Corner rays digitized from the January 1967 design-eye visibility plot
    /// T30915-39. Heading is positive commander/outboard; elevation is positive up.
    static let sourceCornerVisualAnglesDegrees: [LMLPDWindowCorner: SIMD2<Double>] = [
        .upperOutboard: SIMD2(75, 0),
        .upperInboard: SIMD2(-11, 5),
        .lower: SIMD2(-5, -65),
    ]

    /// Figure T30915-38 marks the vertical landing scale every 2 degrees and
    /// the horizontal cross-range scale every 5 degrees.
    static let elevationMarkDegrees = Array(stride(from: 0, through: 60, by: 2))
    static let azimuthMarkDegrees = Array(stride(from: -10, through: 10, by: 5))
    static let horizontalScaleElevations = [0]
    static let apollo11InPlaneRedesignationDegrees = 0.5
    static let apollo11CrossRangeRedesignationDegrees = 2.0

    /// Angular half-spans digitized from the relative mark proportions in
    /// T30915-38. Angular construction keeps the complete colored marks, not
    /// only their centers, collimated through both panes at the design eye.
    static let elevationMajorTickHalfSpanDegrees = 1.2
    static let elevationMinorTickHalfSpanDegrees = 0.7
    static let azimuthMajorTickHalfSpanDegrees = 0.9
    static let azimuthMinorTickHalfSpanDegrees = 0.6

    /// Scene placement of the flight design eye. The source body-station datum
    /// is retained separately so an artist cabin can be checked without making
    /// scene origin placement part of the spacecraft definition.
    let commanderEyeMeters = SIMD3<Float>(-0.36, 1.78, -0.38)

    /// The exact flight cavity depth is not present in the cited drawings. Keep
    /// this isolated and conspicuous until an artifact survey or dimensioned
    /// production drawing replaces it.
    let provisionalPaneSeparationMeters: Float = 0.020

    /// Reconstructed inner-pane corners relative to the design eye. They solve
    /// the three T30915-39 corner rays against a 28/24/25 inch triangle.
    private static let innerCornerOffsetsMeters: [LMLPDWindowCorner: SIMD3<Float>] = [
        .upperOutboard: SIMD3(-0.441_529_5, 0, -0.118_307_5),
        .upperInboard: SIMD3(0.109_796_3, 0.049_418_3, -0.564_853_2),
        .lower: SIMD3(0.017_576_9, -0.430_841_1, -0.200_904_5),
    ]

    var sourceBodyDatumMeters: SIMD3<Float> {
        commanderEyeMeters - Self.sceneVector(fromSourceBodyInches: Self.sourceDesignEyeInches)
    }

    func scenePoint(sourceBodyInches: SIMD3<Float>) -> SIMD3<Float> {
        sourceBodyDatumMeters + Self.sceneVector(fromSourceBodyInches: sourceBodyInches)
    }

    func panePlane(_ pane: LMLPDPane) -> LMLPDPlane {
        let innerReference = windowCorner(.upperOutboard, on: .inner)
        let normal = innerPaneNormalTowardEye
        switch pane {
        case .inner:
            return LMLPDPlane(
                referencePointMeters: innerReference,
                normalTowardEye: normal
            )
        case .outer:
            return LMLPDPlane(
                referencePointMeters: innerReference - normal * provisionalPaneSeparationMeters,
                normalTowardEye: normal
            )
        }
    }

    func windowCorner(
        _ corner: LMLPDWindowCorner,
        on pane: LMLPDPane
    ) -> SIMD3<Float> {
        guard let innerOffset = Self.innerCornerOffsetsMeters[corner] else {
            preconditionFailure("Every LPD window corner must be calibrated")
        }
        let innerCorner = commanderEyeMeters + innerOffset
        guard pane == .outer else { return innerCorner }
        return panePlane(.outer).intersection(
            from: commanderEyeMeters,
            direction: innerOffset
        )
    }

    func windowCorners(on pane: LMLPDPane) -> [SIMD3<Float>] {
        LMLPDWindowCorner.allCases.map { windowCorner($0, on: pane) }
    }

    func point(
        elevationDegrees: Double,
        azimuthDegrees: Double = 0,
        on pane: LMLPDPane
    ) -> SIMD3<Float> {
        panePlane(pane).intersection(
            from: commanderEyeMeters,
            direction: sightDirectionVector(
                elevationDegrees: elevationDegrees,
                azimuthDegrees: azimuthDegrees
            )
        )
    }

    func elevationTickEndpoints(
        elevationDegrees: Int,
        on pane: LMLPDPane
    ) -> (start: SIMD3<Float>, end: SIMD3<Float>) {
        let halfSpan = elevationDegrees.isMultiple(of: 10)
            ? Self.elevationMajorTickHalfSpanDegrees
            : Self.elevationMinorTickHalfSpanDegrees
        return (
            point(
                elevationDegrees: Double(elevationDegrees),
                azimuthDegrees: -halfSpan,
                on: pane
            ),
            point(
                elevationDegrees: Double(elevationDegrees),
                azimuthDegrees: halfSpan,
                on: pane
            )
        )
    }

    func azimuthTickEndpoints(
        azimuthDegrees: Int,
        scaleElevationDegrees: Int = 0,
        on pane: LMLPDPane
    ) -> (start: SIMD3<Float>, end: SIMD3<Float>) {
        let halfSpan = azimuthDegrees.isMultiple(of: 10)
            ? Self.azimuthMajorTickHalfSpanDegrees
            : Self.azimuthMinorTickHalfSpanDegrees
        return (
            point(
                elevationDegrees: Double(scaleElevationDegrees) - halfSpan,
                azimuthDegrees: Double(azimuthDegrees),
                on: pane
            ),
            point(
                elevationDegrees: Double(scaleElevationDegrees) + halfSpan,
                azimuthDegrees: Double(azimuthDegrees),
                on: pane
            )
        )
    }

    func sightDirection(
        elevationDegrees: Double,
        azimuthDegrees: Double = 0
    ) -> SIMD3<Float> {
        simd_normalize(sightDirectionVector(
            elevationDegrees: elevationDegrees,
            azimuthDegrees: azimuthDegrees
        ))
    }

    func paneBasis(
        _ pane: LMLPDPane
    ) -> (right: SIMD3<Float>, up: SIMD3<Float>, normal: SIMD3<Float>) {
        let right = simd_normalize(
            windowCorner(.upperInboard, on: pane)
                - windowCorner(.upperOutboard, on: pane)
        )
        let normal = panePlane(pane).normalTowardEye
        let up = simd_normalize(simd_cross(normal, right))
        return (right, up, normal)
    }

    func paneOrientation(_ pane: LMLPDPane) -> simd_quatf {
        let basis = paneBasis(pane)
        return simd_quatf(simd_float3x3(columns: (
            basis.right,
            basis.up,
            basis.normal
        )))
    }

    func sourceVisualAnglesDegrees(
        for scenePoint: SIMD3<Float>
    ) -> SIMD2<Double> {
        let offset = scenePoint - commanderEyeMeters
        let heading = atan2(Double(-offset.x), Double(-offset.z)) * 180 / .pi
        let elevation = atan2(Double(offset.y), Double(-offset.z)) * 180 / .pi
        return SIMD2(heading, elevation)
    }

    func alignmentErrorRadians(
        eyeMeters: SIMD3<Float>,
        elevationDegrees: Double,
        azimuthDegrees: Double = 0
    ) -> Float {
        let inner = simd_normalize(point(
            elevationDegrees: elevationDegrees,
            azimuthDegrees: azimuthDegrees,
            on: .inner
        ) - eyeMeters)
        let outer = simd_normalize(point(
            elevationDegrees: elevationDegrees,
            azimuthDegrees: azimuthDegrees,
            on: .outer
        ) - eyeMeters)
        return acos(min(max(simd_dot(inner, outer), -1), 1))
    }

    private var innerPaneNormalTowardEye: SIMD3<Float> {
        let outboard = windowCorner(.upperOutboard, on: .inner)
        let inboard = windowCorner(.upperInboard, on: .inner)
        let lower = windowCorner(.lower, on: .inner)
        var normal = simd_normalize(simd_cross(inboard - outboard, lower - outboard))
        if simd_dot(normal, commanderEyeMeters - outboard) < 0 {
            normal = -normal
        }
        return normal
    }

    private func sightDirectionVector(
        elevationDegrees: Double,
        azimuthDegrees: Double
    ) -> SIMD3<Float> {
        let elevation = elevationDegrees * .pi / 180
        let azimuth = azimuthDegrees * .pi / 180
        return SIMD3<Float>(
            Float(tan(azimuth)),
            -Float(tan(elevation)),
            -1
        )
    }

    private static func sceneVector(
        fromSourceBodyInches source: SIMD3<Float>
    ) -> SIMD3<Float> {
        SIMD3(-source.y, source.x, -source.z) * metersPerInch
    }
}
