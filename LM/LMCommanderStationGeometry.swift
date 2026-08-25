import Foundation
import simd

/// Physical datums for the LM forward crew compartment and control-panel stack.
///
/// Controlled dimensions and angles come from two Grumman/NASA primary sources:
/// - *Apollo Operations Handbook, Lunar Module LM 10, Volume I*, section
///   1.2.2.1.1 and figure 1-7.
/// - *Apollo News Reference: Lunar Module*, crew-compartment description.
///
/// The handbooks do not provide individual panel envelopes. Those values live
/// only in `reconstructedSurfaces` and are explicitly identified as digitized
/// reconstruction values. They preserve the controlled panel relationships and
/// can be replaced without moving the optical or interaction datums.
enum LMCommanderStationGeometry {
    static let metersPerInch: Float = 0.0254
    static let operationsHandbookSource =
        "Apollo Operations Handbook, Lunar Module LM 10, Volume I, §1.2.2.1.1, Figure 1-7"
    static let newsReferenceSource = "Apollo News Reference: Lunar Module, Crew Compartment"

    // MARK: - Controlled or explicitly approximate source dimensions

    static let crewCompartmentDiameterInches: Float = 92
    static let crewCompartmentDepthInches: Float = 42
    static let flightStationCenterlineSeparationInches: Float = 44
    static let deckWidthInches: Float = 55
    static let deckDepthInches: Float = 36
    static let approximateForwardHatchSideInches: Float = 32
    static let mainPanelSandwichDepthInches: Float = 2
    static let mainPanelForwardCantDegrees: Float = 10
    static let centerPanelDownAndAftSlopeDegrees: Float = 45
    /// Figure 2.1-40 identifies 1° through 11° as the proportional ACA range.
    static let acaProportionalTravelDegrees: Float = 11
    /// The LM-10 handbook defines ACA hardover as 12° or more in any axis.
    static let acaHardoverDegrees: Float = 12
    static let descentRateIncrementFeetPerSecond: Float = 1

    static let crewCompartmentDiameterMeters = crewCompartmentDiameterInches * metersPerInch
    static let crewCompartmentDepthMeters = crewCompartmentDepthInches * metersPerInch
    static let flightStationCenterlineSeparationMeters =
        flightStationCenterlineSeparationInches * metersPerInch
    static let deckWidthMeters = deckWidthInches * metersPerInch
    static let deckDepthMeters = deckDepthInches * metersPerInch
    static let approximateForwardHatchSideMeters = approximateForwardHatchSideInches * metersPerInch
    static let mainPanelSandwichDepthMeters = mainPanelSandwichDepthInches * metersPerInch

    /// Scene-space station centerlines. Commander is negative X; LMP is positive X.
    static let commanderStationCenterXMeters = -flightStationCenterlineSeparationMeters / 2
    static let lmpStationCenterXMeters = flightStationCenterlineSeparationMeters / 2

    enum SurfaceID: String, CaseIterable, Sendable {
        case cabinDeck = "Cabin_Deck"
        case forwardHatch = "Forward_Hatch"
        case panelOne = "Panel_1"
        case panelTwo = "Panel_2"
        case panelThree = "Panel_3"
        case panelFour = "Panel_4"
        case panelFive = "Panel_5"
        case panelSix = "Panel_6"
        case commanderGlareShield = "CDR_Glareshield"
        case lmpGlareShield = "LMP_Glareshield"
    }

    struct Surface: Identifiable, Sendable {
        let id: SurfaceID
        /// Local box dimensions. X and Y span the face; Z is the face depth.
        let sizeMeters: SIMD3<Float>
        let centerMeters: SIMD3<Float>
        /// Negative pitch puts the top edge forward and the bottom edge aft.
        let pitchDegrees: Float

        var orientation: simd_quatf {
            simd_quatf(
                angle: pitchDegrees * .pi / 180,
                axis: SIMD3<Float>(1, 0, 0)
            )
        }

        var faceNormalTowardCrew: SIMD3<Float> {
            simd_normalize(orientation.act(SIMD3<Float>(0, 0, 1)))
        }

        func scenePoint(local: SIMD3<Float>) -> SIMD3<Float> {
            centerMeters + orientation.act(local)
        }
    }

    /// Panel envelopes reconstructed from LM-10 handbook figure 1-7 using the
    /// controlled 44-inch flight-station separation and 8.124-inch DSKY face as
    /// scale checks. These are production blockout datums, not claimed drawings.
    static let reconstructedSurfaces: [Surface] = [
        Surface(
            id: .cabinDeck,
            sizeMeters: SIMD3(deckWidthMeters, deckDepthMeters, 0.045),
            centerMeters: SIMD3(0, 0.10, -0.07),
            pitchDegrees: -90
        ),
        Surface(
            id: .forwardHatch,
            sizeMeters: SIMD3(
                approximateForwardHatchSideMeters,
                approximateForwardHatchSideMeters,
                0.035
            ),
            centerMeters: SIMD3(0, 0.52, -0.64),
            pitchDegrees: 0
        ),
        Surface(
            id: .panelOne,
            sizeMeters: SIMD3(0.48, 0.50, mainPanelSandwichDepthMeters),
            centerMeters: SIMD3(-0.245, 1.045, -0.535),
            pitchDegrees: -mainPanelForwardCantDegrees
        ),
        Surface(
            id: .panelTwo,
            sizeMeters: SIMD3(0.48, 0.50, mainPanelSandwichDepthMeters),
            centerMeters: SIMD3(0.245, 1.045, -0.535),
            pitchDegrees: -mainPanelForwardCantDegrees
        ),
        Surface(
            id: .panelThree,
            sizeMeters: SIMD3(0.97, 0.18, 0.040),
            centerMeters: SIMD3(0, 0.735, -0.540),
            pitchDegrees: -centerPanelDownAndAftSlopeDegrees
        ),
        Surface(
            id: .panelFour,
            sizeMeters: SIMD3(0.40, 0.34, 0.040),
            centerMeters: SIMD3(0, 0.535, -0.435),
            pitchDegrees: -centerPanelDownAndAftSlopeDegrees
        ),
        Surface(
            id: .panelFive,
            sizeMeters: SIMD3(0.34, 0.31, 0.038),
            centerMeters: SIMD3(commanderStationCenterXMeters, 0.46, -0.30),
            pitchDegrees: -75
        ),
        Surface(
            id: .panelSix,
            sizeMeters: SIMD3(0.34, 0.31, 0.038),
            centerMeters: SIMD3(lmpStationCenterXMeters, 0.46, -0.30),
            pitchDegrees: -75
        ),
        Surface(
            id: .commanderGlareShield,
            sizeMeters: SIMD3(0.57, 0.15, 0.040),
            centerMeters: SIMD3(-0.47, 1.315, -0.465),
            pitchDegrees: -70
        ),
        Surface(
            id: .lmpGlareShield,
            sizeMeters: SIMD3(0.57, 0.15, 0.040),
            centerMeters: SIMD3(0.47, 1.315, -0.465),
            pitchDegrees: -70
        ),
    ]

    static let panelSurfaces = reconstructedSurfaces.filter {
        switch $0.id {
        case .panelOne, .panelTwo, .panelThree, .panelFour, .panelFive, .panelSix:
            true
        default:
            false
        }
    }

    static func surface(_ id: SurfaceID) -> Surface {
        guard let result = reconstructedSurfaces.first(where: { $0.id == id }) else {
            preconditionFailure("Every commander-station surface must have a reconstruction datum")
        }
        return result
    }

    // MARK: - Instrument and interaction datums

    static let fdaiMountPositionMeters = surface(.panelOne).scenePoint(
        local: SIMD3(-0.055, -0.015, surface(.panelOne).sizeMeters.z / 2 + 0.008)
    )
    static let fdaiMountOrientation = surface(.panelOne).orientation

    static let dskyMountPositionMeters = surface(.panelFour).scenePoint(
        local: SIMD3(0, 0.015, surface(.panelFour).sizeMeters.z / 2 + 0.009)
    )
    static let dskyMountOrientation = surface(.panelFour).orientation

    // MARK: - Immersive assembly and crew entry

    /// The bundled lander was authored at approximately full Apollo scale but
    /// its ascent-stage pressure shell is 2.67 m wide. Scale it to the
    /// handbook's controlled 92-inch crew-compartment diameter.
    static let exteriorModelScale: Float = crewCompartmentDiameterMeters / 2.67

    /// Aligns the procedural crew-compartment datum with the ascent-stage shell
    /// in the bundled `lunarlander` hierarchy. This remains an explicit asset
    /// registration value so replacing the art does not move flight datums.
    static let cabinFrameOffsetMeters = SIMD3<Float>(-0.025, 1.981, -0.298)

    /// Enter slightly aft and below the optical design eye so the full panel
    /// stack is visible immediately. The wearer can lean forward into the
    /// source-backed design eye when using the Landing Point Designator.
    static let comfortableEntryOffsetFromDesignEyeMeters = SIMD3<Float>(0, -0.42, 0.50)

    static let comfortableEntryEyeMeters =
        cabinFrameOffsetMeters
        + LMLandingPointDesignator().commanderEyeMeters
        + comfortableEntryOffsetFromDesignEyeMeters

    /// A reconstructed, clearly non-flight mission-management control placed
    /// on the otherwise sparse lower-right region of Panel 5.
    static let missionControlButtonPositionMeters = surface(.panelFive).scenePoint(
        local: SIMD3(0.085, -0.065, surface(.panelFive).sizeMeters.z / 2 + 0.024)
    )
    static let missionControlButtonOrientation = surface(.panelFive).orientation

    /// Floating panel position is deliberately aft/outboard of the flight
    /// controls so it can be read without covering the DSKY, FDAI, or window.
    static let missionControlPanelPositionMeters = SIMD3<Float>(-0.92, 1.38, -0.02)

    static let acaPivotPositionMeters = SIMD3<Float>(-0.49, 0.50, -0.37)

    /// The spring-return DES RATE switch is 1S5 on Panel 5. Each throw supplies
    /// one Channel 16 pulse and changes commanded descent rate by 1 ft/s.
    /// Its exact drawing station is not published in the handbook; this local
    /// placement is reconstructed within the Panel 5 envelope from figure 1-7.
    static let rodPivotPositionMeters = surface(.panelFive).scenePoint(
        local: SIMD3(-0.095, 0.060, surface(.panelFive).sizeMeters.z / 2 + 0.020)
    )
    static let rodNeutralOrientation = surface(.panelFive).orientation
    static let rodActuationAxis = simd_normalize(
        surface(.panelFive).orientation.act(SIMD3<Float>(0, 1, 0))
    )
    static let attitudeHoldPivotPositionMeters = surface(.panelThree).scenePoint(
        local: SIMD3(0.33, 0, surface(.panelThree).sizeMeters.z / 2 + 0.012)
    )
    static let attitudeHoldOrientation = surface(.panelThree).orientation

    // MARK: - Cylindrical pressure-shell blockout

    struct ShellSegment: Identifiable, Sendable {
        let id: Int
        let sizeMeters: SIMD3<Float>
        let centerMeters: SIMD3<Float>
        let orientation: simd_quatf
    }

    static let shellCenterYMeters: Float = 1.10
    static let shellCenterZMeters: Float = -0.12
    static let shellThicknessMeters: Float = 0.035

    static let shellSegments: [ShellSegment] = {
        let radius = crewCompartmentDiameterMeters / 2
        let count = 10
        let step = Float.pi / Float(count)
        let chord = 2 * radius * sin(step / 2)
        return (0..<count).map { index in
            let angle = -.pi / 2 + step * (Float(index) + 0.5)
            return ShellSegment(
                id: index,
                sizeMeters: SIMD3(chord, shellThicknessMeters, crewCompartmentDepthMeters),
                centerMeters: SIMD3(
                    sin(angle) * radius,
                    shellCenterYMeters + cos(angle) * radius,
                    shellCenterZMeters
                ),
                orientation: simd_quatf(angle: -angle, axis: SIMD3<Float>(0, 0, 1))
            )
        }
    }()
}
