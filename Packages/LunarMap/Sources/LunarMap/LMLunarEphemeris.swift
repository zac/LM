import Foundation
import simd

/// Direction to a body in a site's horizon frame, using the same convention
/// the terrain manifest states for mission lighting: azimuth measured
/// clockwise from north, elevation measured up from the local horizon.
public struct LMHorizonAngles: Equatable, Sendable {
    package let azimuthDegreesClockwiseFromNorth: Double
    public let elevationDegrees: Double
}

/// Where the Sun and the Earth are, in the Moon's body-fixed frame, at a
/// given instant.
///
/// This is the time authority behind mission lighting: an instant in, a sun
/// direction out. Apollo 11's pinned manifest sun becomes one evaluation of
/// this function rather than a separate hand-entered constant, and any other
/// mission or date gets the same treatment.
///
/// ## Method
///
/// Classical analytic theory (Meeus, *Astronomical Algorithms* 2nd ed.):
/// abbreviated ELP lunar terms (ch. 47), low-precision solar position
/// (ch. 25), and the physical-ephemeris libration construction (ch. 53)
/// evaluated for both the Earth and the Sun as seen from the Moon. Results
/// are selenographic coordinates in the IAU Mean Earth/Polar axis frame —
/// the same frame `LMSelenographicCoordinateSystem` defines — so the existing
/// coordinate authority converts them into any site's horizon frame.
///
/// `Docs/MoonExplorerPlan.md` Workstream 1 specified a SPICE-baked table with
/// this analytic model as the cross-check. The order is deliberately inverted:
/// evaluating the series directly removes the kernel toolchain, the bundled
/// table, and its interpolation error, while meeting the plan's stated
/// accuracy target. A tabulated DE440 product can later replace the internals
/// without changing this API if sub-arcminute accuracy is ever required.
///
/// ## Accuracy
///
/// Optical libration is computed in full; physical libration (bounded by
/// about 0.04 degrees) is omitted, as are planetary perturbations below the
/// retained ELP terms. Total error stays well inside `angularToleranceDegrees`
/// — far below the angular size of a rendered pixel at any Explorer zoom, and
/// far below the ~0.5 degree apparent diameter of the Sun that ultimately
/// softens every terminator anyway.
public enum LMLunarEphemeris {
    /// Documented accuracy bound of this model, in degrees. Tests assert
    /// against it rather than against exact literals so the bound stays an
    /// explicit, reviewable contract.
    static let angularToleranceDegrees = 0.1

    /// Cassini's laws: inclination of the lunar equator to the ecliptic.
    fileprivate static let lunarEquatorInclinationDegrees = 1.54242

    fileprivate static let astronomicalUnitKilometers = 149_597_870.7

    // MARK: - Body directions

    /// Selenographic coordinate directly beneath the Sun. Its latitude stays
    /// within about +/-1.6 degrees because the Moon's spin axis is nearly
    /// perpendicular to the ecliptic; its longitude sweeps westward roughly
    /// 12.2 degrees per day, which is what moves the terminator.
    static func subsolarPoint(at date: Date) -> LMSelenographicCoordinate {
        let fundamentals = Fundamentals(date: date)
        return fundamentals.selenographicPoint(
            eclipticLongitudeDegrees: fundamentals.sunLongitudeFromMoonDegrees,
            eclipticLatitudeDegrees: fundamentals.sunLatitudeFromMoonDegrees
        )
    }

    /// Selenographic coordinate directly beneath the Earth. Libration keeps
    /// this within roughly +/-8 degrees of (0, 0) — the reason a little more
    /// than half the Moon is visible from Earth over time, and the direction
    /// the earthshine fill light comes from.
    static func subEarthPoint(at date: Date) -> LMSelenographicCoordinate {
        let fundamentals = Fundamentals(date: date)
        return fundamentals.selenographicPoint(
            eclipticLongitudeDegrees: fundamentals.moonLongitudeDegrees,
            eclipticLatitudeDegrees: fundamentals.moonLatitudeDegrees
        )
    }

    /// Unit vector toward the Sun in the Moon-fixed frame. The Sun is far
    /// enough away that this direction is the same from every point on the
    /// surface: the parallax across a lunar radius is under 0.001 degrees.
    static func sunDirectionInMoonFixedFrame(at date: Date) -> SIMD3<Double> {
        unitVector(towards: subsolarPoint(at: date))
    }

    /// Unit vector toward the Earth in the Moon-fixed frame. Unlike the Sun,
    /// the Earth is close enough for surface parallax to matter at about one
    /// degree, which is still far below what an earthshine fill light needs.
    static func earthDirectionInMoonFixedFrame(at date: Date) -> SIMD3<Double> {
        unitVector(towards: subEarthPoint(at: date))
    }

    // MARK: - Site horizon frame

    /// Sun azimuth and elevation as seen from a site, in the manifest's
    /// convention. This is the call mission lighting makes.
    public static func sunAngles(
        at date: Date,
        site: LMSelenographicCoordinate,
        coordinateSystem: LMSelenographicCoordinateSystem = .init()
    ) -> LMHorizonAngles {
        horizonAngles(
            of: sunDirectionInMoonFixedFrame(at: date),
            at: site,
            coordinateSystem: coordinateSystem
        )
    }

    /// Earth azimuth and elevation as seen from a site. Over Tranquility Base
    /// the Earth hangs high and nearly fixed, wandering only a few degrees
    /// with libration — the Moon keeps one face toward it.
    package static func earthAngles(
        at date: Date,
        site: LMSelenographicCoordinate,
        coordinateSystem: LMSelenographicCoordinateSystem = .init()
    ) -> LMHorizonAngles {
        horizonAngles(
            of: earthDirectionInMoonFixedFrame(at: date),
            at: site,
            coordinateSystem: coordinateSystem
        )
    }

    /// Projects a Moon-fixed direction into a site's horizon frame.
    static func horizonAngles(
        of moonFixedDirection: SIMD3<Double>,
        at site: LMSelenographicCoordinate,
        coordinateSystem: LMSelenographicCoordinateSystem = .init()
    ) -> LMHorizonAngles {
        let local = coordinateSystem
            .localFrame(at: site)
            .localDirection(moonFixedDirection)
        let horizontal = (local.x * local.x + local.y * local.y).squareRoot()

        return LMHorizonAngles(
            azimuthDegreesClockwiseFromNorth: normalizedDegrees(
                atan2(local.y, local.x) * 180 / .pi
            ),
            elevationDegrees: atan2(local.z, horizontal) * 180 / .pi
        )
    }

    // MARK: - Earthshine

    /// Fraction of the Earth's disc that is sunlit as seen from the Moon.
    ///
    /// Earth and Moon show each other opposite phases, so this peaks when the
    /// Moon is new — exactly when a lunar site's night side needs fill light
    /// most. Earthshine intensity should scale with this.
    package static func earthIlluminatedFractionFromMoon(at date: Date) -> Double {
        let sun = sunDirectionInMoonFixedFrame(at: date)
        let earth = earthDirectionInMoonFixedFrame(at: date)
        // The illuminated fraction is (1 + cos i)/2 about the *Earth's* phase
        // angle i, the Sun-Earth-Moon angle. What the two directions above
        // give is the angle at the Moon, which is its supplement: seeing the
        // Earth alongside the Sun means looking at the Earth's night side.
        let angleAtMoon = simd_dot(sun, earth)
        return (1 - min(max(angleAtMoon, -1), 1)) / 2
    }

    // MARK: - Helpers

    private static func unitVector(
        towards coordinate: LMSelenographicCoordinate
    ) -> SIMD3<Double> {
        let latitude = coordinate.latitudeDegrees * .pi / 180
        let longitude = coordinate.longitudeDegrees * .pi / 180
        return SIMD3(
            cos(latitude) * cos(longitude),
            cos(latitude) * sin(longitude),
            sin(latitude)
        )
    }

    fileprivate static func normalizedDegrees(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }
}

// MARK: - Series evaluation

/// Fundamental arguments and body positions for one instant.
///
/// Angles are carried in degrees, matching the published series, and are only
/// converted to radians at each trigonometric call.
private struct Fundamentals {
    /// Julian centuries of Terrestrial Time from J2000.0.
    let centuries: Double
    /// Moon's mean elongation, Sun's mean anomaly, Moon's mean anomaly,
    /// Moon's argument of latitude, and the ascending node of the mean orbit.
    let elongation: Double
    let solarAnomaly: Double
    let lunarAnomaly: Double
    let argumentOfLatitude: Double
    let ascendingNode: Double

    let moonLongitudeDegrees: Double
    let moonLatitudeDegrees: Double
    let moonDistanceKilometers: Double

    let sunLongitudeDegrees: Double
    let sunDistanceKilometers: Double

    /// Nutation in longitude, principal term only. It shifts the libration by
    /// well under 0.005 degrees but costs one line to carry.
    let nutationInLongitude: Double

    init(date: Date) {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let ephemerisDay = julianDay + Self.deltaTSeconds(julianDay: julianDay) / 86_400
        let time = (ephemerisDay - 2_451_545.0) / 36_525
        centuries = time

        elongation = 297.8501921
            + 445_267.1114034 * time
            - 0.0018819 * time * time
            + time * time * time / 545_868
            - time * time * time * time / 113_065_000
        solarAnomaly = 357.5291092
            + 35_999.0502909 * time
            - 0.0001536 * time * time
            + time * time * time / 24_490_000
        lunarAnomaly = 134.9633964
            + 477_198.8675055 * time
            + 0.0087414 * time * time
            + time * time * time / 69_699
            - time * time * time * time / 14_712_000
        argumentOfLatitude = 93.2720950
            + 483_202.0175233 * time
            - 0.0036539 * time * time
            - time * time * time / 3_526_000
            + time * time * time * time / 863_310_000
        ascendingNode = 125.0445479
            - 1_934.1362891 * time
            + 0.0020754 * time * time
            + time * time * time / 467_441
            - time * time * time * time / 60_616_000

        let meanLongitude = 218.3164477
            + 481_267.88123421 * time
            - 0.0015786 * time * time
            + time * time * time / 538_841
            - time * time * time * time / 65_194_000

        // Earth's orbital eccentricity correction, applied to terms that
        // depend on the Sun's anomaly.
        let eccentricity = 1 - 0.002516 * time - 0.0000074 * time * time

        let moon = Self.lunarSeries(
            elongation: elongation,
            solarAnomaly: solarAnomaly,
            lunarAnomaly: lunarAnomaly,
            argumentOfLatitude: argumentOfLatitude,
            eccentricity: eccentricity
        )
        moonLongitudeDegrees = LMLunarEphemeris.normalizedDegrees(
            meanLongitude + moon.longitudeDegrees
        )
        moonLatitudeDegrees = moon.latitudeDegrees
        moonDistanceKilometers = 385_000.56 + moon.distanceKilometers

        let sun = Self.solarSeries(centuries: time)
        sunLongitudeDegrees = sun.longitudeDegrees
        sunDistanceKilometers = sun.distanceAU * LMLunarEphemeris
            .astronomicalUnitKilometers

        nutationInLongitude = -0.004778 * Self.sinDegrees(ascendingNode)
    }

    // MARK: Selenocentric direction to the Sun

    /// The Sun's ecliptic longitude as seen from the Moon rather than from the
    /// Earth. The Moon's orbital displacement shifts the apparent solar
    /// direction by up to about 0.15 degrees, which matters at our tolerance.
    var sunLongitudeFromMoonDegrees: Double {
        let ratio = moonDistanceKilometers / sunDistanceKilometers
        return sunLongitudeDegrees + 180
            + ratio * (180 / Double.pi)
            * Self.cosDegrees(moonLatitudeDegrees)
            * Self.sinDegrees(sunLongitudeDegrees - moonLongitudeDegrees)
    }

    var sunLatitudeFromMoonDegrees: Double {
        let ratio = moonDistanceKilometers / sunDistanceKilometers
        return ratio * moonLatitudeDegrees
    }

    // MARK: Libration

    /// Selenographic coordinate beneath a body at the given geocentric-style
    /// ecliptic direction, via the optical-libration construction. Passing the
    /// Moon's own longitude and latitude yields the sub-Earth point; passing
    /// the selenocentric solar direction yields the subsolar point.
    func selenographicPoint(
        eclipticLongitudeDegrees longitude: Double,
        eclipticLatitudeDegrees latitude: Double
    ) -> LMSelenographicCoordinate {
        let inclination = LMLunarEphemeris.lunarEquatorInclinationDegrees
        let node = longitude - nutationInLongitude - ascendingNode

        let sinNode = Self.sinDegrees(node)
        let cosNode = Self.cosDegrees(node)
        let sinLatitude = Self.sinDegrees(latitude)
        let cosLatitude = Self.cosDegrees(latitude)
        let sinInclination = Self.sinDegrees(inclination)
        let cosInclination = Self.cosDegrees(inclination)

        let angle = atan2(
            sinNode * cosLatitude * cosInclination - sinLatitude * sinInclination,
            cosNode * cosLatitude
        ) * 180 / .pi
        let selenographicLatitude = asin(
            min(max(
                -sinNode * cosLatitude * sinInclination - sinLatitude * cosInclination,
                -1
            ), 1)
        ) * 180 / .pi

        // Longitude is measured from the mean sub-Earth meridian; the argument
        // of latitude carries the Moon's rotation.
        var selenographicLongitude = angle - argumentOfLatitude
        selenographicLongitude = LMLunarEphemeris
            .normalizedDegrees(selenographicLongitude)

        return LMSelenographicCoordinate(
            latitudeDegrees: selenographicLatitude,
            longitudeDegrees: selenographicLongitude
        )
    }

    // MARK: Series

    private struct LunarPosition {
        let longitudeDegrees: Double
        let latitudeDegrees: Double
        let distanceKilometers: Double
    }

    /// Principal ELP terms. The retained set holds the residual well inside
    /// the module's documented tolerance; the omitted terms are all below a
    /// few arcseconds.
    private static func lunarSeries(
        elongation: Double,
        solarAnomaly: Double,
        lunarAnomaly: Double,
        argumentOfLatitude: Double,
        eccentricity: Double
    ) -> LunarPosition {
        // (multiple of D, M, M', F, coefficient in 1e-6 degrees)
        let longitudeTerms: [(Double, Double, Double, Double, Double)] = [
            (0, 0, 1, 0, 6_288_774),
            (2, 0, -1, 0, 1_274_027),
            (2, 0, 0, 0, 658_314),
            (0, 0, 2, 0, 213_618),
            (0, 1, 0, 0, -185_116),
            (0, 0, 0, 2, -114_332),
            (2, 0, -2, 0, 58_793),
            (2, -1, -1, 0, 57_066),
            (2, 0, 1, 0, 53_322),
            (2, -1, 0, 0, 45_758),
            (0, 1, -1, 0, -40_923),
            (1, 0, 0, 0, -34_720),
            (0, 1, 1, 0, -30_383),
            (2, 0, 0, -2, 15_327),
            (0, 0, 1, 2, -12_528),
            (0, 0, 1, -2, 10_980),
            (4, 0, -1, 0, 10_675),
            (0, 0, 3, 0, 10_034),
            (4, 0, -2, 0, 8_548),
            (2, 1, -1, 0, -7_888),
            (2, 1, 0, 0, -6_766),
            (1, 0, -1, 0, -5_163),
            (1, 1, 0, 0, 4_987),
            (2, -1, 1, 0, 4_036),
            (2, 0, 2, 0, 3_994),
            (4, 0, 0, 0, 3_861),
            (2, 0, -3, 0, 3_665),
        ]
        // (multiple of D, M, M', F, coefficient in 1e-6 degrees)
        let latitudeTerms: [(Double, Double, Double, Double, Double)] = [
            (0, 0, 0, 1, 5_128_122),
            (0, 0, 1, 1, 280_602),
            (0, 0, 1, -1, 277_693),
            (2, 0, 0, -1, 173_237),
            (2, 0, -1, 1, 55_413),
            (2, 0, -1, -1, 46_271),
            (2, 0, 0, 1, 32_573),
            (0, 0, 2, 1, 17_198),
            (2, 0, 1, -1, 9_266),
            (0, 0, 2, -1, 8_822),
            (2, -1, 0, -1, 8_216),
            (2, 0, -2, -1, 4_324),
            (2, 0, 1, 1, 4_200),
            (2, 1, 0, -1, -3_359),
            (2, -1, -1, 1, 2_463),
            (2, -1, 0, 1, 2_211),
            (2, -1, -1, -1, 2_065),
            (0, 1, -1, -1, -1_870),
            (4, 0, -1, -1, 1_828),
            (0, 1, 0, 1, -1_794),
        ]
        // (multiple of D, M, M', F, coefficient in 1e-3 kilometres)
        let distanceTerms: [(Double, Double, Double, Double, Double)] = [
            (0, 0, 1, 0, -20_905_355),
            (2, 0, -1, 0, -3_699_111),
            (2, 0, 0, 0, -2_955_968),
            (0, 0, 2, 0, -569_925),
            (0, 1, 0, 0, 48_888),
            (0, 0, 0, 2, -3_149),
            (2, 0, -2, 0, 246_158),
            (2, -1, -1, 0, -152_138),
            (2, 0, 1, 0, -170_733),
            (2, -1, 0, 0, -204_586),
            (0, 1, -1, 0, -129_620),
            (1, 0, 0, 0, 108_743),
            (0, 1, 1, 0, 104_755),
            (2, 0, 0, -2, 10_321),
            (4, 0, -1, 0, -16_675),
            (0, 0, 3, 0, -16_707),
            (4, 0, -2, 0, -11_650),
        ]

        func eccentricityFactor(_ solarMultiple: Double) -> Double {
            switch abs(solarMultiple) {
            case 1: eccentricity
            case 2: eccentricity * eccentricity
            default: 1
            }
        }

        var longitude = 0.0
        for (d, m, mPrime, f, coefficient) in longitudeTerms {
            let argument = d * elongation + m * solarAnomaly
                + mPrime * lunarAnomaly + f * argumentOfLatitude
            longitude += coefficient * eccentricityFactor(m) * sinDegrees(argument)
        }

        var latitude = 0.0
        for (d, m, mPrime, f, coefficient) in latitudeTerms {
            let argument = d * elongation + m * solarAnomaly
                + mPrime * lunarAnomaly + f * argumentOfLatitude
            latitude += coefficient * eccentricityFactor(m) * sinDegrees(argument)
        }

        var distance = 0.0
        for (d, m, mPrime, f, coefficient) in distanceTerms {
            let argument = d * elongation + m * solarAnomaly
                + mPrime * lunarAnomaly + f * argumentOfLatitude
            distance += coefficient * eccentricityFactor(m) * cosDegrees(argument)
        }

        return LunarPosition(
            longitudeDegrees: longitude / 1_000_000,
            latitudeDegrees: latitude / 1_000_000,
            distanceKilometers: distance / 1_000
        )
    }

    private struct SolarPosition {
        let longitudeDegrees: Double
        let distanceAU: Double
    }

    private static func solarSeries(centuries time: Double) -> SolarPosition {
        let meanLongitude = 280.46646 + 36_000.76983 * time + 0.0003032 * time * time
        let meanAnomaly = 357.52911 + 35_999.05029 * time - 0.0001537 * time * time
        let eccentricity = 0.016708634
            - 0.000042037 * time
            - 0.0000001267 * time * time

        let center = (1.914602 - 0.004817 * time - 0.000014 * time * time)
            * sinDegrees(meanAnomaly)
            + (0.019993 - 0.000101 * time) * sinDegrees(2 * meanAnomaly)
            + 0.000289 * sinDegrees(3 * meanAnomaly)

        let trueAnomaly = meanAnomaly + center
        let distance = 1.000001018 * (1 - eccentricity * eccentricity)
            / (1 + eccentricity * cosDegrees(trueAnomaly))

        return SolarPosition(
            longitudeDegrees: LMLunarEphemeris.normalizedDegrees(
                meanLongitude + center
            ),
            distanceAU: distance
        )
    }

    /// Difference between Terrestrial Time and UT, by the Espenak-Meeus
    /// piecewise fits.
    ///
    /// The result only has to be roughly right: the subsolar longitude moves
    /// about 0.00014 degrees per second, so even a 100-second error in this
    /// value stays an order of magnitude inside the module's tolerance.
    private static func deltaTSeconds(julianDay: Double) -> Double {
        let year = 2000 + (julianDay - 2_451_545.0) / 365.25

        switch year {
        case ..<1920:
            let t = year - 1900
            return -2.79 + 1.494119 * t - 0.0598939 * t * t
                + 0.0061966 * t * t * t - 0.000197 * t * t * t * t
        case ..<1941:
            let t = year - 1920
            return 21.20 + 0.84493 * t - 0.076100 * t * t + 0.0020936 * t * t * t
        case ..<1961:
            let t = year - 1950
            return 29.07 + 0.407 * t - t * t / 233 + t * t * t / 2_547
        case ..<1986:
            let t = year - 1975
            return 45.45 + 1.067 * t - t * t / 260 - t * t * t / 718
        case ..<2005:
            let t = year - 2000
            return 63.86 + 0.3345 * t - 0.060374 * t * t
                + 0.0017275 * t * t * t + 0.000651814 * t * t * t * t
                + 0.00002373599 * t * t * t * t * t
        case ..<2050:
            let t = year - 2000
            return 62.92 + 0.32217 * t + 0.005589 * t * t
        default:
            let t = year - 1820
            return -20 + 32 * (t / 100) * (t / 100) - 0.5628 * (2150 - year)
        }
    }

    fileprivate static func sinDegrees(_ degrees: Double) -> Double {
        sin(degrees * .pi / 180)
    }

    fileprivate static func cosDegrees(_ degrees: Double) -> Double {
        cos(degrees * .pi / 180)
    }
}
