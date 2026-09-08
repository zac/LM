import Foundation
import simd

package struct LMLunarPOICatalog: Decodable {
    let version: Int
    package let features: [Place]
    package struct Place: Decodable, Identifiable {
        package let id: String
        package let name: String
        package let latitude: Double
        package let longitude: Double
        package let sourceURL: URL
        let height: Double?
        package let category: String
        package let blurb: String
        package let suggestedAltitudeMeters: Double
        package let suggestedHeadingDegrees: Double
        package var coordinate: LMSelenographicCoordinate { .init(latitudeDegrees: latitude, longitudeDegrees: longitude, heightMeters: height ?? 0) }
    }
    package static func load(bundle: Bundle = LunarMap.resources) throws -> Self {
        guard let url = bundle.url(forResource: "MoonPOI", withExtension: "json", subdirectory: "Terrain") ?? bundle.url(forResource: "MoonPOI", withExtension: "json") else {
            throw LMLunarElevationCatalog.CatalogError.missingResource
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

public enum LMLunarNavigation {
    public static func parse(_ text: String) -> LMSelenographicCoordinate? {
        let pair = text.split(separator: ",", omittingEmptySubsequences: false)
        guard pair.count == 2, let lat = Double(pair[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(pair[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return .init(latitudeDegrees: lat, longitudeDegrees: lon)
    }

    /// Move on the sphere in the starting point's tangent frame. This remains
    /// finite at the poles and wraps the dateline without a latitude clamp.
    package static func draggedCoordinate(from start: LMSelenographicCoordinate,
                                  northDegrees: Double, eastDegrees: Double) -> LMSelenographicCoordinate {
        guard northDegrees.isFinite, eastDegrees.isFinite else { return start }
        let frame = LMSelenographicCoordinateSystem().localFrame(at: start)
        let north = northDegrees * .pi / 180, east = eastDegrees * .pi / 180
        let length = hypot(north, east)
        guard length > 1e-12 else { return start }
        let angle = min(.pi, length)
        let up = frame.moonFixedDirection(SIMD3(0, 0, 1))
        let tangent = frame.moonFixedDirection(SIMD3(north / length, east / length, 0))
        let p = up * cos(angle) + tangent * sin(angle)
        return .init(latitudeDegrees: atan2(p.z, hypot(p.x, p.y)) * 180 / .pi,
                     longitudeDegrees: atan2(p.y, p.x) * 180 / .pi)
    }

    /// Constant-angular-speed great circle; the caller supplies eased time.
    /// Antipodes have no unique shortest path: choose a stable orthogonal axis.
    package static func interpolate(from: LMSelenographicCoordinate, to: LMSelenographicCoordinate,
                            fraction: Double) -> LMSelenographicCoordinate {
        if fraction <= 0 { return from }
        if fraction >= 1 { return to }
        let system = LMSelenographicCoordinateSystem()
        let a = simd_normalize(system.moonCenteredPosition(for: from).vector)
        let b = simd_normalize(system.moonCenteredPosition(for: to).vector)
        let dot = min(1, max(-1, simd_dot(a, b)))
        let point: SIMD3<Double>
        if dot > 0.999999 { point = simd_normalize(a + (b - a) * fraction) }
        else {
            let angle = acos(dot)
            let perpendicular = b - a * dot
            let tangent = simd_length(perpendicular) > 1e-8 ? simd_normalize(perpendicular)
                : simd_normalize(simd_cross(a, abs(a.z) < 0.9 ? SIMD3(0, 0, 1) : SIMD3(0, 1, 0)))
            point = a * cos(angle * fraction) + tangent * sin(angle * fraction)
        }
        return .init(latitudeDegrees: atan2(point.z, hypot(point.x, point.y)) * 180 / .pi,
                     longitudeDegrees: atan2(point.y, point.x) * 180 / .pi)
    }

    package static func displayRotation(from: LMSelenographicCoordinate, to: LMSelenographicCoordinate) -> simd_quatf {
        let system = LMSelenographicCoordinateSystem()
        let a = system.localFrame(at: from), b = system.localFrame(at: to)
        func column(_ vector: SIMD3<Double>) -> SIMD3<Float> {
            let local = b.localDirection(vector)
            return .init(Float(local.y), Float(local.x), Float(local.z))
        }
        return simd_quatf(simd_float3x3(columns: (column(a.moonFixedDirection(SIMD3(0, 1, 0))), column(a.moonFixedDirection(SIMD3(1, 0, 0))), column(a.moonFixedDirection(SIMD3(0, 0, 1))))))
    }
}
