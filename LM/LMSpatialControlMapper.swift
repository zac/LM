import Foundation
import simd

struct LMSpatialControlMapper: Equatable, Sendable {
    var acaTravelMeters: Float = 0.055
    var rodTravelMeters: Float = 0.045
    var rodDetentFraction: Float = 0.32

    func acaInput(for translation: SIMD3<Float>) -> LMACANormalizedInput {
        let travel = max(acaTravelMeters, 0.001)
        return LMACANormalizedInput(
            pitch: Double(clamped(-translation.z / travel)),
            yaw: Double(clamped(translation.y / travel)),
            roll: Double(clamped(translation.x / travel))
        )
    }

    func rodPosition(for verticalTranslation: Float) -> PoweredDescentSession.RODSwitchPosition {
        let travel = max(rodTravelMeters, 0.001)
        let normalized = clamped(verticalTranslation / travel)
        if normalized > rodDetentFraction {
            return .descendPlus
        }
        if normalized < -rodDetentFraction {
            return .descendMinus
        }
        return .neutral
    }

    func visualACATranslation(for input: LMACANormalizedInput) -> SIMD3<Float> {
        SIMD3(
            Float(input.roll) * acaTravelMeters,
            Float(input.yaw) * acaTravelMeters,
            -Float(input.pitch) * acaTravelMeters
        )
    }

    func visualRODTranslation(for position: PoweredDescentSession.RODSwitchPosition) -> Float {
        switch position {
        case .descendPlus:
            return rodTravelMeters
        case .neutral:
            return 0
        case .descendMinus:
            return -rodTravelMeters
        }
    }

    private func clamped(_ value: Float) -> Float {
        min(max(value, -1), 1)
    }
}
