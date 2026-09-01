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

    struct CraterCatalog: Equatable, Decodable {
        struct DetectionParameters: Equatable, Decodable {
            let metersPerPixel: Double
            let minimumDiameterMeters: Double
            let maximumDiameterMeters: Double
            let diameterSteps: Int
            let minimumScore: Double
            let coverageRadiusMeters: Double
            let maximumCandidates: Int
            let sunElevationDegrees: Double
            let sunAzimuthDegreesClockwiseFromNorth: Double
        }

        let file: String
        let catalogID: String
        let generatorVersion: String
        let sha256: String
        let detectorSHA256: String
        let sourceIDs: [String]
        let detectionParameters: DetectionParameters
        let detail: String
    }

    struct Globe: Equatable, Decodable {
        struct TextureTier: Equatable, Decodable {
            let id: String
            let file: String
            let width: Int
            let height: Int
            let mapResolutionPixelsPerDegree: Double
            let metersPerPixel: Double
            let sha256: String
            let sourceID: String
            let detail: String
            let codec: String?
            let codecQuality: Int?
            let codecEncoder: String?
            let losslessSourceSHA256: String?
            let losslessSourceBytes: Int?
        }

        struct NormalMap: Equatable, Decodable {
            let id: String
            let file: String
            let width: Int
            let height: Int
            let mapResolutionPixelsPerDegree: Double
            let metersPerPixel: Double
            let sha256: String
            let sourceID: String
            let coordinateFrame: String
            let encoding: String
            let detail: String
        }

        let coordinateSystemName: String
        let radiusMeters: Double
        let materialMode: String
        let generatorVersion: String
        let generatorSHA256: String
        let textureTiers: [TextureTier]
        let normalMap: NormalMap
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
        let labelSHA256: String?
        let labelBytes: Int?
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
    let craterCatalog: CraterCatalog?
    let globe: Globe
    let sources: [Source]
    let tiles: [Tile]
    let toolSHA256: String

    static let schemaVersion = 5

    static let eagleLandmarkID = "apollo11-lm-eagle"

    func tile(id: String) -> Tile? {
        tiles.first { $0.id == id }
    }

    func landmark(id: String) -> Landmark? {
        landmarks.first { $0.id == id }
    }

    var selenographicCoordinateSystem: LMSelenographicCoordinateSystem {
        LMSelenographicCoordinateSystem(
            datumRadiusMeters: projection.sphereRadiusMeters
        )
    }

    var landingOriginCoordinate: LMSelenographicCoordinate {
        LMSelenographicCoordinate(
            latitudeDegrees: landingOrigin.latitudeDegrees,
            longitudeDegrees: landingOrigin.longitudeDegrees,
            heightMeters: landingOriginElevationMeters
        )
    }

    var landingLocalFrame: LMSelenographicLocalFrame {
        selenographicCoordinateSystem.localFrame(at: landingOriginCoordinate)
    }

    /// Local tangent-plane position relative to `landingOrigin`, matching the
    /// terrain mesh's +x north, +y east convention.
    func localPosition(of landmark: Landmark) -> LMVector3D {
        let position = selenographicCoordinateSystem.sitePosition(
            for: LMSelenographicCoordinate(
                latitudeDegrees: landmark.latitudeDegrees,
                longitudeDegrees: landmark.longitudeDegrees,
                heightMeters: landingOriginElevationMeters
            ),
            relativeTo: landingOriginCoordinate
        )
        return LMVector3D(
            x: position.northMeters,
            y: position.eastMeters,
            // The existing site terrain is planar around the datum elevation.
            // Preserve that calibrated vertical frame rather than introducing
            // the Moon's radial curvature as local relief.
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
