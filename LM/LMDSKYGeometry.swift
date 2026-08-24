import AGC
import Foundation

/// Flight-configuration geometry for the Apollo 11 LM display and keyboard.
///
/// Primary sources:
/// - MIT/IL drawing 2003956, `AGC DSKY OUTLINE DRAWING`, revision B.
/// - MIT/IL assembly 2003994-091, the DSKY configuration installed in
///   Apollo 11 through Apollo 14 Lunar Modules.
///
/// Drawing 2003956 establishes the face envelope and the 19-switch layout.
/// The key centers below are digitized from its front view so every renderer
/// and the future artist asset use the same physical coordinate system.
struct LMDSKYKeyPlacement: Identifiable, Sendable {
    let code: DSKYKeyCode
    let centerInches: SIMD2<Float>
    let sizeInches: SIMD2<Float>

    var id: Int { code.rawValue }

    var centerMeters: SIMD2<Float> {
        centerInches * LMDSKYGeometry.metersPerInch
    }

    var sizeMeters: SIMD2<Float> {
        sizeInches * LMDSKYGeometry.metersPerInch
    }
}

enum LMDSKYGeometry {
    static let sourceAssembly = "2003994-091"
    static let sourceOutlineDrawing = "2003956 Rev B"
    static let metersPerInch: Float = 0.0254

    // Controlled envelope dimensions called out on drawing 2003956.
    static let faceWidthInches: Float = 8.124
    static let faceHeightInches: Float = 8.000
    static let maximumDepthInches: Float = 6.91
    static let mountingFaceWidthInches: Float = 7.700
    static let innerFaceWidthInches: Float = 6.900
    static let displayHeightInches: Float = 4.670
    static let keybedHeightInches: Float = 2.330
    static let lowerFaceInsetInches: Float = 0.500

    static let faceWidthMeters = faceWidthInches * metersPerInch
    static let faceHeightMeters = faceHeightInches * metersPerInch
    static let maximumDepthMeters = maximumDepthInches * metersPerInch
    static let mountingFaceWidthMeters = mountingFaceWidthInches * metersPerInch
    static let innerFaceWidthMeters = innerFaceWidthInches * metersPerInch
    static let keybedHeightMeters = keybedHeightInches * metersPerInch

    /// Center of the live display area in face-local coordinates.
    /// X and Y are measured from the face center; +Y is toward the top.
    static let displayCenterMeters = SIMD2<Float>(
        0,
        (lowerFaceInsetInches + keybedHeightInches + displayHeightInches / 2
            - faceHeightInches / 2) * metersPerInch
    )

    /// The 19 switch centers in drawing coordinates, measured from the lower
    /// left of the 8.124 × 8.000 inch face. All keys share the same flight-size
    /// cap envelope; RealityKit supplies a slightly larger collision target.
    static let keyPlacements: [LMDSKYKeyPlacement] = {
        let keySize = SIMD2<Float>(0.70, 0.62)
        let left: Float = 1.11
        let centerColumns: [Float] = [2.08, 2.98, 3.88, 4.78, 5.68]
        let right: Float = 6.67
        let rows: [Float] = [2.25, 1.55, 0.85]

        return [
            .init(code: .verb, centerInches: [left, rows[0]], sizeInches: keySize),
            .init(code: .noun, centerInches: [left, rows[1]], sizeInches: keySize),

            .init(code: .plus, centerInches: [centerColumns[0], rows[0]], sizeInches: keySize),
            .init(code: .digit7, centerInches: [centerColumns[1], rows[0]], sizeInches: keySize),
            .init(code: .digit8, centerInches: [centerColumns[2], rows[0]], sizeInches: keySize),
            .init(code: .digit9, centerInches: [centerColumns[3], rows[0]], sizeInches: keySize),
            .init(code: .clear, centerInches: [centerColumns[4], rows[0]], sizeInches: keySize),

            .init(code: .minus, centerInches: [centerColumns[0], rows[1]], sizeInches: keySize),
            .init(code: .digit4, centerInches: [centerColumns[1], rows[1]], sizeInches: keySize),
            .init(code: .digit5, centerInches: [centerColumns[2], rows[1]], sizeInches: keySize),
            .init(code: .digit6, centerInches: [centerColumns[3], rows[1]], sizeInches: keySize),
            .init(code: .pro, centerInches: [centerColumns[4], rows[1]], sizeInches: keySize),

            .init(code: .digit0, centerInches: [centerColumns[0], rows[2]], sizeInches: keySize),
            .init(code: .digit1, centerInches: [centerColumns[1], rows[2]], sizeInches: keySize),
            .init(code: .digit2, centerInches: [centerColumns[2], rows[2]], sizeInches: keySize),
            .init(code: .digit3, centerInches: [centerColumns[3], rows[2]], sizeInches: keySize),
            .init(code: .keyRelease, centerInches: [centerColumns[4], rows[2]], sizeInches: keySize),

            .init(code: .enter, centerInches: [right, rows[0]], sizeInches: keySize),
            .init(code: .reset, centerInches: [right, rows[1]], sizeInches: keySize),
        ]
    }()

    static let fallbackRows: [[DSKYKeyCode]] = [
        [.verb, .plus, .digit7, .digit8, .digit9, .clear, .enter],
        [.noun, .minus, .digit4, .digit5, .digit6, .pro, .reset],
        [.digit0, .digit1, .digit2, .digit3, .keyRelease],
    ]

    static func artistNodeName(for code: DSKYKeyCode) -> String {
        let suffix: String = switch code {
        case .plus: "PLUS"
        case .minus: "MINUS"
        case .keyRelease: "KEY_REL"
        case .enter: "ENTR"
        case .clear: "CLR"
        case .reset: "RSET"
        default: code.label
        }
        return "DSKY_Key_\(suffix)"
    }

    static func faceLocalPosition(for placement: LMDSKYKeyPlacement) -> SIMD3<Float> {
        SIMD3(
            placement.centerMeters.x - faceWidthMeters / 2,
            placement.centerMeters.y - faceHeightMeters / 2,
            0
        )
    }
}
