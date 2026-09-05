import Foundation
import LMCore

/// Local gear dynamics against one immutable rendered generation. This does
/// not retarget the Apollo AGC pad load or pretend to validate its guidance.
struct LMLunarLandingRehearsal {
    let surface: LMTerrainContactSurface
    private(set) var position: LMVector3D
    private(set) var velocity = LMVector3D(z: -0.5)
    private(set) var attitude = LMQuaternion.identity
    private(set) var angularVelocity = LMVector3D.zero
    private(set) var gear = LMLandingGearState()
    private(set) var isSettled = false
    private(set) var elapsed = 0.0

    init(surface: LMTerrainContactSurface, north: Double, east: Double) {
        self.surface = surface
        // Clear all four pads, including relief above the center sample.
        let highest = LMLandingGearLeg.allCases.map {
            let pad = LMLandingGearGeometry.footpadBody($0, strokeMeters: 0)
            return surface.surfaceHeightMeters(northMeters: north + pad.x, eastMeters: east + pad.y)
        }.max() ?? 0
        position = .init(x: north, y: east, z: highest + 0.5)
    }

    mutating func step(seconds: Double = 1.0 / 60.0) {
        guard !isSettled, gear.failure == nil, elapsed < 30 else { return }
        let mass = LMLandingGearGeometry.designTouchdownMassKilograms
        let result = LMLandingGearDynamics.integrate(
            positionMeters: position, velocityMetersPerSecond: velocity, attitude: attitude,
            angularVelocityRadiansPerSecond: angularVelocity, massKilograms: mass,
            inertiaKilogramMetersSquared: LMInertiaMap.diagonalInertiaKilogramMetersSquared(massKilograms: mass),
            accelerationMetersPerSecondSquared: .init(z: -LMVehicleConfiguration.sourceBackedDefault.lunarGravityMetersPerSecondSquared.value),
            angularAccelerationRadiansPerSecondSquared: .zero, gear: gear, surface: surface, deltaTime: seconds)
        position = result.positionMeters; velocity = result.velocityMetersPerSecond
        attitude = result.attitude; angularVelocity = result.angularVelocityRadiansPerSecond
        gear = result.gear; isSettled = result.isSettled; elapsed += seconds
    }

    var finished: Bool { isSettled || gear.failure != nil || elapsed >= 30 }
    var message: String {
        if isSettled { return String(format: "Settled after %.2f s", elapsed) }
        if let failure = gear.failure { return "Landing failed: \(failure)" }
        return elapsed >= 30 ? "Landing did not settle within 30 s" : "Dropping onto the visible terrain"
    }
}
