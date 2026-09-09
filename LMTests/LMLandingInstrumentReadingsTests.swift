import Testing
@testable import LM

struct LMLandingInstrumentReadingsTests {
    @Test func altitudeAndRadialRateUseFeetAndPreserveUpPositive() {
        let reading = LMAltitudeRateReading(altitudeMeters: 304.8, radialRateMetersPerSecond: -3.048)
        #expect(reading.altitudeFeet == 1000)
        #expect(reading.rateFeetPerSecond == -10)
        #expect(LMAltitudeRateReading(altitudeMeters: 0, radialRateMetersPerSecond: 0).altitudeFeet == 0)
    }
    @Test func invalidValuesDoNotBecomePlausibleZeroOrClampedLimits() {
        for value in [Double.nan, .infinity, -.infinity] {
            let reading = LMAltitudeRateReading(altitudeMeters: value, radialRateMetersPerSecond: value)
            #expect(reading.altitudeFeet == nil && reading.rateFeetPerSecond == nil)
        }
        #expect(LMAltitudeRateReading(altitudeMeters: -1, radialRateMetersPerSecond: 214).altitudeFeet == nil)
        #expect(LMAltitudeRateReading(altitudeMeters: 18_289, radialRateMetersPerSecond: 214).rateFeetPerSecond == nil)
        #expect(LMAltitudeRateReading(state: nil).altitudeFeet == nil)
    }
    @Test func tapeInterpolationUsesKnotsAndNeverExtrapolates() {
        let altitude = LMTapeScale(knots: [[0, 0], [1000, 0.20], [10000, 0.38], [60000, 0.58]], signed: false)
        #expect(altitude.coordinate(for: 500) == 0.10)
        #expect(altitude.coordinate(for: 1000) == 0.20)
        #expect(altitude.coordinate(for: 60001) == nil)
        #expect(altitude.coordinate(for: .nan) == nil)
        let rate = LMTapeScale(knots: [[0, 0], [20, 0.08], [100, 0.24], [700, 0.48]], signed: true)
        #expect(rate.coordinate(for: -10) == -0.04)
        #expect(rate.coordinate(for: 10) == 0.04)
        #expect(rate.coordinate(for: -701) == nil)
        #expect(!LMTapeScale(knots: [[0, 0], [0, 1]], signed: false).isValid)
    }
}

extension LMLandingInstrumentReadingsTests {
    @Test func crossPointerUsesLaterFlyToSignsAndDropsRadialVelocity() throws {
        let reading = try #require(LMCrossPointerReading(velocity: .init(x: 3.048, y: 6.096, z: -100),
            bodyForward: .init(y: 1), radialUp: .init(z: 1)))
        #expect(abs(reading.rightFeetPerSecond - 10) < 0.00001)
        #expect(abs(reading.forwardFeetPerSecond - 20) < 0.00001)
        #expect(reading.lateralFraction == -0.5)
        #expect(reading.forwardFraction == 1)
        let yawed = try #require(LMCrossPointerReading(velocity: .init(x: 6.096),
            bodyForward: .init(x: 1), radialUp: .init(z: 1)))
        #expect(abs(yawed.forwardFeetPerSecond - 20) < 0.00001)
        #expect(abs(yawed.rightFeetPerSecond) < 0.00001)
        let pitched = try #require(LMCrossPointerReading(velocity: .init(z: -30),
            bodyForward: .init(y: 0.5, z: 0.866), radialUp: .init(z: 1)))
        #expect(pitched.forwardFeetPerSecond == 0 && pitched.rightFeetPerSecond == 0)
    }
    @Test func crossPointerRejectsUnknownHeadingAndSourceAndSaturatesFiniteSpeed() throws {
        #expect(LMCrossPointerReading(velocity: .init(x: .nan), bodyForward: .init(y: 1), radialUp: .init(z: 1)) == nil)
        #expect(LMCrossPointerReading(velocity: .zero, bodyForward: .init(z: 1), radialUp: .init(z: 1)) == nil)
        #expect(LMCrossPointerReading(state: nil, program: 66) == nil)
        let capped = try #require(LMCrossPointerReading(velocity: .init(x: 100, y: -100),
            bodyForward: .init(y: 1), radialUp: .init(z: 1)))
        #expect(capped.isSaturated && capped.lateralFraction == -1 && capped.forwardFraction == -1)
    }
}
