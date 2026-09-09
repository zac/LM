import Foundation
import LMCore

/// Presentation of simulated geometric state, not a radar/PGNS/AGS instrument signal.
struct LMAltitudeRateReading: Equatable {
    let altitudeFeet: Double?
    let rateFeetPerSecond: Double?
    static let metersPerFoot = 0.3048

    init(altitudeMeters: Double?, radialRateMetersPerSecond: Double?) {
        altitudeFeet = Self.valid(altitudeMeters, range: 0...60_000)
        rateFeetPerSecond = Self.valid(radialRateMetersPerSecond, range: -700...700)
    }
    init(state: LMVehicleStateSnapshot?) {
        self.init(altitudeMeters: state?.altitudeMeters,
                  radialRateMetersPerSecond: state?.verticalSpeedMetersPerSecond)
    }
    private static func valid(_ meters: Double?, range: ClosedRange<Double>) -> Double? {
        guard let meters, meters.isFinite else { return nil }
        let feet = meters / metersPerFoot
        return range.contains(feet) ? feet : nil
    }
}

/// Piecewise authoring calibration. Knots are physical tape coordinates, not a
/// historical electrical transfer function or a replacement navigation model.
struct LMTapeScale {
    let knots: [[Double]]
    let signed: Bool

    var isValid: Bool {
        guard knots.count >= 2, knots.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) }) else { return false }
        return zip(knots, knots.dropFirst()).allSatisfy { $0[0] < $1[0] && $0[1] < $1[1] }
    }
    func coordinate(for value: Double) -> Double? {
        guard isValid, value.isFinite else { return nil }
        let input = signed ? abs(value) : value
        guard input >= knots[0][0], input <= knots[knots.count - 1][0] else { return nil }
        let sign = signed && value < 0 ? -1.0 : 1.0
        for (a, b) in zip(knots, knots.dropFirst()) where input <= b[0] {
            return sign * (a[1] + (b[1] - a[1]) * (input - a[0]) / (b[0] - a[0]))
        }
        return nil
    }
}

/// Later LAD-inspired surface/yaw velocity aid. Sign convention is an explicit
/// fly-to interpretation of Luminary memos 165/171, not Luminary 099 output.
struct LMCrossPointerReading: Equatable {
    let rightFeetPerSecond: Double
    let forwardFeetPerSecond: Double
    var isSaturated: Bool { abs(rightFeetPerSecond) > 20 || abs(forwardFeetPerSecond) > 20 }
    var lateralFraction: Float { Float(-min(max(rightFeetPerSecond / 20, -1), 1)) }
    var forwardFraction: Float { Float(min(max(forwardFeetPerSecond / 20, -1), 1)) }

    init?(state: LMVehicleStateSnapshot?, program: Int?) {
        guard let state, let program, (63...67).contains(program),
              state.flightOutcome == .inFlight || state.flightOutcome.isIntactLanding else { return nil }
        let moon = LMAGCNavState.moonCenteredPositionMeters(from: state)
        let (north, east, up) = LMAGCNavState.moonFixedSiteBasis(site: state.landingSite)
        let radialUp = LMVector3D(x: moon.dot(north), y: moon.dot(east), z: moon.dot(up))
        self.init(velocity: state.velocityMetersPerSecond,
                  bodyForward: state.attitude.rotated(LMVector3D(y: 1)), radialUp: radialUp)
    }
    init?(velocity: LMVector3D, bodyForward: LMVector3D, radialUp: LMVector3D) {
        let values = [velocity.x, velocity.y, velocity.z, bodyForward.x, bodyForward.y, bodyForward.z,
                      radialUp.x, radialUp.y, radialUp.z]
        guard values.allSatisfy(\.isFinite), radialUp.magnitude > 0.0001 else { return nil }
        let up = radialUp.normalized()
        let projected = bodyForward - up * bodyForward.dot(up)
        // An almost vertical forward axis has no reliable yaw heading.
        guard projected.magnitude > 0.001 else { return nil }
        let forward = projected.normalized()
        let right = forward.cross(up).normalized()
        let horizontal = velocity - up * velocity.dot(up)
        rightFeetPerSecond = horizontal.dot(right) / LMAltitudeRateReading.metersPerFoot
        forwardFeetPerSecond = horizontal.dot(forward) / LMAltitudeRateReading.metersPerFoot
    }
}
