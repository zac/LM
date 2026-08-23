import Foundation
import LMCore

/// Decoded `TerrainManifest.json` produced by `Tools/TerrainGenerator`.
/// Every field traces to the pinned LROC NAC DTM source recorded in the
/// manifest itself.
struct LMTerrainManifest: Equatable, Decodable {
    struct LandingOrigin: Equatable, Decodable {
        let latitudeDegrees: Double
        let longitudeDegrees: Double
        let detail: String
    }

    struct Projection: Equatable, Decodable {
        let mapProjectionType: String
        let latitudeType: String
        let positiveLongitudeDirection: String
        let sphereRadiusMeters: Double
        let sourceMetersPerPost: Double
        let sourceMinimumLatitude: Double
        let sourceMaximumLatitude: Double
        let sourceWesternmostLongitude: Double
        let sourceEasternmostLongitude: Double
    }

    struct Sun: Equatable, Decodable {
        let elevationDegrees: Double
        let azimuthDegreesClockwiseFromNorth: Double
        let detail: String
    }

    struct Source: Equatable, Decodable {
        let id: String
        let role: String
        let url: String
        let sha256: String
        let productId: String
        let productVersion: String
        let labelURL: String
        let detail: String
    }

    struct HeightEncoding: Equatable, Decodable {
        let format: String
        let centimetersPerCount: Int
        let detail: String
    }

    struct AlbedoEncoding: Equatable, Decodable {
        let format: String
        let detail: String
    }

    struct Tile: Equatable, Decodable {
        let id: String
        let postsPerSide: Int
        let postSpacingMeters: Double
        let extentMeters: Double
        let zeroPointMeters: Double
        let minimumHeightMeters: Double
        let maximumHeightMeters: Double
        let curvatureCorrected: Bool
        let edgeHandling: String?
        let heightFile: String
        let albedoFile: String
        let heightEncoding: HeightEncoding
        let albedoEncoding: AlbedoEncoding
        let detail: String?
    }

    let schemaVersion: Int
    let scenarioID: String
    let generated: String
    let landingOrigin: LandingOrigin
    let landingOriginElevationMeters: Double
    let projection: Projection
    let sun: Sun
    let sources: [Source]
    let tiles: [Tile]

    static let schemaVersion = 1

    func tile(id: String) -> Tile? {
        tiles.first { $0.id == id }
    }

    /// Sun direction in site-ENU meters: +x north, +y east, +z up, pointing
    /// from the scene toward the sun.
    var sunDirectionENU: LMVector3D {
        let elevation = sun.elevationDegrees * .pi / 180.0
        let azimuth = sun.azimuthDegreesClockwiseFromNorth * .pi / 180.0
        return LMVector3D(
            x: cos(elevation) * cos(azimuth),
            y: cos(elevation) * sin(azimuth),
            z: sin(elevation)
        )
    }

    static func load(bundle: Bundle = .main) throws -> LMTerrainManifest {
        guard let url = bundle.url(
            forResource: "TerrainManifest",
            withExtension: "json",
            subdirectory: "Terrain"
        ) ?? bundle.url(forResource: "TerrainManifest", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(
            LMTerrainManifest.self,
            from: Data(contentsOf: url)
        )
    }
}
