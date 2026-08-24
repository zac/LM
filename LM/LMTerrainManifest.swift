import Foundation
import LMCore

/// Decoded `TerrainManifest.json` produced by `Tools/TerrainGenerator`.
/// Every field traces to a pinned LROC NAC or LOLA/SELENE source recorded in
/// the manifest itself.
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
        let sourceLines: Int
        let sourceSamples: Int
        let sourceMetersPerPost: Double
        let sourceMinimumLatitude: Double
        let sourceMaximumLatitude: Double
        let sourceWesternmostLongitude: Double
        let sourceEasternmostLongitude: Double
    }

    struct Landmark: Equatable, Decodable {
        let id: String
        let latitudeDegrees: Double
        let longitudeDegrees: Double
        let sourceURL: String
        let detail: String
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
        let bytes: Int?
        let sourceBytes: Int?
        let byteRangeStart: Int?
        let byteRangeEnd: Int?
        let sourceMD5: String?
        let sourceRowStart: Int?
        let sourceRowEnd: Int?
        let sourceRowBytes: Int?
        let mapResolutionPixelsPerDegree: Double?
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
        let colorSpace: String?
        let texelsPerSide: Int?
        let metersPerTexel: Double?
        let sourceIDs: [String]?
        let edgeHandling: String?
        let minimumLinearReflectance: Double?
        let maximumLinearReflectance: Double?
        let detail: String

        init(
            format: String,
            colorSpace: String? = nil,
            texelsPerSide: Int? = nil,
            metersPerTexel: Double? = nil,
            sourceIDs: [String]? = nil,
            edgeHandling: String? = nil,
            minimumLinearReflectance: Double? = nil,
            maximumLinearReflectance: Double? = nil,
            detail: String
        ) {
            self.format = format
            self.colorSpace = colorSpace
            self.texelsPerSide = texelsPerSide
            self.metersPerTexel = metersPerTexel
            self.sourceIDs = sourceIDs
            self.edgeHandling = edgeHandling
            self.minimumLinearReflectance = minimumLinearReflectance
            self.maximumLinearReflectance = maximumLinearReflectance
            self.detail = detail
        }
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
        let sourceIDs: [String]?
        let nativeSourceSpacingMeters: Double?
        let transitionWidthMeters: Double?
        let heightFile: String
        let albedoFile: String
        let heightEncoding: HeightEncoding
        let albedoEncoding: AlbedoEncoding
        let detail: String?
    }

    let schemaVersion: Int
    let scenarioID: String
    let landingOrigin: LandingOrigin
    let landmarks: [Landmark]
    let landingOriginElevationMeters: Double
    let projection: Projection
    let sun: Sun
    let sources: [Source]
    let tiles: [Tile]
    let toolSHA256: String

    static let schemaVersion = 2

    static let eagleLandmarkID = "apollo11-lm-eagle"

    func tile(id: String) -> Tile? {
        tiles.first { $0.id == id }
    }

    func landmark(id: String) -> Landmark? {
        landmarks.first { $0.id == id }
    }

    /// Local tangent-plane position relative to `landingOrigin`, matching the
    /// terrain mesh's +x north, +y east convention.
    func localPosition(of landmark: Landmark) -> LMVector3D {
        let degreesToRadians = Double.pi / 180
        let originLatitude = landingOrigin.latitudeDegrees * degreesToRadians
        let landmarkLatitude = landmark.latitudeDegrees * degreesToRadians
        let latitudeDelta = landmarkLatitude - originLatitude
        let longitudeDelta = (landmark.longitudeDegrees - landingOrigin.longitudeDegrees)
            * degreesToRadians
        let meanLatitude = (originLatitude + landmarkLatitude) / 2
        return LMVector3D(
            x: latitudeDelta * projection.sphereRadiusMeters,
            y: longitudeDelta * projection.sphereRadiusMeters * cos(meanLatitude),
            z: 0
        )
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

/// Translates Luminary's landing-site-local navigation frame into the
/// geospatial terrain frame without changing simulated physics or attitude.
///
/// The bundled P66 recording is the deterministic visual calibration artifact:
/// its contact point maps to JPL's measured Eagle position. Any live deviation
/// from that nominal trajectory passes through unchanged.
struct LMTerrainFrameAlignment: Equatable, Sendable {
    enum AlignmentError: Error, Equatable {
        case missingLandmark(String)
    }

    /// Final contact position in `P66TerminalDescent.json`. A regression test
    /// ties this value to the fixture so regenerated flight data cannot silently
    /// move the terrain frame.
    static let nominalP66GuidanceTouchdown = LMVector3D(
        x: -539.922_526_555_545_8,
        y: 756.958_327_442_571,
        z: -0.249_133_707_907_646_77
    )

    let guidanceReferenceTouchdown: LMVector3D
    let terrainReferenceTouchdown: LMVector3D

    init(
        manifest: LMTerrainManifest,
        guidanceReferenceTouchdown: LMVector3D = Self.nominalP66GuidanceTouchdown
    ) throws {
        guard let eagle = manifest.landmark(id: LMTerrainManifest.eagleLandmarkID) else {
            throw AlignmentError.missingLandmark(LMTerrainManifest.eagleLandmarkID)
        }
        self.guidanceReferenceTouchdown = guidanceReferenceTouchdown
        terrainReferenceTouchdown = manifest.localPosition(of: eagle)
    }

    func terrainPosition(from guidancePosition: LMVector3D) -> LMVector3D {
        LMVector3D(
            x: terrainReferenceTouchdown.x
                + guidancePosition.x - guidanceReferenceTouchdown.x,
            y: terrainReferenceTouchdown.y
                + guidancePosition.y - guidanceReferenceTouchdown.y,
            z: guidancePosition.z
        )
    }
}
