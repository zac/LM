import Foundation

/// Normalized ACA axes from a directly grabbed analog handle (or the
/// gaze-and-pinch accessibility fallback). Each axis is -1…1 with 0 at center.
struct LMACANormalizedInput: Equatable, Sendable {
    var pitch = 0.0
    var yaw = 0.0
    var roll = 0.0

    static let neutral = LMACANormalizedInput()

    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, -1), 1) : 0
    }

    var clamped: Self {
        Self(pitch: Self.clamp(pitch), yaw: Self.clamp(yaw), roll: Self.clamp(roll))
    }

    var isNeutral: Bool { pitch == 0 && yaw == 0 && roll == 0 }
}

/// Maps normalized ACA deflection onto the AGC rotational-hand-controller
/// counter channels exactly like the real station hardware: an 8% center dead
/// zone, ±42 counts at nominal full (10°) travel, and a ±57-count mechanical
/// clamp that stops out-of-range analog excursions at the physical stops.
struct LMACAInputMapper: Equatable, Sendable {
    static let deadZoneFraction = 0.08
    static let nominalDeflectionCounts = 42
    static let mechanicalClampCounts = 57

    func counts(for axisValue: Double) -> Int {
        let magnitude = abs(axisValue)
        guard magnitude > Self.deadZoneFraction else { return 0 }
        let scaled = magnitude * Double(Self.nominalDeflectionCounts)
        let clamped = min(scaled, Double(Self.mechanicalClampCounts))
        let counts = Int(clamped.rounded())
        return axisValue < 0 ? -counts : counts
    }

    /// Sum a discrete button command and an analog axis, honoring the
    /// mechanical clamp in both directions.
    func combined(buttonCounts: Int, normalizedAxis: Double) -> Int {
        let total = buttonCounts + counts(for: normalizedAxis)
        return min(max(total, -Self.mechanicalClampCounts), Self.mechanicalClampCounts)
    }
}
