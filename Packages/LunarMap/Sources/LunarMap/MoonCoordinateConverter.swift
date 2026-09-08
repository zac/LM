import Foundation
import simd

/// A position in the Moon's IAU Mean Earth/Polar axis body-fixed frame.
///
/// The axes are +X through 0 degrees latitude/longitude, +Y through
/// 0 degrees latitude/90 degrees east, and +Z through the north pole.
public struct LMMoonCenteredPosition: Equatable, Sendable {
    let xMeters: Double
    let yMeters: Double
    let zMeters: Double

    init(xMeters: Double, yMeters: Double, zMeters: Double) {
        self.xMeters = xMeters
        self.yMeters = yMeters
        self.zMeters = zMeters
    }

    package init(_ vector: SIMD3<Double>) {
        self.init(xMeters: vector.x, yMeters: vector.y, zMeters: vector.z)
    }

    package var vector: SIMD3<Double> {
        SIMD3(xMeters, yMeters, zMeters)
    }
}

/// Planetocentric lunar latitude, east-positive longitude, and height above
/// the configured lunar datum.
public struct LMSelenographicCoordinate: Equatable, Sendable {
    public let latitudeDegrees: Double
    public let longitudeDegrees: Double
    public let heightMeters: Double

    package init(
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        heightMeters: Double = 0
    ) {
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = Self.normalizedLongitude(longitudeDegrees)
        self.heightMeters = heightMeters
    }

    private static func normalizedLongitude(_ longitudeDegrees: Double) -> Double {
        guard longitudeDegrees.isFinite else { return longitudeDegrees }
        var result = longitudeDegrees.truncatingRemainder(dividingBy: 360)
        if result < -180 {
            result += 360
        } else if result >= 180 {
            result -= 360
        }
        return result == 0 ? 0 : result
    }
}

/// Site-local coordinates matching the production terrain convention:
/// +north, +east, and +up.
public struct LMSiteENUPosition: Equatable, Sendable {
    package let northMeters: Double
    package let eastMeters: Double
    let upMeters: Double

    public init(northMeters: Double, eastMeters: Double, upMeters: Double) {
        self.northMeters = northMeters
        self.eastMeters = eastMeters
        self.upMeters = upMeters
    }

    var vector: SIMD3<Double> {
        SIMD3(northMeters, eastMeters, upMeters)
    }
}

/// Single coordinate authority for Moon-fixed positions used by the Explorer,
/// terrain site frames, future globe chunks, and offline ephemeris products.
/// This module deliberately has no RealityKit dependency and keeps all
/// geodetic calculations in `Double`.
public struct LMSelenographicCoordinateSystem: Equatable, Sendable {
    /// IAU Mean Earth/Polar axis rendering datum used by LOLA/SLDEM products.
    public static let meanEarthPolarRadiusMeters = 1_737_400.0

    public let datumRadiusMeters: Double

    @usableFromInline package init(datumRadiusMeters: Double = Self.meanEarthPolarRadiusMeters) {
        precondition(datumRadiusMeters.isFinite && datumRadiusMeters > 0)
        self.datumRadiusMeters = datumRadiusMeters
    }

    package func moonCenteredPosition(
        for coordinate: LMSelenographicCoordinate
    ) -> LMMoonCenteredPosition {
        let latitude = coordinate.latitudeDegrees * .pi / 180
        let longitude = coordinate.longitudeDegrees * .pi / 180
        let radius = datumRadiusMeters + coordinate.heightMeters
        let latitudeRadius = radius * cos(latitude)

        return LMMoonCenteredPosition(
            xMeters: latitudeRadius * cos(longitude),
            yMeters: latitudeRadius * sin(longitude),
            zMeters: radius * sin(latitude)
        )
    }

    package func coordinate(
        for position: LMMoonCenteredPosition
    ) -> LMSelenographicCoordinate {
        let radius = simd_length(position.vector)
        precondition(radius.isFinite && radius > 0)

        return LMSelenographicCoordinate(
            // atan2 retains the small horizontal component at the poles;
            // asin(z / radius) can round that component away entirely.
            latitudeDegrees: atan2(
                position.zMeters, hypot(position.xMeters, position.yMeters)
            ) * 180 / .pi,
            longitudeDegrees: atan2(position.yMeters, position.xMeters) * 180 / .pi,
            heightMeters: radius - datumRadiusMeters
        )
    }

    package func localFrame(
        at anchor: LMSelenographicCoordinate
    ) -> LMSelenographicLocalFrame {
        LMSelenographicLocalFrame(coordinateSystem: self, anchor: anchor)
    }

    /// Projects a coordinate into the existing site terrain's local planar
    /// convention. This is intentionally distinct from `localFrame(at:)`:
    /// the production tiles use their declared equirectangular datum radius
    /// for horizontal map distances and carry elevation as a separate axis.
    func sitePosition(
        for coordinate: LMSelenographicCoordinate,
        relativeTo anchor: LMSelenographicCoordinate
    ) -> LMSiteENUPosition {
        let degreesToRadians = Double.pi / 180
        let anchorLatitude = anchor.latitudeDegrees * degreesToRadians
        let latitude = coordinate.latitudeDegrees * degreesToRadians
        let longitudeDelta = LMSelenographicCoordinate(
            latitudeDegrees: 0,
            longitudeDegrees: coordinate.longitudeDegrees - anchor.longitudeDegrees
        ).longitudeDegrees * degreesToRadians
        let meanLatitude = (anchorLatitude + latitude) / 2

        return LMSiteENUPosition(
            northMeters: (latitude - anchorLatitude) * datumRadiusMeters,
            eastMeters: longitudeDelta * datumRadiusMeters * cos(meanLatitude),
            upMeters: coordinate.heightMeters - anchor.heightMeters
        )
    }

    func coordinate(
        forSitePosition position: LMSiteENUPosition,
        relativeTo anchor: LMSelenographicCoordinate
    ) -> LMSelenographicCoordinate {
        let anchorLatitude = anchor.latitudeDegrees * .pi / 180
        let latitude = anchorLatitude + position.northMeters / datumRadiusMeters
        let meanLatitude = (anchorLatitude + latitude) / 2
        let longitude = anchor.longitudeDegrees * .pi / 180
            + position.eastMeters / (datumRadiusMeters * cos(meanLatitude))

        return LMSelenographicCoordinate(
            latitudeDegrees: latitude * 180 / .pi,
            longitudeDegrees: longitude * 180 / .pi,
            heightMeters: anchor.heightMeters + position.upMeters
        )
    }
}

/// Origin-relative tangent frame for a site on the Moon. The basis is exact
/// for the spherical ME datum; callers choose when a planar terrain should
/// intentionally discard the small radial curvature component.
public struct LMSelenographicLocalFrame: Equatable, Sendable {
    public let coordinateSystem: LMSelenographicCoordinateSystem
    public let anchor: LMSelenographicCoordinate

    private let anchorPosition: LMMoonCenteredPosition
    private let north: SIMD3<Double>
    private let east: SIMD3<Double>
    private let up: SIMD3<Double>

    init(
        coordinateSystem: LMSelenographicCoordinateSystem,
        anchor: LMSelenographicCoordinate
    ) {
        self.coordinateSystem = coordinateSystem
        self.anchor = anchor
        anchorPosition = coordinateSystem.moonCenteredPosition(for: anchor)

        let latitude = anchor.latitudeDegrees * .pi / 180
        let longitude = anchor.longitudeDegrees * .pi / 180
        north = SIMD3(
            -sin(latitude) * cos(longitude),
            -sin(latitude) * sin(longitude),
            cos(latitude)
        )
        east = SIMD3(-sin(longitude), cos(longitude), 0)
        up = SIMD3(
            cos(latitude) * cos(longitude),
            cos(latitude) * sin(longitude),
            sin(latitude)
        )
    }

    package func position(
        for coordinate: LMSelenographicCoordinate
    ) -> LMSiteENUPosition {
        position(for: coordinateSystem.moonCenteredPosition(for: coordinate))
    }

    func position(
        for moonCenteredPosition: LMMoonCenteredPosition
    ) -> LMSiteENUPosition {
        let delta = moonCenteredPosition.vector - anchorPosition.vector
        return LMSiteENUPosition(
            northMeters: simd_dot(delta, north),
            eastMeters: simd_dot(delta, east),
            upMeters: simd_dot(delta, up)
        )
    }

    /// Resolves a Moon-fixed direction into this frame's north, east, and up
    /// components. Directions carry no origin, so unlike `position(for:)` this
    /// only rotates. Mission lighting uses it to put an ephemeris sun
    /// direction into a site's horizon frame.
    package func localDirection(_ moonFixedDirection: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            simd_dot(moonFixedDirection, north),
            simd_dot(moonFixedDirection, east),
            simd_dot(moonFixedDirection, up)
        )
    }

    /// Inverse direction rotation, with no translation or height projection.
    package func moonFixedDirection(_ localDirection: SIMD3<Double>) -> SIMD3<Double> {
        north * localDirection.x + east * localDirection.y + up * localDirection.z
    }

    public func moonCenteredPosition(
        for position: LMSiteENUPosition
    ) -> LMMoonCenteredPosition {
        LMMoonCenteredPosition(
            anchorPosition.vector
                + north * position.northMeters
                + east * position.eastMeters
                + up * position.upMeters
        )
    }

    package func coordinate(
        for position: LMSiteENUPosition
    ) -> LMSelenographicCoordinate {
        coordinateSystem.coordinate(for: moonCenteredPosition(for: position))
    }
}

/// Compatibility adapter for the original prototype API. New code should use
/// `LMSelenographicCoordinateSystem` and retain `Double` until a chunk-local
/// position is handed to RealityKit.
@available(*, deprecated, message: "Use LMSelenographicCoordinateSystem")
enum MoonCoordinateConverter {
    static let lunarMeanRadius =
        LMSelenographicCoordinateSystem.meanEarthPolarRadiusMeters / 1_000

    static func latitudeLongitudeAltitudeToPosition(
        latitudeDeg: Double,
        longitudeDeg: Double,
        altitude: Double,
        scale: Double
    ) -> SIMD3<Float> {
        let position = LMSelenographicCoordinateSystem().moonCenteredPosition(
            for: LMSelenographicCoordinate(
                latitudeDegrees: latitudeDeg,
                longitudeDegrees: longitudeDeg,
                heightMeters: altitude * 1_000
            )
        )
        let kilometers = position.vector / 1_000

        // Preserve the prototype's RealityKit orientation: +Y north and
        // east-positive longitude toward -Z.
        return SIMD3(
            Float(kilometers.x * scale),
            Float(kilometers.z * scale),
            Float(-kilometers.y * scale)
        )
    }
}
