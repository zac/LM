import Foundation
import simd

struct LMSpatialControlMapper: Equatable, Sendable {
    var acaTravelMeters: Float = 0.055
    /// Hand travel used to cross a DES RATE detent. The switch itself pivots;
    /// this is the spatial-gesture distance, not visible lever translation.
    var rodTravelMeters: Float = 0.025
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

    func rodPosition(
        for translation: SIMD3<Float>,
        along actuationAxis: SIMD3<Float>
    ) -> PoweredDescentSession.RODSwitchPosition {
        let axisLength = simd_length(actuationAxis)
        guard axisLength > 0.0001 else { return .neutral }
        return rodPosition(for: simd_dot(translation, actuationAxis / axisLength))
    }

    func visualRODDeflectionRadians(
        for position: PoweredDescentSession.RODSwitchPosition
    ) -> Float {
        let travel = Float.pi * 20 / 180
        switch position {
        case .descendPlus:
            return travel
        case .neutral:
            return 0
        case .descendMinus:
            return -travel
        }
    }

    private func clamped(_ value: Float) -> Float {
        min(max(value, -1), 1)
    }
}
