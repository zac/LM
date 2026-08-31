import Foundation
import Testing
import simd
@testable import LM

@Suite("Lunar ephemeris")
struct LMLunarEphemerisTests {
    /// Tranquility Base, from the bundled manifest's landing origin.
    private let apollo11 = LMSelenographicCoordinate(
        latitudeDegrees: 0.673433,
        longitudeDegrees: 23.473113
    )

    /// Eagle's touchdown, 1969-07-20 20:17:40 UTC.
    private let touchdown = Self.utc(1969, 7, 20, 20, 17, 40)

    // MARK: - Mission anchor

    /// The acceptance anchor from `Docs/MoonExplorerPlan.md`: evaluating the
    /// ephemeris at Apollo 11's touchdown has to reproduce the mission's
    /// documented sun, which is what makes every other date trustworthy.
    @Test func apollo11TouchdownReproducesTheDocumentedMissionSunElevation() throws {
        let angles = LMLunarEphemeris.sunAngles(at: touchdown, site: apollo11)
        let manifest = try LMTerrainManifest.load()

        // The Apollo 11 mission report quotes a sun elevation of 10.8 degrees
        // at landing, to one decimal; the manifest pins 10.77. Both agree with
        // the model inside its documented tolerance plus that rounding.
        #expect(
            abs(angles.elevationDegrees - manifest.sun.elevationDegrees)
                < LMLunarEphemeris.angularToleranceDegrees
        )
        #expect(
            abs(angles.elevationDegrees - 10.8)
                < LMLunarEphemeris.angularToleranceDegrees + 0.05
        )
    }

    /// The manifest's pinned mission sun is now this ephemeris evaluated at
    /// touchdown rather than a separately entered constant. Keeping the two
    /// tied together is what stops the pinned value drifting again — an
    /// earlier hand-entered azimuth pointed anti-solar and put every shadow in
    /// the scene on the wrong side.
    @Test func pinnedMissionSunMatchesTheEphemerisAtTouchdown() throws {
        let manifest = try LMTerrainManifest.load()
        let angles = LMLunarEphemeris.sunAngles(
            at: touchdown,
            site: manifest.landingOriginCoordinate
        )

        #expect(
            abs(angles.elevationDegrees - manifest.sun.elevationDegrees) < 0.01
        )
        #expect(
            abs(
                angles.azimuthDegreesClockwiseFromNorth
                    - manifest.sun.azimuthDegreesClockwiseFromNorth
            ) < 0.01
        )
    }

    /// Landing happened in local morning with the Sun low in the east, which
    /// is what casts the long westward shadows across the approach.
    ///
    /// The manifest's pinned azimuth of 276.4 degrees is the *anti-solar*
    /// direction — its own note calls it "approximated west-southwest". The
    /// elevation anchor above is what proves the sign convention here: a
    /// subsolar longitude west of the site would put the Sun below the
    /// horizon at this instant, not 10.7 degrees above it. Correcting the
    /// manifest is deliberately left as a separate decision because it moves
    /// every shadow in every existing capture baseline.
    @Test func apollo11SunSitsLowInTheMorningEasternSky() {
        let angles = LMLunarEphemeris.sunAngles(at: touchdown, site: apollo11)

        #expect(angles.azimuthDegrees(isWithin: 80...100))
        #expect(angles.elevationDegrees > 10)
        #expect(angles.elevationDegrees < 12)

        // Local morning: the Sun is climbing, and had risen roughly a day
        // earlier at the Moon's leisurely half-degree-per-hour pace.
        let sixHoursLater = LMLunarEphemeris.sunAngles(
            at: touchdown.addingTimeInterval(6 * 3_600),
            site: apollo11
        )
        let dayEarlier = LMLunarEphemeris.sunAngles(
            at: touchdown.addingTimeInterval(-24 * 3_600),
            site: apollo11
        )
        #expect(sixHoursLater.elevationDegrees > angles.elevationDegrees)
        #expect(dayEarlier.elevationDegrees < 0)
    }

    /// The Earth hangs high over the near-side landing site and stays there;
    /// this is the direction the earthshine fill light comes from.
    @Test func earthStaysHighAndNearlyFixedOverTranquilityBase() {
        var minimumElevation = Double.greatestFiniteMagnitude
        var maximumElevation = -Double.greatestFiniteMagnitude

        for day in stride(from: 0.0, through: 60.0, by: 0.5) {
            let angles = LMLunarEphemeris.earthAngles(
                at: touchdown.addingTimeInterval(day * 86_400),
                site: apollo11
            )
            minimumElevation = min(minimumElevation, angles.elevationDegrees)
            maximumElevation = max(maximumElevation, angles.elevationDegrees)
        }

        // Tidal lock keeps the Earth aloft; libration alone moves it, and only
        // by a handful of degrees.
        #expect(minimumElevation > 50)
        #expect(maximumElevation < 75)
        #expect(maximumElevation - minimumElevation < 20)
    }

    // MARK: - Physical invariants

    /// The Moon's spin axis is nearly perpendicular to the ecliptic, so the
    /// Sun never wanders far from its equator. This is why polar illumination
    /// is such a knife edge and why every other site sees a near-vertical
    /// terminator sweep.
    @Test func subsolarLatitudeStaysWithinTheLunarAxialTilt() {
        for step in stride(from: 0.0, through: 800.0, by: 0.37) {
            let point = LMLunarEphemeris.subsolarPoint(
                at: touchdown.addingTimeInterval(step * 86_400)
            )
            #expect(abs(point.latitudeDegrees) < 1.7)
        }
    }

    /// Libration is what lets Earth-based observers see about 59 percent of
    /// the surface, and it is bounded.
    @Test func subEarthPointStaysInsideTheLibrationEnvelope() {
        var maximumLatitude = 0.0
        var maximumLongitude = 0.0

        for step in stride(from: 0.0, through: 800.0, by: 0.37) {
            let point = LMLunarEphemeris.subEarthPoint(
                at: touchdown.addingTimeInterval(step * 86_400)
            )
            maximumLatitude = max(maximumLatitude, abs(point.latitudeDegrees))
            maximumLongitude = max(maximumLongitude, abs(point.longitudeDegrees))
        }

        #expect(maximumLatitude > 5)
        #expect(maximumLatitude < 8)
        #expect(maximumLongitude > 6)
        #expect(maximumLongitude < 9)
    }

    /// The terminator only ever sweeps one way, at the synodic rate. A sign
    /// error or a series discontinuity would show up here as a reversal.
    @Test func subsolarLongitudeSweepsWestwardAtTheSynodicRate() {
        let stepHours = 6.0
        var previous: Double?
        var totalDrift = 0.0
        var samples = 0

        for step in 0..<(4 * 365 * 2) {
            let point = LMLunarEphemeris.subsolarPoint(
                at: touchdown.addingTimeInterval(Double(step) * stepHours * 3_600)
            )
            if let previous {
                var delta = point.longitudeDegrees - previous
                if delta > 180 { delta -= 360 }
                if delta < -180 { delta += 360 }
                // Westward means decreasing east longitude, every single step.
                #expect(delta < 0)
                totalDrift += delta
                samples += 1
            }
            previous = point.longitudeDegrees
        }

        // A synodic month is 29.53 days, so 360/29.53 = 12.19 degrees per day.
        let degreesPerDay = totalDrift / Double(samples) * (24 / stepHours)
        #expect(abs(degreesPerDay + 12.19) < 0.05)
    }

    /// Earth and Moon show each other opposite phases. Earthshine is brightest
    /// exactly when a lunar site needs it most: local night under a full Earth.
    @Test func earthAndMoonPhasesAreComplementary() throws {
        // A full Moon puts the Sun over the near side, so the Earth is new.
        var fullMoonFraction: Double?
        var newMoonFraction: Double?

        for step in stride(from: 0.0, through: 30.0, by: 0.02) {
            let date = touchdown.addingTimeInterval(step * 86_400)
            let subsolar = LMLunarEphemeris.subsolarPoint(at: date)
            let subEarth = LMLunarEphemeris.subEarthPoint(at: date)
            let separation = abs(
                subsolar.longitudeDegrees - subEarth.longitudeDegrees
            )
            if separation < 0.5 {
                fullMoonFraction = LMLunarEphemeris
                    .earthIlluminatedFractionFromMoon(at: date)
            }
            if abs(separation - 180) < 0.5 {
                newMoonFraction = LMLunarEphemeris
                    .earthIlluminatedFractionFromMoon(at: date)
            }
        }

        #expect(try #require(fullMoonFraction) < 0.02)
        #expect(try #require(newMoonFraction) > 0.98)
    }

    @Test func illuminatedFractionStaysBounded() {
        for step in stride(from: 0.0, through: 400.0, by: 0.13) {
            let fraction = LMLunarEphemeris.earthIlluminatedFractionFromMoon(
                at: touchdown.addingTimeInterval(step * 86_400)
            )
            #expect(fraction >= 0)
            #expect(fraction <= 1)
        }
    }

    // MARK: - Frame integration

    /// The ephemeris reports Moon-fixed directions and lets the existing
    /// coordinate authority do every frame conversion, so a direction pointed
    /// at the subsolar point must read as straight overhead there.
    @Test func theSunIsOverheadAtItsOwnSubsolarPoint() {
        for step in stride(from: 0.0, through: 40.0, by: 1.7) {
            let date = touchdown.addingTimeInterval(step * 86_400)
            let subsolar = LMLunarEphemeris.subsolarPoint(at: date)
            let angles = LMLunarEphemeris.sunAngles(at: date, site: subsolar)
            #expect(abs(angles.elevationDegrees - 90) < 1e-6)
        }
    }

    /// Antipodal to the subsolar point it must be deep night.
    @Test func theSunIsDirectlyUnderfootAtTheAntisolarPoint() {
        let subsolar = LMLunarEphemeris.subsolarPoint(at: touchdown)
        let antipode = LMSelenographicCoordinate(
            latitudeDegrees: -subsolar.latitudeDegrees,
            longitudeDegrees: subsolar.longitudeDegrees + 180
        )
        let angles = LMLunarEphemeris.sunAngles(at: touchdown, site: antipode)

        #expect(abs(angles.elevationDegrees + 90) < 1e-6)
    }

    @Test func moonFixedDirectionsAreUnitLength() {
        for step in stride(from: 0.0, through: 60.0, by: 0.9) {
            let date = touchdown.addingTimeInterval(step * 86_400)
            let sun = LMLunarEphemeris.sunDirectionInMoonFixedFrame(at: date)
            let earth = LMLunarEphemeris.earthDirectionInMoonFixedFrame(at: date)
            #expect(abs(simd_length(sun) - 1) < 1e-12)
            #expect(abs(simd_length(earth) - 1) < 1e-12)
        }
    }

    /// Determinism is a standing contract for everything that feeds a bake or
    /// a cache key.
    @Test func evaluationIsDeterministic() {
        let first = LMLunarEphemeris.sunAngles(at: touchdown, site: apollo11)
        let second = LMLunarEphemeris.sunAngles(at: touchdown, site: apollo11)

        #expect(first == second)
        #expect(
            LMLunarEphemeris.subsolarPoint(at: touchdown)
                == LMLunarEphemeris.subsolarPoint(at: touchdown)
        )
    }

    // MARK: - Helpers

    private static func utc(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }
}

private extension LMHorizonAngles {
    func azimuthDegrees(isWithin range: ClosedRange<Double>) -> Bool {
        range.contains(azimuthDegreesClockwiseFromNorth)
    }
}
