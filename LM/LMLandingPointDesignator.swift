import Foundation
import simd

enum LMLPDPane: CaseIterable, Sendable {
    case inner
    case outer
}

/// Angular calibration for the commander's Landing Point Designator.
///
/// NASA TN D-6846 establishes that zero is the LM +Z body axis and that the
/// computer-supplied look angle is sighted by aligning marks on both panes.
/// The angular scale is authoritative; the current physical eye and pane datums
/// remain provisional until checked against a vehicle drawing or artifact survey.
struct LMLandingPointDesignator: Sendable {
    static let elevationDegrees = Array(0...60)
    static let azimuthDegrees = Array(-10...10)
    static let horizontalScaleElevations = [0, 50]
    static let apollo11InPlaneRedesignationDegrees = 0.5
    static let apollo11CrossRangeRedesignationDegrees = 2.0

    let commanderEyeMeters = SIMD3<Float>(-0.36, 1.78, -0.38)
    let innerPaneZMeters: Float = -0.815
    let outerPaneZMeters: Float = -0.835

    func point(
        elevationDegrees: Double,
        azimuthDegrees: Double = 0,
        on pane: LMLPDPane
    ) -> SIMD3<Float> {
        let elevation = elevationDegrees * .pi / 180
        let azimuth = azimuthDegrees * .pi / 180
        let direction = SIMD3<Float>(
            Float(tan(azimuth)),
            -Float(tan(elevation)),
            -1
        )
        let paneZ = pane == .inner ? innerPaneZMeters : outerPaneZMeters
        let distance = (paneZ - commanderEyeMeters.z) / direction.z
        return commanderEyeMeters + direction * distance
    }

    func sightDirection(
        elevationDegrees: Double,
        azimuthDegrees: Double = 0
    ) -> SIMD3<Float> {
        simd_normalize(point(
            elevationDegrees: elevationDegrees,
            azimuthDegrees: azimuthDegrees,
            on: .outer
        ) - commanderEyeMeters)
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
}
