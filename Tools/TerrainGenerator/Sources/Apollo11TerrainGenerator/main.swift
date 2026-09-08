import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Terrain preprocessing for the full-immersion Apollo 11 terminal descent.
//
// Source-pinned pipeline: reads the LROC NAC DTM product for the Apollo 11
// landing site (NAC_DTM_APOLLO11, volume LROLRC_2001), verifies it against the
// committed PDS labels, and emits three nested georeferenced tiles: a dense
// LROC NAC near field, a SLDEM2015 medium field, and a global SLDEM2015 far
// field. The manifest records source URLs, exact byte-range checksums,
// projection, sampling, boundary registration, and the landing origin.
//
// Usage:
//   swift run --package-path Tools/TerrainGenerator Apollo11TerrainGenerator \
//     --dtm Tools/TerrainGenerator/cache/NAC_DTM_APOLLO11.TIF \
//     --sldem-medium Tools/TerrainGenerator/cache/SLDEM2015_512_APOLLO11_ROWS_14874_15156_FLOAT.bin \
//     --sldem-far Tools/TerrainGenerator/cache/SLDEM2015_128_APOLLO11_ROWS_7038_8150_FLOAT.bin \
//     --nac-ortho-a Tools/TerrainGenerator/cache/NAC_DTM_APOLLO11_M150361817_50CM_ROWS_32100_36197.bin \
//     --nac-ortho-b Tools/TerrainGenerator/cache/NAC_DTM_APOLLO11_M150368601_50CM_ROWS_32100_36197.bin \
//     --wac-medium Tools/TerrainGenerator/cache/WAC_EMP_643NM_304P_N_ROWS_17951_18118_FLOAT.bin \
//     --wac-far-north Tools/TerrainGenerator/cache/WAC_EMP_643NM_064P_N_ROWS_3518_3839_FLOAT.bin \
//     --wac-far-south Tools/TerrainGenerator/cache/WAC_EMP_643NM_064P_S_ROWS_0_235_FLOAT.bin \
//     --out Packages/LunarMap/Sources/LunarMap/Resources/Terrain

// MARK: - Pinned sources (Docs/visionOS Immersive.md)

struct PinnedSource {
    let url: String
    let sha256: String?
    let bytes: Int?
    let sourceBytes: Int?
    let byteRangeStart: Int?
    let byteRangeEnd: Int?
    let sourceMD5: String?

    init(
        url: String,
        sha256: String?,
        bytes: Int?,
        sourceBytes: Int?,
        byteRangeStart: Int?,
        byteRangeEnd: Int?,
        sourceMD5: String? = nil
    ) {
        self.url = url
        self.sha256 = sha256
        self.bytes = bytes
        self.sourceBytes = sourceBytes
        self.byteRangeStart = byteRangeStart
        self.byteRangeEnd = byteRangeEnd
        self.sourceMD5 = sourceMD5
    }
}

let pinnedDTM = PinnedSource(
    url: "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/SDP/NAC_DTM/APOLLO11/NAC_DTM_APOLLO11.TIF",
    sha256: "920da622e3d7c3f047c67a970b5429aaadf00f886804e3fc6c72f6e5298043e9",
    bytes: 118_142_727,
    sourceBytes: 118_142_727,
    byteRangeStart: nil,
    byteRangeEnd: nil
)
let pinnedLabel = PinnedSource(
    url: "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/SDP/NAC_DTM/APOLLO11/NAC_DTM_APOLLO11.LBL",
    sha256: nil,
    bytes: nil,
    sourceBytes: nil,
    byteRangeStart: nil,
    byteRangeEnd: nil
)

let sldemBaseURL = "https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/sldem2015"
let pinnedSLDEMMedium = PinnedSource(
    url: "\(sldemBaseURL)/tiles/float_img/sldem2015_512_00n_30n_000_045_float.img",
    sha256: "9ef0cf5d054c295d21b02ccf463c0f246dc78871c344f4fe01c5f077ba8d7698",
    bytes: 26_081_280,
    sourceBytes: 1_415_577_600,
    byteRangeStart: 1_370_787_840,
    byteRangeEnd: 1_396_869_119
)
let pinnedSLDEMMediumLabelURL = "\(sldemBaseURL)/tiles/float_img/sldem2015_512_00n_30n_000_045_float.lbl"
let pinnedSLDEMFar = PinnedSource(
    url: "\(sldemBaseURL)/global/float_img/sldem2015_128_60s_60n_000_360_float.img",
    sha256: "f02bb39e4b11f664a77ce3ed8ab0f12087fd89a01d534942564fba5d643122f9",
    bytes: 205_148_160,
    sourceBytes: 2_831_155_200,
    byteRangeStart: 1_297_244_160,
    byteRangeEnd: 1_502_392_319
)
let pinnedSLDEMFarLabelURL = "\(sldemBaseURL)/global/float_img/sldem2015_128_60s_60n_000_360_float.lbl"

let lrocApollo11BaseURL = "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/SDP/NAC_DTM/APOLLO11"
let pinnedNACOrthoA = PinnedSource(
    url: "\(lrocApollo11BaseURL)/NAC_DTM_APOLLO11_M150361817_50CM.IMG",
    sha256: "b6e9df38ddae806b66c6dc3afbe7f1e94b932421292e3af07f048606d9d6e961",
    bytes: 69_174_240,
    sourceBytes: 943_743_920,
    byteRangeStart: 541_864_880,
    byteRangeEnd: 611_039_119,
    sourceMD5: "c3784f010eb6d6c2d84d6ee7b4088331"
)
let pinnedNACOrthoB = PinnedSource(
    url: "\(lrocApollo11BaseURL)/NAC_DTM_APOLLO11_M150368601_50CM.IMG",
    sha256: "e93a51b8f18dd549aa7b3b22e708c7d06775273a6605b43026679d54e380a207",
    bytes: 69_174_240,
    sourceBytes: 943_743_920,
    byteRangeStart: 541_864_880,
    byteRangeEnd: 611_039_119,
    sourceMD5: "95decbebbf283e46d6146c47fec988ed"
)

let wacEMPBaseURL = "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/MDR/WAC_EMP"
let pinnedWACMedium = PinnedSource(
    url: "\(wacEMPBaseURL)/WAC_EMP_643NM_E300N0450_304P.IMG",
    sha256: "08829725710d9e4dba155372369e6bf5c268eac37023ae6ed77f15902640072a",
    bytes: 18_385_920,
    sourceBytes: 1_996_295_040,
    byteRangeStart: 1_964_666_880,
    byteRangeEnd: 1_983_052_799,
    sourceMD5: "97af2366068cffb38415b3658993b4f1"
)
let pinnedWACFarNorth = PinnedSource(
    url: "\(wacEMPBaseURL)/WAC_EMP_643NM_E300N0450_064P.IMG",
    sha256: "831255f649b8184f7e8ea339ced80878c840052971fd0fcd761d6c30c6395e42",
    bytes: 7_418_880,
    sourceBytes: 88_496_640,
    byteRangeStart: 81_077_760,
    byteRangeEnd: 88_496_639,
    sourceMD5: "37e0144f3fa52cf91f9cb0aa605d9200"
)
let pinnedWACFarSouth = PinnedSource(
    url: "\(wacEMPBaseURL)/WAC_EMP_643NM_E300S0450_064P.IMG",
    sha256: "9a8bcc140296ddf9dd8289e95f85f112a30776cc8c441955a56347d66b1b7c86",
    bytes: 5_437_440,
    sourceBytes: 88_496_640,
    byteRangeStart: 23_040,
    byteRangeEnd: 5_460_479,
    sourceMD5: "53eb43347e3a96bc8fdb17c1f3207546"
)

/// Apollo 11 retroreflector (LRR-3) alignment per Docs/visionOS Immersive.md.
let siteLatitudeDegrees = 0.673_433
let siteLongitudeDegrees = 23.473_113

/// Eagle position from JPL D-32296, Lunar Constants and Models Document,
/// table 5-1. The terrain stays centered on the retroreflector so existing
/// measured products remain pixel-registered; this landmark georeferences the
/// simulated touchdown inside that terrain frame.
let eagleLatitudeDegrees = 0.674_08
let eagleLongitudeDegrees = 23.472_97
let jplLunarConstantsURL = "https://ssd.jpl.nasa.gov/doc/lunar_cmd_2005_jpl_d32296.pdf"

// NAC_DTM_APOLLO11 v1.9 label values (committed alongside this tool).
let dtmLines = 13_978
let dtmSamples = 2_111
let dtmMetersPerPost = 2.000_000_000_000_6
let dtmMaximumLatitude = 1.236_538_8
let dtmMinimumLatitude = 0.314_609
let dtmEasternmostLongitude = 23.511_529_6
let dtmWesternmostLongitude = 23.372_275_8
let dtmNoData: Float = -3.402_822_66e38
let lunarRadiusMeters = 1_737_400.0

/// Mission sun at touchdown (1969-07-20T20:17:40Z), from `LMLunarEphemeris`
/// evaluated at the landing origin. Eagle landed in local morning with the Sun
/// low in the east, which is what casts the long westward shadows across the
/// approach.
///
/// The previous azimuth of 276.4 degrees was an approximation and pointed at
/// the anti-solar direction, putting every shadow on the wrong side; it was
/// close to this site's NAC *acquisition* azimuth, which is a separate thing.
/// The elevation is unchanged within the ephemeris tolerance and still agrees
/// with the 10.8 degrees the mission report quotes.
let sunElevationDegrees = 10.689
let sunAzimuthDegreesClockwiseFromNorth = 88.819

let nearTilePosts = 1025
let nearTilePostSpacingMeters = 2.0
let mediumTilePosts = 513
let mediumTilePostSpacingMeters = 32.0
let farTilePosts = 513
let farTilePostSpacingMeters = 512.0

let sldemMediumRows = 15_360
let sldemMediumSamples = 23_040
let sldemMediumResolutionPixelsPerDegree = 512.0
let sldemMediumMaximumLatitude = 30.0
let sldemMediumWesternmostLongitude = 0.0
let sldemMediumRowStart = 14_874
let sldemMediumRowEnd = 15_156
let sldemMediumMetersPerPost = 59.225_293_8

let sldemFarRows = 15_360
let sldemFarSamples = 46_080
let sldemFarResolutionPixelsPerDegree = 128.0
let sldemFarMaximumLatitude = 60.0
let sldemFarWesternmostLongitude = 0.0
let sldemFarRowStart = 7_038
let sldemFarRowEnd = 8_150
let sldemFarMetersPerPost = 236.901

let nacOrthoSamples = 8_440
let nacOrthoResolutionPixelsPerDegree = 60_646.700_848_3
let nacOrthoMaximumLatitude = 1.236_505_84
let nacOrthoWesternmostLongitude = 23.372_316_47
let nacOrthoRowStart = 32_100
let nacOrthoRowEnd = 36_197
let nacOrthoMetersPerPixel = 0.5

let wacMediumSamples = 27_360
let wacMediumResolutionPixelsPerDegree = 304.0
let wacMediumMaximumLatitude = 60.0
let wacMediumWesternmostLongitude = 0.0
let wacMediumRowStart = 17_951
let wacMediumRowEnd = 18_118
let wacMediumMetersPerPixel = 99.747_863_237_334

let wacFarSamples = 5_760
let wacFarResolutionPixelsPerDegree = 64.0
let wacFarNorthMaximumLatitude = 60.0
let wacFarNorthRowStart = 3_518
let wacFarNorthRowEnd = 3_839
let wacFarSouthMaximumLatitude = 0.0
let wacFarSouthRowStart = 0
let wacFarSouthRowEnd = 235
let wacFarMetersPerPixel = 473.802_350_377_34

let nearAlbedoTexels = 4_097
let mediumAlbedoTexels = mediumTilePosts
let farAlbedoTexels = farTilePosts

let craterCatalogFileName = "apollo11-nac-craters-v1.json"
let craterCatalogID = "apollo11-near-field-nac-craters-v1"
let craterCatalogGeneratorVersion = "nac-parametric-correlation-v1"
let craterCatalogSHA256 =
    "b2bdfada9d6df68623dcfd8c99a5b7b7d1bc2c6000b997d04afd80a79a6e630f"
let craterDetectorSHA256 =
    "d01e3ed540e29a54bde5afc283688bd38b0f0013b0317d1b395608e34a839558"
let wacGlobal16PPDURL =
    "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/BDR/WAC_GLOBAL/WAC_GLOBAL_E000N0000_016P.IMG"
let wacGlobal16PPDSourceSHA256 =
    "c75a49b48df0d1d8afad8f25e58332599e8383e4967424ffbb0ba38b0808b2b6"
let wacGlobal16PPDTextureSHA256 =
    "b799eab2d43f7a27799972d4ec4bc25cff06776ba14774e03e322cb7a7ea460e"
let wacGlobal64PPDURL =
    "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/BDR/WAC_GLOBAL/WAC_GLOBAL_E000N0000_064P.IMG"
let wacGlobal64PPDSourceSHA256 =
    "bc1feab6e86ae2cf47798a4f00cdf7f5e73030fcbc2223fba7fab59a5a2a34ec"
let wacGlobal64PPDTextureSHA256 =
    "819ca84afedca9a5fe864a0a3a036bc6384a105f21135614c90808c184355841"
let wacGlobal64PPDLosslessSHA256 =
    "faead7d93e3ac1b16f30955419f4cbb2f1fbd1040dbc2913473ccd5f30df2420"
let lolaLDEM16URL =
    "https://imbrium.mit.edu/DATA/LOLA_GDR/CYLINDRICAL/IMG/LDEM_16.IMG"
let lolaLDEM16LabelURL =
    "https://imbrium.mit.edu/DATA/LOLA_GDR/CYLINDRICAL/IMG/LDEM_16.LBL"
let lolaLDEM16SourceSHA256 =
    "a511e40d7a3ea3275945b4da2a1df377133264fab0be94b7434b1cf8907254cb"
let lolaLDEM16LabelSHA256 =
    "9aef29463ccc6ed3a3fbe0df3ecd830a99c69e16b564f455507dee2697096579"
let lolaLDEM16NormalSHA256 =
    "bd70494eb4194aca023e4f4f724cc7a6d11a4b23148f4519192715694dd34696"
let globalLunarMosaicGeneratorSHA256 =
    "1dcd7091ec5dcb370ece0196f02510d33aab48510a44f4ca7571a2b898567711"

// MARK: - Manifest model (mirrored by LM/LM/LMTerrainManifest.swift)

func manifestJSON() -> [String: Any] {
    [
        "schemaVersion": 6,
        "remoteElevationCatalog": [
            "file": "LunarElevationStrips.json",
            "sha256": "3cb3fa9507cfe174ae0c0698a684f4c3704b507b6213b0d78a2c6ac6ab303181",
        ],
        "scenarioID": "apollo11-progressive-real-data-terrain",
        "globe": [
            "coordinateSystemName": "IAU_ME",
            "radiusMeters": lunarRadiusMeters,
            "materialMode": "unlit-morphologic-map",
            "generatorVersion": "wac-global-morphologic-lola-normal-jxl-v3",
            "generatorSHA256": globalLunarMosaicGeneratorSHA256,
            "textureTiers": [
                [
                    "id": "wac-global-16ppd",
                    "file": "WACGlobal16PPD.png",
                    "width": 5_760,
                    "height": 2_880,
                    "mapResolutionPixelsPerDegree": 16.0,
                    "metersPerPixel": 1_895.209_401_509_3,
                    "sha256": wacGlobal16PPDTextureSHA256,
                    "sourceID": "wac-global-morphologic-16ppd",
                    "detail": "Pinned global WAC morphologic base. Illumination is baked into this map, so it is rendered unlit rather than double-shaded by the movable mission sun."
                ],
                [
                    "id": "wac-global-64ppd",
                    "file": "WACGlobal64PPD-q95.jxl",
                    "width": 23_040,
                    "height": 11_520,
                    "mapResolutionPixelsPerDegree": 64.0,
                    "metersPerPixel": 473.802_350_377_34,
                    "sha256": wacGlobal64PPDTextureSHA256,
                    "sourceID": "wac-global-morphologic-64ppd",
                    "detail": "Pinned offline 64 ppd WAC morphologic tier. The source transfer is unchanged and remains unlit; one-channel JPEG XL is visually transparent to the lossless grayscale PNG in fixed Simulator globe and orbit-overlap captures.",
                    "codec": "JPEG XL",
                    "codecQuality": 95,
                    "codecEffort": 7,
                    "codecEncoder": "cjxl 0.12.0 effort 7",
                    "losslessSourceSHA256": wacGlobal64PPDLosslessSHA256,
                    "losslessSourceBytes": 128_461_405
                ]
            ],
            "normalMap": [
                "id": "lola-ldem-16ppd-me-normal",
                "file": "LOLALDEM16MENormal.png",
                "width": 5_760,
                "height": 2_880,
                "mapResolutionPixelsPerDegree": 16.0,
                "metersPerPixel": 1_895.209_401_509_3,
                "sha256": lolaLDEM16NormalSHA256,
                "sourceID": "lola-ldem-16ppd-global",
                "coordinateFrame": "IAU_ME",
                "encoding": "linear RGB maps normalized ME x/y/z from [-1,1] to [0,1]",
                "detail": "Detrended radial normal plus central-difference LDEM_16 relief. Used only to perturb the ephemeris terminator multiplier; never as a second PBR lighting pass."
            ],
            "detail": "Whole-Moon map-scale presentation in the Mean Earth/Polar-axis frame. The WAC base remains unlit; a detrended LOLA normal field perturbs only the ephemeris terminator multiplier."
        ],
        "craterCatalog": [
            "file": craterCatalogFileName,
            "catalogID": craterCatalogID,
            "generatorVersion": craterCatalogGeneratorVersion,
            "sha256": craterCatalogSHA256,
            "detectorSHA256": craterDetectorSHA256,
            "sourceIDs": [
                "nac-ortho-m150361817-50cm-slab",
                "nac-ortho-m150368601-50cm-slab"
            ],
            "detectionParameters": [
                "metersPerPixel": 0.5,
                "minimumDiameterMeters": 2.0,
                "maximumDiameterMeters": 8.0,
                "diameterSteps": 9,
                "minimumScore": 0.70,
                "coverageRadiusMeters": 900.0,
                "maximumCandidates": 1_200,
                "sunElevationDegrees": 26.941_222_345_7,
                "sunAzimuthDegreesClockwiseFromNorth": 270.572_339_464_1
            ],
            "detail": "Human-reviewed deterministic crater correlations from the registered 0.5 m NAC composite. The catalog adds bounded sub-DTM geometry only; the measured height field remains exact at every 2 m post."
        ],
        "landingOrigin": [
            "latitudeDegrees": siteLatitudeDegrees,
            "longitudeDegrees": siteLongitudeDegrees,
            "detail": "Apollo 11 retroreflector alignment; heights are relative to the DTM elevation sampled at this point."
        ],
        "landmarks": [
            [
                "id": "apollo11-lm-eagle",
                "latitudeDegrees": eagleLatitudeDegrees,
                "longitudeDegrees": eagleLongitudeDegrees,
                "sourceURL": jplLunarConstantsURL,
                "detail": "Apollo 11 Lunar Module position from JPL D-32296 table 5-1. The visual terrain frame maps the bundled nominal P66 touchdown to this point while preserving live guidance deviations."
            ]
        ],
        "projection": [
            "mapProjectionType": "EQUIRECTANGULAR",
            "latitudeType": "PLANETOCENTRIC",
            "positiveLongitudeDirection": "EAST",
            "sphereRadiusMeters": lunarRadiusMeters,
            "sourceLines": dtmLines,
            "sourceSamples": dtmSamples,
            "sourceMetersPerPost": dtmMetersPerPost,
            "sourceMinimumLatitude": dtmMinimumLatitude,
            "sourceMaximumLatitude": dtmMaximumLatitude,
            "sourceWesternmostLongitude": dtmWesternmostLongitude,
            "sourceEasternmostLongitude": dtmEasternmostLongitude
        ],
        "sun": [
            "elevationDegrees": sunElevationDegrees,
            "azimuthDegreesClockwiseFromNorth": sunAzimuthDegreesClockwiseFromNorth,
            "detail": "Mission-appropriate low sun at touchdown; azimuth approximated west-southwest."
        ],
        "sources": [
            [
                "coverage": coverageManifest(
                    minimumLatitude: dtmMinimumLatitude,
                    maximumLatitude: dtmMaximumLatitude,
                    westernmostLongitude: dtmWesternmostLongitude,
                    easternmostLongitude: dtmEasternmostLongitude
                ),
                "id": "nac-dtm-apollo11",
                "role": "geometry",
                "postSpacingMeters": dtmMetersPerPost,
                "residualCapRatio": 0.12,
                "url": pinnedDTM.url,
                "sha256": pinnedDTM.sha256 ?? "",
                "bytes": pinnedDTM.bytes ?? 0,
                "productId": "NAC_DTM_APOLLO11",
                "productVersion": "v1.9",
                "labelURL": pinnedLabel.url,
                "detail": "LROC NAC DTM supplies measured near-field geometry. Separately pinned 0.5 m orthorectified NAC observations supply only exposure-normalized high-frequency reflectance detail over a photometrically normalized WAC base. The mission-sun DirectionalLight shades the mesh normals; per-tile hillshade PNGs remain regenerable diagnostics rather than surface color."
            ],
            sourceManifest(
                id: "sldem2015-512-apollo11-slab",
                role: "medium-field-geometry",
                source: pinnedSLDEMMedium,
                productID: "SLDEM2015_512_00N_30N_000_045_FLOAT",
                labelURL: pinnedSLDEMMediumLabelURL,
                rowStart: sldemMediumRowStart,
                rowEnd: sldemMediumRowEnd,
                rowBytes: sldemMediumSamples * MemoryLayout<Float>.size,
                resolution: sldemMediumResolutionPixelsPerDegree,
                maximumLatitude: sldemMediumMaximumLatitude,
                westernmostLongitude: sldemMediumWesternmostLongitude,
                sourceSamples: sldemMediumSamples,
                postSpacingMeters: sldemMediumMetersPerPost,
                residualCapRatio: 0.12,
                detail: "Exact PDS byte-range slab covering the 16.384 km Apollo 11 medium field. Native SLDEM2015 posts are about 59.2 m at the equator; the 32 m render grid interpolates this source and is boundary-registered to the measured NAC tile."
            ),
            sourceManifest(
                id: "sldem2015-128-apollo11-slab",
                role: "far-field-geometry",
                source: pinnedSLDEMFar,
                productID: "SLDEM2015_128_60S_60N_000_360_FLOAT",
                labelURL: pinnedSLDEMFarLabelURL,
                rowStart: sldemFarRowStart,
                rowEnd: sldemFarRowEnd,
                rowBytes: sldemFarSamples * MemoryLayout<Float>.size,
                resolution: sldemFarResolutionPixelsPerDegree,
                maximumLatitude: sldemFarMaximumLatitude,
                westernmostLongitude: sldemFarWesternmostLongitude,
                sourceSamples: sldemFarSamples,
                postSpacingMeters: sldemFarMetersPerPost,
                residualCapRatio: 0.12,
                detail: "Exact PDS byte-range slab covering the 262.144 km Apollo 11 far field. Native SLDEM2015 posts are about 236.9 m at the equator; the 512 m render grid is boundary-registered to the medium field."
            ),
            sourceManifest(
                id: "nac-ortho-m150361817-50cm-slab",
                role: "near-field-high-frequency-reflectance",
                source: pinnedNACOrthoA,
                productID: "NAC_DTM_APOLLO11_M150361817_50CM",
                labelURL: "\(lrocApollo11BaseURL)/NAC_DTM_APOLLO11_M150361817_50CM.xml",
                rowStart: nacOrthoRowStart,
                rowEnd: nacOrthoRowEnd,
                rowBytes: nacOrthoSamples * MemoryLayout<Int16>.size,
                resolution: nacOrthoResolutionPixelsPerDegree,
                maximumLatitude: nacOrthoMaximumLatitude,
                westernmostLongitude: nacOrthoWesternmostLongitude,
                sourceSamples: nacOrthoSamples,
                postSpacingMeters: nil,
                residualCapRatio: nil,
                detail: "Exact PDS byte-range slab from the first 0.5 m orthorectified NAC stereo observation. Exposure-normalized high-frequency contrast is averaged with the second observation and faded to zero at the near-field edge; it is not treated as photometrically normalized absolute albedo."
            ),
            sourceManifest(
                id: "nac-ortho-m150368601-50cm-slab",
                role: "near-field-high-frequency-reflectance",
                source: pinnedNACOrthoB,
                productID: "NAC_DTM_APOLLO11_M150368601_50CM",
                labelURL: "\(lrocApollo11BaseURL)/NAC_DTM_APOLLO11_M150368601_50CM.xml",
                rowStart: nacOrthoRowStart,
                rowEnd: nacOrthoRowEnd,
                rowBytes: nacOrthoSamples * MemoryLayout<Int16>.size,
                resolution: nacOrthoResolutionPixelsPerDegree,
                maximumLatitude: nacOrthoMaximumLatitude,
                westernmostLongitude: nacOrthoWesternmostLongitude,
                sourceSamples: nacOrthoSamples,
                postSpacingMeters: nil,
                residualCapRatio: nil,
                detail: "Exact PDS byte-range slab from the second 0.5 m orthorectified NAC stereo observation. Its independent gain and offset are normalized before the two registered views are averaged."
            ),
            sourceManifest(
                id: "wac-emp-643nm-304p-apollo11-slab",
                role: "near-and-medium-photometric-reflectance",
                source: pinnedWACMedium,
                productID: "WAC_EMP_643NM_E300N0450_304P",
                labelURL: "\(wacEMPBaseURL)/WAC_EMP_643NM_E300N0450_304P.xml",
                rowStart: wacMediumRowStart,
                rowEnd: wacMediumRowEnd,
                rowBytes: wacMediumSamples * MemoryLayout<Float>.size,
                resolution: wacMediumResolutionPixelsPerDegree,
                maximumLatitude: wacMediumMaximumLatitude,
                westernmostLongitude: wacMediumWesternmostLongitude,
                sourceSamples: wacMediumSamples,
                postSpacingMeters: nil,
                residualCapRatio: nil,
                detail: "Exact PDS byte-range slab from the empirically photometrically normalized 643 nm WAC mosaic at about 99.7 m/pixel. It supplies absolute low-frequency reflectance for the near and medium bands."
            ),
            sourceManifest(
                id: "wac-emp-643nm-64p-north-apollo11-slab",
                role: "far-field-photometric-reflectance",
                source: pinnedWACFarNorth,
                productID: "WAC_EMP_643NM_E300N0450_064P",
                labelURL: "\(wacEMPBaseURL)/WAC_EMP_643NM_E300N0450_064P.xml",
                rowStart: wacFarNorthRowStart,
                rowEnd: wacFarNorthRowEnd,
                rowBytes: wacFarSamples * MemoryLayout<Float>.size,
                resolution: wacFarResolutionPixelsPerDegree,
                maximumLatitude: wacFarNorthMaximumLatitude,
                westernmostLongitude: 0,
                sourceSamples: wacFarSamples,
                postSpacingMeters: nil,
                residualCapRatio: nil,
                detail: "Exact PDS byte-range slab from the normalized 643 nm WAC mosaic north of the equator at about 473.8 m/pixel."
            ),
            sourceManifest(
                id: "wac-emp-643nm-64p-south-apollo11-slab",
                role: "far-field-photometric-reflectance",
                source: pinnedWACFarSouth,
                productID: "WAC_EMP_643NM_E300S0450_064P",
                labelURL: "\(wacEMPBaseURL)/WAC_EMP_643NM_E300S0450_064P.xml",
                rowStart: wacFarSouthRowStart,
                rowEnd: wacFarSouthRowEnd,
                rowBytes: wacFarSamples * MemoryLayout<Float>.size,
                resolution: wacFarResolutionPixelsPerDegree,
                maximumLatitude: wacFarSouthMaximumLatitude,
                westernmostLongitude: 0,
                sourceSamples: wacFarSamples,
                postSpacingMeters: nil,
                residualCapRatio: nil,
                detail: "Exact PDS byte-range slab from the normalized 643 nm WAC mosaic south of the equator at about 473.8 m/pixel."
            ),
            [
                "coverage": coverageManifest(
                    minimumLatitude: -90,
                    maximumLatitude: 90,
                    westernmostLongitude: 0,
                    easternmostLongitude: 360
                ),
                "id": "wac-global-morphologic-16ppd",
                "role": "global-morphologic-map",
                "url": wacGlobal16PPDURL,
                "sha256": wacGlobal16PPDSourceSHA256,
                "bytes": 66_378_240,
                "mapResolutionPixelsPerDegree": 16.0,
                "productId": "WAC_GLOBAL_E000N0000_016P",
                "productVersion": "v1.3",
                "labelURL": wacGlobal16PPDURL,
                "detail": "Global 53-70 degree-incidence WAC morphologic mosaic with an attached PDS3 label. It is the pinned source for the unlit globe base and is not photometrically normalized surface albedo."
            ],
            [
                "coverage": coverageManifest(
                    minimumLatitude: -90,
                    maximumLatitude: 90,
                    westernmostLongitude: 0,
                    easternmostLongitude: 360
                ),
                "id": "wac-global-morphologic-64ppd",
                "role": "global-morphologic-map",
                "url": wacGlobal64PPDURL,
                "sha256": wacGlobal64PPDSourceSHA256,
                "bytes": 1_061_775_360,
                "mapResolutionPixelsPerDegree": 64.0,
                "productId": "WAC_GLOBAL_E000N0000_064P",
                "productVersion": "v1.3",
                "labelURL": wacGlobal64PPDURL,
                "detail": "Global 53-70 degree-incidence WAC morphologic mosaic at 64 ppd with an attached PDS3 label. It is the pinned lossless source for the bundled one-channel JPEG XL tier and is not photometrically normalized surface albedo."
            ],
            [
                "coverage": coverageManifest(
                    minimumLatitude: -90,
                    maximumLatitude: 90,
                    westernmostLongitude: 0,
                    easternmostLongitude: 360
                ),
                "id": "lola-ldem-16ppd-global",
                "bundledFile": "LDEM_16.IMG",
                "bundledLabelFile": "LDEM_16.LBL",
                "role": "global-elevation-normal-source",
                "postSpacingMeters": 1_895.209_401_509_3,
                "residualCapRatio": 0.12,
                "url": lolaLDEM16URL,
                "sha256": lolaLDEM16SourceSHA256,
                "bytes": 33_177_600,
                "mapResolutionPixelsPerDegree": 16.0,
                "productId": "LDEM_16",
                "productVersion": "V3.1",
                "labelURL": lolaLDEM16LabelURL,
                "labelSHA256": lolaLDEM16LabelSHA256,
                "labelBytes": 5_121,
                "detail": "Global 16 ppd LOLA height above the 1,737,400 m reference sphere in the Mean Earth/Polar-axis frame. The pinned image supplies the global offline elevation base and the existing globe normal field. The measured-elevation diagnostic consumes it directly; Apollo site geometry and contact retain their original assets."
            ]
        ],
        "tiles": [
            nearManifestTile(),
            mediumManifestTile(),
            farManifestTile()
        ]
    ]
}

func sourceManifest(
    id: String,
    role: String,
    source: PinnedSource,
    productID: String,
    labelURL: String,
    rowStart: Int,
    rowEnd: Int,
    rowBytes: Int,
    resolution: Double,
    maximumLatitude: Double,
    westernmostLongitude: Double,
    sourceSamples: Int,
    postSpacingMeters: Double?,
    residualCapRatio: Double?,
    detail: String
) -> [String: Any] {
    var manifest: [String: Any] = [
        "coverage": coverageManifest(
            minimumLatitude: maximumLatitude - (Double(rowEnd) + 0.5) / resolution,
            maximumLatitude: maximumLatitude - (Double(rowStart) - 0.5) / resolution,
            westernmostLongitude: westernmostLongitude,
            easternmostLongitude: westernmostLongitude + Double(sourceSamples) / resolution
        ),
        "id": id,
        "role": role,
        "url": source.url,
        "sha256": source.sha256 ?? "",
        "bytes": source.bytes ?? 0,
        "sourceBytes": source.sourceBytes ?? 0,
        "byteRangeStart": source.byteRangeStart ?? 0,
        "byteRangeEnd": source.byteRangeEnd ?? 0,
        "sourceRowStart": rowStart,
        "sourceRowEnd": rowEnd,
        "sourceRowBytes": rowBytes,
        "mapResolutionPixelsPerDegree": resolution,
        "productId": productID,
        "productVersion": "V2.0",
        "labelURL": labelURL,
        "detail": detail
    ]
    if let postSpacingMeters, let residualCapRatio {
        manifest["postSpacingMeters"] = postSpacingMeters
        manifest["residualCapRatio"] = residualCapRatio
    }
    if let sourceMD5 = source.sourceMD5 {
        manifest["sourceMD5"] = sourceMD5
    }
    return manifest
}

func coverageManifest(
    minimumLatitude: Double,
    maximumLatitude: Double,
    westernmostLongitude: Double,
    easternmostLongitude: Double
) -> [String: Any] {
    [
        "minimumLatitudeDegrees": minimumLatitude,
        "maximumLatitudeDegrees": maximumLatitude,
        "westernmostLongitudeDegrees": westernmostLongitude,
        "easternmostLongitudeDegrees": easternmostLongitude
    ]
}

func nearManifestTile() -> [String: Any] {
    tileManifest(
        id: "near-field",
        posts: nearTilePosts,
        postSpacing: nearTilePostSpacingMeters,
        sourceIDs: ["nac-dtm-apollo11"],
        nativeSourceSpacing: dtmMetersPerPost,
        centimetersPerCount: 1,
        albedoTexels: nearAlbedoTexels,
        albedoMetersPerTexel: nacOrthoMetersPerPixel,
        albedoSourceIDs: [
            "wac-emp-643nm-304p-apollo11-slab",
            "nac-ortho-m150361817-50cm-slab",
            "nac-ortho-m150368601-50cm-slab",
        ],
        albedoEdgeHandling: "wac-base-with-radial-nac-high-pass-fade",
        edgeHandling: "measured",
        transitionWidth: nil,
        detail: "Dense near field around Tranquility Base."
    )
}

func mediumManifestTile() -> [String: Any] {
    tileManifest(
        id: "medium-field",
        posts: mediumTilePosts,
        postSpacing: mediumTilePostSpacingMeters,
        sourceIDs: [
            "nac-dtm-apollo11",
            "sldem2015-512-apollo11-slab",
            "wac-emp-643nm-304p-apollo11-slab",
        ],
        nativeSourceSpacing: sldemMediumMetersPerPost,
        centimetersPerCount: 1,
        albedoTexels: mediumAlbedoTexels,
        albedoMetersPerTexel: wacMediumMetersPerPixel,
        albedoSourceIDs: ["wac-emp-643nm-304p-apollo11-slab"],
        albedoEdgeHandling: "photometrically-normalized-source",
        edgeHandling: "inner-boundary-registered-bias-blend",
        transitionWidth: 1_024,
        detail: "SLDEM2015 medium field on a 32 m render grid; the inner collar is registered to the measured NAC boundary."
    )
}

func farManifestTile() -> [String: Any] {
    tileManifest(
        id: "far-field",
        posts: farTilePosts,
        postSpacing: farTilePostSpacingMeters,
        sourceIDs: [
            "sldem2015-512-apollo11-slab",
            "sldem2015-128-apollo11-slab",
            "wac-emp-643nm-304p-apollo11-slab",
            "wac-emp-643nm-64p-north-apollo11-slab",
            "wac-emp-643nm-64p-south-apollo11-slab",
        ],
        nativeSourceSpacing: sldemFarMetersPerPost,
        centimetersPerCount: 25,
        albedoTexels: farAlbedoTexels,
        albedoMetersPerTexel: wacFarMetersPerPixel,
        albedoSourceIDs: [
            "wac-emp-643nm-304p-apollo11-slab",
            "wac-emp-643nm-64p-north-apollo11-slab",
            "wac-emp-643nm-64p-south-apollo11-slab",
        ],
        albedoEdgeHandling: "inner-boundary-registered-reflectance-blend",
        edgeHandling: "inner-boundary-registered-bias-blend",
        transitionWidth: 16_384,
        detail: "Global SLDEM2015 far field covering 262.144 km on a 512 m render grid; the inner collar is registered to the medium field."
    )
}

func tileManifest(
    id: String,
    posts: Int,
    postSpacing: Double,
    sourceIDs: [String],
    nativeSourceSpacing: Double,
    centimetersPerCount: Int,
    albedoTexels: Int,
    albedoMetersPerTexel: Double,
    albedoSourceIDs: [String],
    albedoEdgeHandling: String,
    edgeHandling: String,
    transitionWidth: Double?,
    detail: String
) -> [String: Any] {
    var manifest: [String: Any] = [
        "id": id,
        "postsPerSide": posts,
        "postSpacingMeters": postSpacing,
        "extentMeters": Double(posts - 1) * postSpacing,
        "sourceIDs": sourceIDs,
        "nativeSourceSpacingMeters": nativeSourceSpacing,
        "heightEncoding": [
            "format": "PNG_GRAYSCALE_16LE",
            "centimetersPerCount": centimetersPerCount,
            "zeroPointMeters": "<tile minimum height relative to landing origin>",
            "detail": "Counts are centimeters above the tile minimum; add zeroPointMeters for meters above the landing-origin elevation."
        ],
        "albedoEncoding": [
            "format": "PNG_RGB_8",
            "colorSpace": "sRGB encoding of a linear 643 nm reflectance proxy",
            "texelsPerSide": albedoTexels,
            "metersPerTexel": albedoMetersPerTexel,
            "sourceIDs": albedoSourceIDs,
            "edgeHandling": albedoEdgeHandling,
            "detail": "Photometrically normalized WAC reflectance supplies broad tone. The near band adds bounded, exposure-normalized 0.5 m NAC high-frequency contrast while retaining the WAC value at its boundary. Mission lighting remains dynamic in-engine."
        ],
        "hillshadeEncoding": [
            "format": "PNG_RGB_8",
            "detail": "Diagnostic lambertian hillshade under the mission sun; not consumed by the app."
        ],
        "curvatureCorrected": true,
        "curvatureFormula": "z -= r*r / (2 * sphereRadiusMeters)",
        "edgeHandling": edgeHandling,
        "detail": detail
    ]
    if let transitionWidth {
        manifest["transitionWidthMeters"] = transitionWidth
    }
    return manifest
}

// MARK: - PDS label parsing and verification

func parseLabel(_ text: String) -> [String: String] {
    var values: [String: String] = [:]
    // PDS labels end lines with CRLF, which decodes as a single "\r\n"
    // grapheme; split on newline characters generally.
    for line in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { continue }
        var value = String(parts[1])
        // Drop PDS unit annotations like "2.0 <METERS/PIXEL>".
        if let unitStart = value.firstIndex(of: "<") {
            value = String(value[value.startIndex..<unitStart])
        }
        values[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
            value.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
    return values
}

func verifyLabel(_ labels: [String: String]) throws {
    func expect(_ key: String, _ expected: Double) throws {
        guard let text = labels[key], let value = Double(text) else {
            throw TerrainError("label missing or unparsable: \(key)")
        }
        if abs(value - expected) > abs(expected) * 1e-9 + 1e-9 {
            throw TerrainError("label \(key)=\(value) does not match pinned \(expected)")
        }
    }
    try expect("LINES", Double(dtmLines))
    try expect("LINE_SAMPLES", Double(dtmSamples))
    try expect("MAP_SCALE", dtmMetersPerPost)
    try expect("MAXIMUM_LATITUDE", dtmMaximumLatitude)
    try expect("MINIMUM_LATITUDE", dtmMinimumLatitude)
    try expect("EASTERNMOST_LONGITUDE", dtmEasternmostLongitude)
    try expect("WESTERNMOST_LONGITUDE", dtmWesternmostLongitude)
    if let noData = labels["NODATA"]?.lowercased(), !noData.isEmpty {
        // Label writes -3.40282266e+038 inside DESCRIPTION; not a standalone
        // keyword, so absence is acceptable.
        _ = noData
    }
}

func verifySLDEMLabel(
    _ labels: [String: String],
    productID: String,
    lines: Int,
    samples: Int,
    resolution: Double,
    maximumLatitude: Double,
    minimumLatitude: Double,
    westernmostLongitude: Double,
    easternmostLongitude: Double
) throws {
    func expect(_ key: String, _ expected: Double) throws {
        guard let text = labels[key], let value = Double(text) else {
            throw TerrainError("SLDEM label missing or unparsable: \(key)")
        }
        if abs(value - expected) > abs(expected) * 1e-9 + 1e-9 {
            throw TerrainError("SLDEM label \(key)=\(value) does not match pinned \(expected)")
        }
    }
    guard labels["PRODUCT_ID"] == productID else {
        throw TerrainError("SLDEM label PRODUCT_ID does not match \(productID)")
    }
    try expect("LINES", Double(lines))
    try expect("LINE_SAMPLES", Double(samples))
    try expect("MAP_RESOLUTION", resolution)
    try expect("MAXIMUM_LATITUDE", maximumLatitude)
    try expect("MINIMUM_LATITUDE", minimumLatitude)
    try expect("WESTERNMOST_LONGITUDE", westernmostLongitude)
    try expect("EASTERNMOST_LONGITUDE", easternmostLongitude)
    try expect("SAMPLE_BITS", 32)
    try expect("SCALING_FACTOR", 1)
    try expect("OFFSET", 1_737.4)
}

func verifyPDS4Metadata(
    resource: String,
    expectedFragments: [String]
) throws {
    guard let url = Bundle.module.url(forResource: resource, withExtension: "xml") else {
        throw TerrainError("bundled \(resource).xml is missing")
    }
    let text = try String(contentsOf: url, encoding: .utf8)
    for fragment in expectedFragments where !text.contains(fragment) {
        throw TerrainError("\(resource).xml does not contain pinned metadata: \(fragment)")
    }
}

struct TerrainError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Minimal GeoTIFF float32 reader

struct FloatGeoTIFF {
    let width: Int
    let height: Int
    /// Row-major samples, top row first.
    let samples: [Float]

    static func load(contentsOf url: URL) throws -> FloatGeoTIFF {
        let data = try Data(contentsOf: url)
        guard data.count >= 8 else { throw TerrainError("TIFF too small") }
        let endianBytes = [UInt8](data.prefix(2))
        guard endianBytes == [0x49, 0x49] || endianBytes == [0x4D, 0x4D] else {
            throw TerrainError("not a TIFF")
        }
        let littleEndian = endianBytes[0] == 0x49
        func u16(_ offset: Int) -> UInt16 {
            let b = [UInt8](data[offset..<offset + 2])
            return littleEndian
                ? UInt16(b[0]) | (UInt16(b[1]) << 8)
                : (UInt16(b[0]) << 8) | UInt16(b[1])
        }
        func u32(_ offset: Int) -> UInt32 {
            let b = [UInt8](data[offset..<offset + 4])
            return littleEndian
                ? UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
                : (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
        }
        guard u16(2) == 42 else { throw TerrainError("bad TIFF magic") }

        var width = 0
        var height = 0
        var bits = 0
        var compression = 0
        var sampleFormat = 0
        var rowsPerStrip = 0
        var stripOffsets: [Int] = []
        var stripCounts: [Int] = []

        var ifdOffset = Int(u32(4))
        while ifdOffset != 0 {
            let count = Int(u16(ifdOffset))
            var cursor = ifdOffset + 2
            for _ in 0..<count {
                let tag = Int(u16(cursor))
                let type = Int(u16(cursor + 2))
                let valueCount = Int(u32(cursor + 4))
                let typeSize: Int
                switch type {
                case 1, 2, 6, 7: typeSize = 1
                case 3, 8: typeSize = 2
                case 4, 9, 11, 12: typeSize = 4
                default: typeSize = 0
                }
                let byteCount = typeSize * valueCount
                let valueOffset = byteCount <= 4 ? cursor + 8 : Int(u32(cursor + 8))
                func scalar(_ index: Int) -> Int {
                    switch type {
                    case 1, 6, 7: return Int(data[valueOffset + index])
                    case 3, 8: return Int(u16(valueOffset + index * 2))
                    default: return Int(u32(valueOffset + index * 4))
                    }
                }
                switch tag {
                case 256: width = scalar(0)
                case 257: height = scalar(0)
                case 258: bits = scalar(0)
                case 259: compression = scalar(0)
                case 273:
                    stripOffsets = (0..<valueCount).map(scalar)
                case 277: break
                case 278: rowsPerStrip = scalar(0)
                case 279:
                    stripCounts = (0..<valueCount).map(scalar)
                case 339: sampleFormat = scalar(0)
                default: break
                }
                cursor += 12
            }
            ifdOffset = Int(u32(cursor))
        }

        guard bits == 32, compression == 1, sampleFormat == 3, rowsPerStrip == 1,
              stripOffsets.count == height, stripCounts.count == height,
              stripCounts.allSatisfy({ $0 == width * 4 })
        else {
            throw TerrainError(
                "unexpected TIFF layout (bits=\(bits) compression=\(compression) format=\(sampleFormat) strips=\(stripOffsets.count)/\(height))")
        }

        // Verified uniform strips: copy each row directly.
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let start = stripOffsets[row]
            data.withUnsafeBytes { raw in
                let src = raw.baseAddress!.advanced(by: start)
                let dst = bytes.withUnsafeMutableBytes { $0.baseAddress!.advanced(by: row * width * 4) }
                memcpy(dst, src, width * 4)
            }
        }
        // Verified little-endian float32 rows copied verbatim into the sample
        // buffer; every Apple host is little-endian like the GeoTIFF.
        var samples = [Float](repeating: 0, count: width * height)
        _ = samples.withUnsafeMutableBytes { dst in
            bytes.withUnsafeBytes { src in
                memcpy(dst.baseAddress, src.baseAddress, bytes.count)
            }
        }
        return FloatGeoTIFF(width: width, height: height, samples: samples)
    }

    subscript(line: Int, sample: Int) -> Float {
        samples[line * width + sample]
    }
}

// MARK: - Sampling helpers

struct GridSampler {
    let tif: FloatGeoTIFF

    var isValid: (Float) -> Bool { { $0 > -1e30 && $0 < 1e30 } }

    func bilinear(lineF: Double, sampleF: Double) -> Float? {
        let clampedLine = min(max(lineF, 0), Double(tif.height - 1))
        let clampedSample = min(max(sampleF, 0), Double(tif.width - 1))
        let l0 = Int(clampedLine.rounded(.down))
        let s0 = Int(clampedSample.rounded(.down))
        let l1 = min(l0 + 1, tif.height - 1)
        let s1 = min(s0 + 1, tif.width - 1)
        let fl = clampedLine - Double(l0)
        let fs = clampedSample - Double(s0)
        let v00 = tif[l0, s0], v01 = tif[l0, s1]
        let v10 = tif[l1, s0], v11 = tif[l1, s1]
        guard isValid(v00), isValid(v01), isValid(v10), isValid(v11) else { return nil }
        let top = Double(v00) * (1 - fs) + Double(v01) * fs
        let bottom = Double(v10) * (1 - fs) + Double(v11) * fs
        return Float(top * (1 - fl) + bottom * fl)
    }

    /// Expanding-ring nearest-valid search for NoData holes.
    func nearestValid(line: Int, sample: Int, maxRadius: Int = 64) -> Float? {
        if isValid(tif[line, sample]) { return tif[line, sample] }
        for radius in 1...maxRadius {
            var accumulator = 0.0
            var count = 0
            for dl in -radius...radius {
                let l = line + dl
                guard l >= 0, l < tif.height else { continue }
                for ds in -radius...radius where max(abs(dl), abs(ds)) == radius {
                    let s = sample + ds
                    guard s >= 0, s < tif.width else { continue }
                    let v = tif[l, s]
                    if isValid(v) {
                        accumulator += Double(v)
                        count += 1
                    }
                }
            }
            if count > 0 {
                return Float(accumulator / Double(count))
            }
        }
        return nil
    }
}

/// A contiguous set of complete rows fetched with one HTTP byte-range request
/// from a PDS PC_REAL SLDEM2015 product. Samples remain in their source pixel
/// registration and are converted from kilometers to meters only at lookup.
struct SLDEMFloatSlab {
    let sourceWidth: Int
    let sourceRowStart: Int
    let sourceRowEnd: Int
    let resolutionPixelsPerDegree: Double
    let maximumLatitudeDegrees: Double
    let westernmostLongitudeDegrees: Double
    let samples: [Float]

    static func load(
        contentsOf url: URL,
        source: PinnedSource,
        sourceWidth: Int,
        sourceRowStart: Int,
        sourceRowEnd: Int,
        resolutionPixelsPerDegree: Double,
        maximumLatitudeDegrees: Double,
        westernmostLongitudeDegrees: Double
    ) throws -> SLDEMFloatSlab {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = attributes[.size] as? Int ?? 0
        guard byteCount == source.bytes else {
            throw TerrainError("SLDEM slab size \(byteCount) != pinned \(source.bytes ?? 0)")
        }
        let digest = try sha256Hex(contentsOf: url)
        guard digest == source.sha256 else {
            throw TerrainError("SLDEM slab SHA-256 mismatch: \(digest)")
        }
        let expectedRows = sourceRowEnd - sourceRowStart + 1
        let expectedFloats = expectedRows * sourceWidth
        guard byteCount == expectedFloats * MemoryLayout<Float>.size else {
            throw TerrainError("SLDEM slab dimensions do not match its byte range")
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        var samples = [Float](repeating: 0, count: expectedFloats)
        _ = samples.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination)
        }
        guard samples.allSatisfy({ $0.isFinite && $0 > -20 && $0 < 20 }) else {
            throw TerrainError("SLDEM slab contains invalid kilometer heights")
        }
        print("verified SLDEM slab checksum \(digest.prefix(16))…")
        return SLDEMFloatSlab(
            sourceWidth: sourceWidth,
            sourceRowStart: sourceRowStart,
            sourceRowEnd: sourceRowEnd,
            resolutionPixelsPerDegree: resolutionPixelsPerDegree,
            maximumLatitudeDegrees: maximumLatitudeDegrees,
            westernmostLongitudeDegrees: westernmostLongitudeDegrees,
            samples: samples
        )
    }

    func elevationMeters(latitudeDegrees: Double, longitudeDegrees: Double) throws -> Double {
        // PDS pixel registration: the first center is half a post inside the
        // declared maximum latitude and westernmost longitude.
        let globalLine = (maximumLatitudeDegrees - latitudeDegrees)
            * resolutionPixelsPerDegree - 0.5
        let globalSample = (longitudeDegrees - westernmostLongitudeDegrees)
            * resolutionPixelsPerDegree - 0.5
        guard globalLine >= Double(sourceRowStart),
              globalLine <= Double(sourceRowEnd),
              globalSample >= 0,
              globalSample <= Double(sourceWidth - 1) else {
            throw TerrainError(
                String(format: "SLDEM slab misses lat %.6f lon %.6f", latitudeDegrees, longitudeDegrees)
            )
        }
        let localLine = globalLine - Double(sourceRowStart)
        let line0 = Int(floor(localLine))
        let sample0 = Int(floor(globalSample))
        let line1 = min(line0 + 1, sourceRowEnd - sourceRowStart)
        let sample1 = min(sample0 + 1, sourceWidth - 1)
        let lineFraction = localLine - Double(line0)
        let sampleFraction = globalSample - Double(sample0)
        func value(line: Int, sample: Int) -> Double {
            Double(samples[line * sourceWidth + sample])
        }
        let top = value(line: line0, sample: sample0) * (1 - sampleFraction)
            + value(line: line0, sample: sample1) * sampleFraction
        let bottom = value(line: line1, sample: sample0) * (1 - sampleFraction)
            + value(line: line1, sample: sample1) * sampleFraction
        return (top * (1 - lineFraction) + bottom * lineFraction) * 1_000.0
    }
}

/// Contiguous complete rows from a signed 16-bit LROC NAC orthophoto.
/// The two source observations are independently exposed, so their DNs are
/// normalized before only their high-frequency contrast is retained.
struct NACOrthoSlab {
    let sourceWidth: Int
    let sourceRowStart: Int
    let sourceRowEnd: Int
    let resolutionPixelsPerDegree: Double
    let maximumLatitudeDegrees: Double
    let westernmostLongitudeDegrees: Double
    let samples: [Int16]

    static func load(
        contentsOf url: URL,
        source: PinnedSource
    ) throws -> NACOrthoSlab {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = attributes[.size] as? Int ?? 0
        guard byteCount == source.bytes else {
            throw TerrainError("NAC orthophoto slab size \(byteCount) != pinned \(source.bytes ?? 0)")
        }
        let digest = try sha256Hex(contentsOf: url)
        guard digest == source.sha256 else {
            throw TerrainError("NAC orthophoto slab SHA-256 mismatch: \(digest)")
        }
        let expectedRows = nacOrthoRowEnd - nacOrthoRowStart + 1
        let expectedSamples = expectedRows * nacOrthoSamples
        guard byteCount == expectedSamples * MemoryLayout<Int16>.size else {
            throw TerrainError("NAC orthophoto slab dimensions do not match its byte range")
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        var samples = [Int16](repeating: 0, count: expectedSamples)
        _ = samples.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination)
        }
        let validCount = samples.reduce(into: 0) { count, value in
            if value > -32_764 { count += 1 }
        }
        guard validCount > expectedSamples / 2 else {
            throw TerrainError("NAC orthophoto slab contains insufficient valid image data")
        }
        print("verified NAC orthophoto slab checksum \(digest.prefix(16))…")
        return NACOrthoSlab(
            sourceWidth: nacOrthoSamples,
            sourceRowStart: nacOrthoRowStart,
            sourceRowEnd: nacOrthoRowEnd,
            resolutionPixelsPerDegree: nacOrthoResolutionPixelsPerDegree,
            maximumLatitudeDegrees: nacOrthoMaximumLatitude,
            westernmostLongitudeDegrees: nacOrthoWesternmostLongitude,
            samples: samples
        )
    }

    func dn(latitudeDegrees: Double, longitudeDegrees: Double) -> Double? {
        let globalLine = (maximumLatitudeDegrees - latitudeDegrees)
            * resolutionPixelsPerDegree - 0.5
        let globalSample = (longitudeDegrees - westernmostLongitudeDegrees)
            * resolutionPixelsPerDegree - 0.5
        guard globalLine >= Double(sourceRowStart) - 0.5,
              globalLine <= Double(sourceRowEnd) + 0.5,
              globalSample >= -0.5,
              globalSample <= Double(sourceWidth) - 0.5 else {
            return nil
        }
        let localLine = min(
            max(globalLine - Double(sourceRowStart), 0),
            Double(sourceRowEnd - sourceRowStart)
        )
        let sample = min(max(globalSample, 0), Double(sourceWidth - 1))
        let line0 = Int(floor(localLine))
        let sample0 = Int(floor(sample))
        let line1 = min(line0 + 1, sourceRowEnd - sourceRowStart)
        let sample1 = min(sample0 + 1, sourceWidth - 1)
        let lineFraction = localLine - Double(line0)
        let sampleFraction = sample - Double(sample0)
        func value(line: Int, sample: Int) -> Double? {
            let value = samples[line * sourceWidth + sample]
            return value > -32_764 ? Double(value) : nil
        }
        guard let v00 = value(line: line0, sample: sample0),
              let v01 = value(line: line0, sample: sample1),
              let v10 = value(line: line1, sample: sample0),
              let v11 = value(line: line1, sample: sample1) else {
            return nil
        }
        let top = v00 * (1 - sampleFraction) + v01 * sampleFraction
        let bottom = v10 * (1 - sampleFraction) + v11 * sampleFraction
        return top * (1 - lineFraction) + bottom * lineFraction
    }
}

/// A byte-range slab from the empirically normalized LROC WAC 643 nm mosaic.
/// Values are dimensionless reflectance at the product's standard geometry.
struct WACReflectanceSlab {
    let sourceWidth: Int
    let sourceRowStart: Int
    let sourceRowEnd: Int
    let resolutionPixelsPerDegree: Double
    let maximumLatitudeDegrees: Double
    let westernmostLongitudeDegrees: Double
    let samples: [Float]

    static func load(
        contentsOf url: URL,
        source: PinnedSource,
        sourceWidth: Int,
        sourceRowStart: Int,
        sourceRowEnd: Int,
        resolutionPixelsPerDegree: Double,
        maximumLatitudeDegrees: Double,
        westernmostLongitudeDegrees: Double
    ) throws -> WACReflectanceSlab {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = attributes[.size] as? Int ?? 0
        guard byteCount == source.bytes else {
            throw TerrainError("WAC reflectance slab size \(byteCount) != pinned \(source.bytes ?? 0)")
        }
        let digest = try sha256Hex(contentsOf: url)
        guard digest == source.sha256 else {
            throw TerrainError("WAC reflectance slab SHA-256 mismatch: \(digest)")
        }
        let expectedRows = sourceRowEnd - sourceRowStart + 1
        let expectedFloats = expectedRows * sourceWidth
        guard byteCount == expectedFloats * MemoryLayout<Float>.size else {
            throw TerrainError("WAC reflectance slab dimensions do not match its byte range")
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        var samples = [Float](repeating: 0, count: expectedFloats)
        _ = samples.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination)
        }
        let valid = samples.filter { $0.isFinite && $0 > 0 && $0 < 1 }
        guard valid.count > expectedFloats / 2 else {
            throw TerrainError("WAC reflectance slab contains insufficient valid data")
        }
        print("verified WAC reflectance slab checksum \(digest.prefix(16))…")
        return WACReflectanceSlab(
            sourceWidth: sourceWidth,
            sourceRowStart: sourceRowStart,
            sourceRowEnd: sourceRowEnd,
            resolutionPixelsPerDegree: resolutionPixelsPerDegree,
            maximumLatitudeDegrees: maximumLatitudeDegrees,
            westernmostLongitudeDegrees: westernmostLongitudeDegrees,
            samples: samples
        )
    }

    func reflectance(latitudeDegrees: Double, longitudeDegrees: Double) throws -> Double {
        let globalLine = (maximumLatitudeDegrees - latitudeDegrees)
            * resolutionPixelsPerDegree - 0.5
        let globalSample = (longitudeDegrees - westernmostLongitudeDegrees)
            * resolutionPixelsPerDegree - 0.5
        guard globalLine >= Double(sourceRowStart) - 0.5,
              globalLine <= Double(sourceRowEnd) + 0.5,
              globalSample >= -0.5,
              globalSample <= Double(sourceWidth) - 0.5 else {
            throw TerrainError(
                String(format: "WAC slab misses lat %.6f lon %.6f", latitudeDegrees, longitudeDegrees)
            )
        }
        let localLine = min(
            max(globalLine - Double(sourceRowStart), 0),
            Double(sourceRowEnd - sourceRowStart)
        )
        let sample = min(max(globalSample, 0), Double(sourceWidth - 1))
        let line0 = Int(floor(localLine))
        let sample0 = Int(floor(sample))
        let line1 = min(line0 + 1, sourceRowEnd - sourceRowStart)
        let sample1 = min(sample0 + 1, sourceWidth - 1)
        let lineFraction = localLine - Double(line0)
        let sampleFraction = sample - Double(sample0)
        func value(line: Int, sample: Int) throws -> Double {
            let value = samples[line * sourceWidth + sample]
            guard value.isFinite, value > 0, value < 1 else {
                throw TerrainError("WAC reflectance contains a special or invalid pixel")
            }
            return Double(value)
        }
        let v00 = try value(line: line0, sample: sample0)
        let v01 = try value(line: line0, sample: sample1)
        let v10 = try value(line: line1, sample: sample0)
        let v11 = try value(line: line1, sample: sample1)
        let top = v00 * (1 - sampleFraction) + v01 * sampleFraction
        let bottom = v10 * (1 - sampleFraction) + v11 * sampleFraction
        return top * (1 - lineFraction) + bottom * lineFraction
    }
}

struct AlbedoField {
    let texelsPerSide: Int
    let linearReflectance: [Float]
}

private struct RunningStatistics {
    var count = 0
    var mean = 0.0
    var m2 = 0.0

    mutating func add(_ value: Double) {
        count += 1
        let delta = value - mean
        mean += delta / Double(count)
        m2 += delta * (value - mean)
    }

    var standardDeviation: Double {
        count > 1 ? sqrt(m2 / Double(count - 1)) : 0
    }
}

func sampledAlbedoField(
    texelsPerSide: Int,
    extentMeters: Double,
    reflectance: (_ northMeters: Double, _ eastMeters: Double) throws -> Double
) throws -> AlbedoField {
    let spacing = extentMeters / Double(texelsPerSide - 1)
    let halfExtent = extentMeters / 2
    var values = [Float](repeating: 0, count: texelsPerSide * texelsPerSide)
    for row in 0..<texelsPerSide {
        let north = halfExtent - Double(row) * spacing
        for column in 0..<texelsPerSide {
            let east = Double(column) * spacing - halfExtent
            values[row * texelsPerSide + column] = Float(try reflectance(north, east))
        }
    }
    return AlbedoField(texelsPerSide: texelsPerSide, linearReflectance: values)
}

/// Build a near-field reflectance texture from normalized WAC broad tone and
/// only the locally high-passed, exposure-normalized detail shared by the two
/// registered 0.5 m NAC orthophotos. The high-frequency residual is strongest
/// at the landing-site origin and fades radially to exactly zero at the first
/// near-tile edge. A radial footprint avoids exposing the square NAC crop in
/// regional views while preserving essentially all source detail across the
/// terminal landing area.
func nearAlbedoField(
    orthoA: NACOrthoSlab,
    orthoB: NACOrthoSlab,
    broadReflectance: (_ northMeters: Double, _ eastMeters: Double) throws -> Double
) throws -> AlbedoField {
    let size = nearAlbedoTexels
    let spacing = nearTilePostSpacingMeters * Double(nearTilePosts - 1)
        / Double(size - 1)
    let halfExtent = nearTilePostSpacingMeters * Double(nearTilePosts - 1) / 2

    func sourceDN(
        _ source: NACOrthoSlab,
        row: Int,
        column: Int
    ) -> Double? {
        let north = halfExtent - Double(row) * spacing
        let east = Double(column) * spacing - halfExtent
        let coordinate = siteCoordinates(northMeters: north, eastMeters: east)
        return source.dn(
            latitudeDegrees: coordinate.latitude,
            longitudeDegrees: coordinate.longitude
        )
    }

    var statsA = RunningStatistics()
    var statsB = RunningStatistics()
    for row in stride(from: 0, to: size, by: 16) {
        for column in stride(from: 0, to: size, by: 16) {
            if let value = sourceDN(orthoA, row: row, column: column) {
                statsA.add(value)
            }
            if let value = sourceDN(orthoB, row: row, column: column) {
                statsB.add(value)
            }
        }
    }
    guard statsA.standardDeviation > 0, statsB.standardDeviation > 0 else {
        throw TerrainError("NAC orthophoto exposure statistics are degenerate")
    }
    print(String(
        format: "NAC orthophoto normalization: A %.2f±%.2f DN, B %.2f±%.2f DN",
        statsA.mean,
        statsA.standardDeviation,
        statsB.mean,
        statsB.standardDeviation
    ))

    var normalized = [Float](repeating: 0, count: size * size)
    for row in 0..<size {
        for column in 0..<size {
            guard let a = sourceDN(orthoA, row: row, column: column),
                  let b = sourceDN(orthoB, row: row, column: column) else {
                throw TerrainError("NAC orthophoto coverage hole inside the near tile")
            }
            let za = (a - statsA.mean) / statsA.standardDeviation
            let zb = (b - statsB.mean) / statsB.standardDeviation
            normalized[row * size + column] = Float((za + zb) / 2)
        }
    }

    let radius = Int((32.0 / spacing).rounded())
    var horizontalMean = [Float](repeating: 0, count: normalized.count)
    for row in 0..<size {
        var sum = 0.0
        var lower = 0
        var upper = min(radius, size - 1)
        for column in lower...upper {
            sum += Double(normalized[row * size + column])
        }
        for column in 0..<size {
            let count = upper - lower + 1
            horizontalMean[row * size + column] = Float(sum / Double(count))
            let nextLower = max(column + 1 - radius, 0)
            let nextUpper = min(column + 1 + radius, size - 1)
            while lower < nextLower {
                sum -= Double(normalized[row * size + lower])
                lower += 1
            }
            while upper < nextUpper {
                upper += 1
                sum += Double(normalized[row * size + upper])
            }
        }
    }

    var reflectance = [Float](repeating: 0, count: normalized.count)
    for column in 0..<size {
        var sum = 0.0
        var lower = 0
        var upper = min(radius, size - 1)
        for row in lower...upper {
            sum += Double(horizontalMean[row * size + column])
        }
        for row in 0..<size {
            let count = upper - lower + 1
            let localMean = sum / Double(count)
            let highFrequency = min(max(
                Double(normalized[row * size + column]) - localMean,
                -1.8
            ), 1.8)
            let north = halfExtent - Double(row) * spacing
            let east = Double(column) * spacing - halfExtent
            let normalizedInterior = max(
                0,
                1 - hypot(north, east) / halfExtent
            )
            let edgeWeight = normalizedInterior * normalizedInterior
                * (3 - 2 * normalizedInterior)
            let detailMultiplier = exp(highFrequency * 0.18 * edgeWeight)
            reflectance[row * size + column] = Float(
                try broadReflectance(north, east) * detailMultiplier
            )

            let nextLower = max(row + 1 - radius, 0)
            let nextUpper = min(row + 1 + radius, size - 1)
            while lower < nextLower {
                sum -= Double(horizontalMean[lower * size + column])
                lower += 1
            }
            while upper < nextUpper {
                upper += 1
                sum += Double(horizontalMean[upper * size + column])
            }
        }
    }
    return AlbedoField(texelsPerSide: size, linearReflectance: reflectance)
}

// MARK: - Tile generation

struct TileResult {
    let name: String
    let zeroPointMeters: Double
    let minimumHeightMeters: Double
    let maximumHeightMeters: Double
    let minimumLinearReflectance: Double
    let maximumLinearReflectance: Double
}

func metersPerDegree(latitudeDegrees: Double) -> (north: Double, east: Double) {
    let north = Double.pi / 180.0 * lunarRadiusMeters
    let east = north * cos(latitudeDegrees * .pi / 180.0)
    return (north, east)
}

func siteCoordinates(northMeters: Double, eastMeters: Double) -> (latitude: Double, longitude: Double) {
    let scale = metersPerDegree(latitudeDegrees: siteLatitudeDegrees)
    return (
        siteLatitudeDegrees + northMeters / scale.north,
        siteLongitudeDegrees + eastMeters / scale.east
    )
}

func curvatureDrop(northMeters: Double, eastMeters: Double) -> Double {
    (northMeters * northMeters + eastMeters * eastMeters) / (2.0 * lunarRadiusMeters)
}

func nacRelativeElevation(
    northMeters: Double,
    eastMeters: Double,
    sampler: GridSampler,
    siteElevationMeters: Double
) throws -> Double {
    let coordinate = siteCoordinates(northMeters: northMeters, eastMeters: eastMeters)
    let line = (dtmMaximumLatitude - coordinate.latitude)
        / (dtmMaximumLatitude - dtmMinimumLatitude) * Double(dtmLines - 1)
    let sample = (coordinate.longitude - dtmWesternmostLongitude)
        / (dtmEasternmostLongitude - dtmWesternmostLongitude) * Double(dtmSamples - 1)
    guard line >= 0, line <= Double(dtmLines - 1),
          sample >= 0, sample <= Double(dtmSamples - 1) else {
        throw TerrainError(
            String(format: "NAC DTM misses lat %.6f lon %.6f", coordinate.latitude, coordinate.longitude)
        )
    }
    let elevation = sampler.bilinear(lineF: line, sampleF: sample)
        ?? sampler.nearestValid(line: Int(line.rounded()), sample: Int(sample.rounded()))
    guard let elevation else {
        throw TerrainError("NAC DTM contains no valid sample at the requested coordinate")
    }
    return Double(elevation) - siteElevationMeters
        - curvatureDrop(northMeters: northMeters, eastMeters: eastMeters)
}

func sldemRelativeElevation(
    northMeters: Double,
    eastMeters: Double,
    slab: SLDEMFloatSlab,
    siteElevationMeters: Double
) throws -> Double {
    let coordinate = siteCoordinates(northMeters: northMeters, eastMeters: eastMeters)
    return try slab.elevationMeters(
        latitudeDegrees: coordinate.latitude,
        longitudeDegrees: coordinate.longitude
    ) - siteElevationMeters - curvatureDrop(northMeters: northMeters, eastMeters: eastMeters)
}

/// Preserve the entire inner tile boundary exactly, then fade only the outer
/// source's vertical bias over a collar. This prevents cracks or steps without
/// inventing high-frequency relief or changing either source away from the
/// registration band.
func boundaryRegisteredElevation(
    northMeters: Double,
    eastMeters: Double,
    innerHalfExtentMeters: Double,
    transitionWidthMeters: Double,
    innerElevation: (_ northMeters: Double, _ eastMeters: Double) throws -> Double,
    outerElevation: (_ northMeters: Double, _ eastMeters: Double) throws -> Double
) throws -> Double {
    let boundaryNorth = min(max(northMeters, -innerHalfExtentMeters), innerHalfExtentMeters)
    let boundaryEast = min(max(eastMeters, -innerHalfExtentMeters), innerHalfExtentMeters)
    let distance = hypot(northMeters - boundaryNorth, eastMeters - boundaryEast)
    if distance == 0 {
        return try innerElevation(northMeters, eastMeters)
    }
    let boundaryBias = try innerElevation(boundaryNorth, boundaryEast)
        - outerElevation(boundaryNorth, boundaryEast)
    let normalized = min(max(distance / transitionWidthMeters, 0), 1)
    let smooth = normalized * normalized * (3 - 2 * normalized)
    return try outerElevation(northMeters, eastMeters) + boundaryBias * (1 - smooth)
}

func generateTile(
    id: String,
    posts: Int,
    postSpacing: Double,
    centimetersPerCount: Int,
    relativeElevation: (_ northMeters: Double, _ eastMeters: Double) throws -> Double,
    albedoField: AlbedoField,
    sunENU: (x: Double, y: Double, z: Double),
    outDir: URL
) throws -> TileResult {
    let halfExtent = Double(posts - 1) / 2.0 * postSpacing
    var heights = [Double](repeating: 0, count: posts * posts)

    for row in 0..<posts {
        let northOffset = halfExtent - Double(row) * postSpacing
        for column in 0..<posts {
            let eastOffset = Double(column) * postSpacing - halfExtent
            heights[row * posts + column] = try relativeElevation(northOffset, eastOffset)
        }
    }

    let minHeight = heights.min() ?? 0
    let maxHeight = heights.max() ?? 0

    // Height PNG: 16-bit gray, centimeters above the tile minimum.
    var heightPixels = [UInt16](repeating: 0, count: posts * posts)
    for i in heights.indices {
        let counts = ((heights[i] - minHeight) * 100.0 / Double(centimetersPerCount)).rounded()
        guard counts <= Double(UInt16.max) else {
            throw TerrainError(
                "\(id): height span exceeds UInt16 at \(centimetersPerCount) cm/count"
            )
        }
        heightPixels[i] = UInt16(max(0, counts))
    }
    try writeGray16PNG(
        pixels: heightPixels,
        width: posts,
        height: posts,
        to: outDir.appendingPathComponent("\(id)-height.png")
    )

    guard albedoField.linearReflectance.count
            == albedoField.texelsPerSide * albedoField.texelsPerSide else {
        throw TerrainError("\(id): albedo field dimensions are inconsistent")
    }
    // Albedo PNG: encode the source-backed linear reflectance proxy into sRGB.
    // Shading still comes from mesh normals under the in-engine mission sun;
    // the diagnostic hillshade is never consumed by the app.
    var shadePixels = [UInt8](repeating: 0, count: posts * posts * 3)
    let inverseCentralDifferenceSpan = 1.0 / (2.0 * postSpacing)
    for row in 0..<posts {
        for column in 0..<posts {
            let p = (row * posts + column) * 3
            let l = min(max(row, 1), posts - 2)
            let s = min(max(column, 1), posts - 2)
            let northSlope = (heights[(l - 1) * posts + s] - heights[(l + 1) * posts + s])
                * inverseCentralDifferenceSpan
            let eastSlope = (heights[l * posts + s + 1] - heights[l * posts + s - 1])
                * inverseCentralDifferenceSpan
            var normal = SIMD3(-northSlope, -eastSlope, 1.0)
            normal = simd_normalize(normal)
            let lambert = max(Double(simd_dot(normal, SIMD3(sunENU.x, sunENU.y, sunENU.z))), 0)
            let shade = UInt8(max(0, min(255, ((0.16 + 0.84 * pow(lambert, 1.15)) * 255.0).rounded())))
            shadePixels[p] = shade
            shadePixels[p + 1] = shade
            shadePixels[p + 2] = shade
        }
    }
    var albedoPixels = [UInt8](
        repeating: 0,
        count: albedoField.texelsPerSide * albedoField.texelsPerSide * 3
    )
    for (index, value) in albedoField.linearReflectance.enumerated() {
        let encoded = linearReflectanceToSRGB8(Double(value))
        albedoPixels[index * 3] = encoded
        albedoPixels[index * 3 + 1] = encoded
        albedoPixels[index * 3 + 2] = encoded
    }
    try writeRGB8PNG(
        pixels: albedoPixels,
        width: albedoField.texelsPerSide,
        height: albedoField.texelsPerSide,
        to: outDir.appendingPathComponent("\(id)-albedo.png")
    )
    try writeRGB8PNG(
        pixels: shadePixels,
        width: posts,
        height: posts,
        to: outDir.appendingPathComponent("\(id)-hillshade.png")
    )

    return TileResult(
        name: id,
        zeroPointMeters: minHeight,
        minimumHeightMeters: minHeight,
        maximumHeightMeters: maxHeight,
        minimumLinearReflectance: Double(albedoField.linearReflectance.min() ?? 0),
        maximumLinearReflectance: Double(albedoField.linearReflectance.max() ?? 0)
    )
}

func linearReflectanceToSRGB8(_ reflectance: Double) -> UInt8 {
    let linear = min(max(reflectance, 0.015), 0.45)
    let srgb = linear <= 0.003_130_8
        ? 12.92 * linear
        : 1.055 * pow(linear, 1 / 2.4) - 0.055
    return UInt8(min(max((srgb * 255).rounded(), 0), 255))
}

// MARK: - PNG writing

func writeGray16PNG(pixels: [UInt16], width: Int, height: Int, to url: URL) throws {
    // CG reads 16-bit-per-component buffers big-endian by default.
    var bytes = [UInt8](repeating: 0, count: pixels.count * 2)
    for (index, value) in pixels.enumerated() {
        bytes[index * 2] = UInt8(value >> 8)
        bytes[index * 2 + 1] = UInt8(value & 0xff)
    }
    let space = CGColorSpace(name: CGColorSpace.linearGray)!
    let image = try makePNGImage(
        bytes: bytes,
        width: width,
        height: height,
        bitsPerComponent: 16,
        bitsPerPixel: 16,
        bytesPerRow: width * 2,
        space: space
    )
    try writePNG(image, to: url)
}

func writeRGB8PNG(pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let image = try makePNGImage(
        bytes: pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 24,
        bytesPerRow: width * 3,
        space: space
    )
    try writePNG(image, to: url)
}

func makePNGImage(
    bytes: [UInt8],
    width: Int,
    height: Int,
    bitsPerComponent: Int,
    bitsPerPixel: Int,
    bytesPerRow: Int,
    space: CGColorSpace
) throws -> CGImage {
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else {
        throw TerrainError("cannot create data provider for \(width)x\(height)")
    }
    guard let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bitsPerPixel: bitsPerPixel,
        bytesPerRow: bytesPerRow,
        space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        throw TerrainError("cannot build image \(width)x\(height)")
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    )
    guard destination != nil else { throw TerrainError("cannot create \(url.path)") }
    CGImageDestinationAddImage(destination!, image, nil)
    guard CGImageDestinationFinalize(destination!) else {
        throw TerrainError("cannot finalize \(url.path)")
    }
}

// MARK: - Main

func run() throws {
    var dtmPath: URL?
    var sldemMediumPath: URL?
    var sldemFarPath: URL?
    var nacOrthoAPath: URL?
    var nacOrthoBPath: URL?
    var wacMediumPath: URL?
    var wacFarNorthPath: URL?
    var wacFarSouthPath: URL?
    var outDir = URL(fileURLWithPath: "Packages/LunarMap/Sources/LunarMap/Resources/Terrain")
    var dryRun = false
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        if arguments[0] == "--dry-run" { dryRun = true; arguments.removeFirst(); continue }
        guard arguments.count >= 2 else {
            throw TerrainError("missing value for \(arguments[0])")
        }
        switch arguments[0] {
        case "--dtm":
            dtmPath = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        case "--sldem-medium":
            sldemMediumPath = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        case "--sldem-far":
            sldemFarPath = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        case "--nac-ortho-a":
            nacOrthoAPath = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        case "--nac-ortho-b":
            nacOrthoBPath = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        case "--wac-medium":
            wacMediumPath = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        case "--wac-far-north":
            wacFarNorthPath = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        case "--wac-far-south":
            wacFarSouthPath = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        case "--out":
            outDir = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        default:
            throw TerrainError("unknown argument \(arguments[0])")
        }
    }
    if dryRun { print("output: \(outDir.standardizedFileURL.path)"); return }
    guard let dtmPath, let sldemMediumPath, let sldemFarPath,
          let nacOrthoAPath, let nacOrthoBPath,
          let wacMediumPath, let wacFarNorthPath, let wacFarSouthPath else {
        throw TerrainError(
            "usage: Apollo11TerrainGenerator --dtm <NAC_DTM_APOLLO11.TIF> "
                + "--sldem-medium <SLDEM512-row-slab> --sldem-far <SLDEM128-row-slab> "
                + "--nac-ortho-a <NAC-50cm-row-slab> --nac-ortho-b <NAC-50cm-row-slab> "
                + "--wac-medium <WAC-304P-row-slab> "
                + "--wac-far-north <WAC-64P-north-row-slab> "
                + "--wac-far-south <WAC-64P-south-row-slab> --out <dir>"
        )
    }

    // Verify the download against the pinned checksum before anything else.
    let dtmDataAttributes = try FileManager.default.attributesOfItem(atPath: dtmPath.path)
    let dtmBytes = dtmDataAttributes[.size] as? Int ?? 0
    if let expectedBytes = pinnedDTM.bytes, dtmBytes != expectedBytes {
        throw TerrainError("DTM size \(dtmBytes) != pinned \(expectedBytes); redownload")
    }
    let digest = try sha256Hex(contentsOf: dtmPath)
    if let expectedDigest = pinnedDTM.sha256, digest != expectedDigest {
        throw TerrainError("DTM SHA-256 mismatch: \(digest)")
    }
    print("verified DTM checksum \(digest.prefix(16))…")

    // Cross-check the committed label constants against the actual file.
    guard let labelURL = Bundle.module.url(
        forResource: "NAC_DTM_APOLLO11",
        withExtension: "LBL"
    ) else {
        throw TerrainError("bundled NAC_DTM_APOLLO11.LBL is missing")
    }
    let labelText = try String(contentsOf: labelURL, encoding: .utf8)
    try verifyLabel(parseLabel(labelText))
    guard let mediumLabelURL = Bundle.module.url(
        forResource: "SLDEM2015_512_00N_30N_000_045_FLOAT",
        withExtension: "LBL"
    ), let farLabelURL = Bundle.module.url(
        forResource: "SLDEM2015_128_60S_60N_000_360_FLOAT",
        withExtension: "LBL"
    ) else {
        throw TerrainError("bundled SLDEM2015 labels are missing")
    }
    try verifySLDEMLabel(
        parseLabel(try String(contentsOf: mediumLabelURL, encoding: .utf8)),
        productID: "SLDEM2015_512_00N_30N_000_045_FLOAT",
        lines: sldemMediumRows,
        samples: sldemMediumSamples,
        resolution: sldemMediumResolutionPixelsPerDegree,
        maximumLatitude: 30,
        minimumLatitude: 0,
        westernmostLongitude: 0,
        easternmostLongitude: 45
    )
    try verifySLDEMLabel(
        parseLabel(try String(contentsOf: farLabelURL, encoding: .utf8)),
        productID: "SLDEM2015_128_60S_60N_000_360_FLOAT",
        lines: sldemFarRows,
        samples: sldemFarSamples,
        resolution: sldemFarResolutionPixelsPerDegree,
        maximumLatitude: 60,
        minimumLatitude: -60,
        westernmostLongitude: 0,
        easternmostLongitude: 360
    )
    try verifyPDS4Metadata(
        resource: "NAC_DTM_APOLLO11_M150361817_50CM",
        expectedFragments: [
            "<file_size unit=\"byte\">943743920</file_size>",
            "<md5_checksum>c3784f010eb6d6c2d84d6ee7b4088331</md5_checksum>",
            "<elements>55908</elements>",
            "<elements>8440</elements>",
            "<cart:pixel_scale_x unit=\"m/pixel\">0.49999999999999</cart:pixel_scale_x>",
        ]
    )
    try verifyPDS4Metadata(
        resource: "NAC_DTM_APOLLO11_M150368601_50CM",
        expectedFragments: [
            "<file_size unit=\"byte\">943743920</file_size>",
            "<md5_checksum>95decbebbf283e46d6146c47fec988ed</md5_checksum>",
            "<elements>55908</elements>",
            "<elements>8440</elements>",
        ]
    )
    try verifyPDS4Metadata(
        resource: "WAC_EMP_643NM_E300N0450_304P",
        expectedFragments: [
            "<file_size unit=\"byte\">1996295040</file_size>",
            "<md5_checksum>97af2366068cffb38415b3658993b4f1</md5_checksum>",
            "<elements>18240</elements>",
            "<elements>27360</elements>",
            "<cart:pixel_resolution_x unit=\"deg/pixel\">0.003289473684210526</cart:pixel_resolution_x>",
        ]
    )
    try verifyPDS4Metadata(
        resource: "WAC_EMP_643NM_E300N0450_064P",
        expectedFragments: [
            "<file_size unit=\"byte\">88496640</file_size>",
            "<md5_checksum>37e0144f3fa52cf91f9cb0aa605d9200</md5_checksum>",
            "<elements>3840</elements>",
            "<elements>5760</elements>",
        ]
    )
    try verifyPDS4Metadata(
        resource: "WAC_EMP_643NM_E300S0450_064P",
        expectedFragments: [
            "<file_size unit=\"byte\">88496640</file_size>",
            "<md5_checksum>53eb43347e3a96bc8fdb17c1f3207546</md5_checksum>",
            "<elements>3840</elements>",
            "<elements>5760</elements>",
        ]
    )
    print("PDS label constants verified")

    print("reading \(dtmPath.path)…")
    let tif = try FloatGeoTIFF.load(contentsOf: dtmPath)
    guard tif.width == dtmSamples, tif.height == dtmLines else {
        throw TerrainError("DTM dimensions \(tif.width)x\(tif.height) != label")
    }
    let sampler = GridSampler(tif: tif)
    let mediumSlab = try SLDEMFloatSlab.load(
        contentsOf: sldemMediumPath,
        source: pinnedSLDEMMedium,
        sourceWidth: sldemMediumSamples,
        sourceRowStart: sldemMediumRowStart,
        sourceRowEnd: sldemMediumRowEnd,
        resolutionPixelsPerDegree: sldemMediumResolutionPixelsPerDegree,
        maximumLatitudeDegrees: sldemMediumMaximumLatitude,
        westernmostLongitudeDegrees: sldemMediumWesternmostLongitude
    )
    let farSlab = try SLDEMFloatSlab.load(
        contentsOf: sldemFarPath,
        source: pinnedSLDEMFar,
        sourceWidth: sldemFarSamples,
        sourceRowStart: sldemFarRowStart,
        sourceRowEnd: sldemFarRowEnd,
        resolutionPixelsPerDegree: sldemFarResolutionPixelsPerDegree,
        maximumLatitudeDegrees: sldemFarMaximumLatitude,
        westernmostLongitudeDegrees: sldemFarWesternmostLongitude
    )
    let nacOrthoA = try NACOrthoSlab.load(
        contentsOf: nacOrthoAPath,
        source: pinnedNACOrthoA
    )
    let nacOrthoB = try NACOrthoSlab.load(
        contentsOf: nacOrthoBPath,
        source: pinnedNACOrthoB
    )
    let wacMedium = try WACReflectanceSlab.load(
        contentsOf: wacMediumPath,
        source: pinnedWACMedium,
        sourceWidth: wacMediumSamples,
        sourceRowStart: wacMediumRowStart,
        sourceRowEnd: wacMediumRowEnd,
        resolutionPixelsPerDegree: wacMediumResolutionPixelsPerDegree,
        maximumLatitudeDegrees: wacMediumMaximumLatitude,
        westernmostLongitudeDegrees: wacMediumWesternmostLongitude
    )
    let wacFarNorth = try WACReflectanceSlab.load(
        contentsOf: wacFarNorthPath,
        source: pinnedWACFarNorth,
        sourceWidth: wacFarSamples,
        sourceRowStart: wacFarNorthRowStart,
        sourceRowEnd: wacFarNorthRowEnd,
        resolutionPixelsPerDegree: wacFarResolutionPixelsPerDegree,
        maximumLatitudeDegrees: wacFarNorthMaximumLatitude,
        westernmostLongitudeDegrees: 0
    )
    let wacFarSouth = try WACReflectanceSlab.load(
        contentsOf: wacFarSouthPath,
        source: pinnedWACFarSouth,
        sourceWidth: wacFarSamples,
        sourceRowStart: wacFarSouthRowStart,
        sourceRowEnd: wacFarSouthRowEnd,
        resolutionPixelsPerDegree: wacFarResolutionPixelsPerDegree,
        maximumLatitudeDegrees: wacFarSouthMaximumLatitude,
        westernmostLongitudeDegrees: 0
    )

    let siteSample = (siteLongitudeDegrees - dtmWesternmostLongitude)
        / (dtmEasternmostLongitude - dtmWesternmostLongitude) * Double(dtmSamples - 1)
    let siteLine = (dtmMaximumLatitude - siteLatitudeDegrees)
        / (dtmMaximumLatitude - dtmMinimumLatitude) * Double(dtmLines - 1)
    guard let siteElevation = sampler.bilinear(lineF: siteLine, sampleF: siteSample) else {
        throw TerrainError("landing origin has no valid DTM elevation")
    }
    let mediumSiteElevation = try mediumSlab.elevationMeters(
        latitudeDegrees: siteLatitudeDegrees,
        longitudeDegrees: siteLongitudeDegrees
    )
    let farSiteElevation = try farSlab.elevationMeters(
        latitudeDegrees: siteLatitudeDegrees,
        longitudeDegrees: siteLongitudeDegrees
    )
    print(String(
        format: "landing origin elevations: NAC %.2f m, SLDEM512 %.2f m, SLDEM128 %.2f m",
        siteElevation,
        mediumSiteElevation,
        farSiteElevation
    ))

    let elevationRadians = sunElevationDegrees * .pi / 180.0
    let azimuthRadians = sunAzimuthDegreesClockwiseFromNorth * .pi / 180.0
    let sunENU = (
        x: cos(elevationRadians) * cos(azimuthRadians),
        y: cos(elevationRadians) * sin(azimuthRadians),
        z: sin(elevationRadians)
    )

    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let nearElevation: (Double, Double) throws -> Double = { north, east in
        try nacRelativeElevation(
            northMeters: north,
            eastMeters: east,
            sampler: sampler,
            siteElevationMeters: Double(siteElevation)
        )
    }
    let mediumSourceElevation: (Double, Double) throws -> Double = { north, east in
        try sldemRelativeElevation(
            northMeters: north,
            eastMeters: east,
            slab: mediumSlab,
            siteElevationMeters: mediumSiteElevation
        )
    }
    let mediumElevation: (Double, Double) throws -> Double = { north, east in
        try boundaryRegisteredElevation(
            northMeters: north,
            eastMeters: east,
            innerHalfExtentMeters: Double(nearTilePosts - 1) * nearTilePostSpacingMeters / 2,
            transitionWidthMeters: 1_024,
            innerElevation: nearElevation,
            outerElevation: mediumSourceElevation
        )
    }
    let farSourceElevation: (Double, Double) throws -> Double = { north, east in
        try sldemRelativeElevation(
            northMeters: north,
            eastMeters: east,
            slab: farSlab,
            siteElevationMeters: farSiteElevation
        )
    }
    let farElevation: (Double, Double) throws -> Double = { north, east in
        try boundaryRegisteredElevation(
            northMeters: north,
            eastMeters: east,
            innerHalfExtentMeters: Double(mediumTilePosts - 1) * mediumTilePostSpacingMeters / 2,
            transitionWidthMeters: 16_384,
            innerElevation: mediumElevation,
            outerElevation: farSourceElevation
        )
    }

    let mediumReflectance: (Double, Double) throws -> Double = { north, east in
        let coordinate = siteCoordinates(northMeters: north, eastMeters: east)
        return try wacMedium.reflectance(
            latitudeDegrees: coordinate.latitude,
            longitudeDegrees: coordinate.longitude
        )
    }
    let farSourceReflectance: (Double, Double) throws -> Double = { north, east in
        let coordinate = siteCoordinates(northMeters: north, eastMeters: east)
        let source = coordinate.latitude >= 0 ? wacFarNorth : wacFarSouth
        return try source.reflectance(
            latitudeDegrees: coordinate.latitude,
            longitudeDegrees: coordinate.longitude
        )
    }
    let farReflectance: (Double, Double) throws -> Double = { north, east in
        try boundaryRegisteredElevation(
            northMeters: north,
            eastMeters: east,
            innerHalfExtentMeters: Double(mediumTilePosts - 1)
                * mediumTilePostSpacingMeters / 2,
            transitionWidthMeters: 16_384,
            innerElevation: mediumReflectance,
            outerElevation: farSourceReflectance
        )
    }
    print("generating source-backed albedo fields…")
    let nearAlbedo = try nearAlbedoField(
        orthoA: nacOrthoA,
        orthoB: nacOrthoB,
        broadReflectance: mediumReflectance
    )
    let mediumAlbedo = try sampledAlbedoField(
        texelsPerSide: mediumAlbedoTexels,
        extentMeters: Double(mediumTilePosts - 1) * mediumTilePostSpacingMeters,
        reflectance: mediumReflectance
    )
    let farAlbedo = try sampledAlbedoField(
        texelsPerSide: farAlbedoTexels,
        extentMeters: Double(farTilePosts - 1) * farTilePostSpacingMeters,
        reflectance: farReflectance
    )

    let near = try generateTile(
        id: "near-field",
        posts: nearTilePosts,
        postSpacing: nearTilePostSpacingMeters,
        centimetersPerCount: 1,
        relativeElevation: nearElevation,
        albedoField: nearAlbedo,
        sunENU: sunENU,
        outDir: outDir
    )
    let medium = try generateTile(
        id: "medium-field",
        posts: mediumTilePosts,
        postSpacing: mediumTilePostSpacingMeters,
        centimetersPerCount: 1,
        relativeElevation: mediumElevation,
        albedoField: mediumAlbedo,
        sunENU: sunENU,
        outDir: outDir
    )
    let far = try generateTile(
        id: "far-field",
        posts: farTilePosts,
        postSpacing: farTilePostSpacingMeters,
        centimetersPerCount: 25,
        relativeElevation: farElevation,
        albedoField: farAlbedo,
        sunENU: sunENU,
        outDir: outDir
    )

    var manifest = manifestJSON()
    manifest["landingOriginElevationMeters"] = Double(siteElevation)
    manifest["sourceLandingOriginElevationsMeters"] = [
        "nac-dtm-apollo11": Double(siteElevation),
        "sldem2015-512-apollo11-slab": mediumSiteElevation,
        "sldem2015-128-apollo11-slab": farSiteElevation
    ]
    manifest["toolSHA256"] = try sha256Hex(
        contentsOf: URL(fileURLWithPath: #filePath)
    )
    for (index, result) in [near, medium, far].enumerated() {
        var tile = manifest["tiles"] as! [[String: Any]]
        tile[index]["zeroPointMeters"] = result.zeroPointMeters
        tile[index]["minimumHeightMeters"] = result.minimumHeightMeters
        tile[index]["maximumHeightMeters"] = result.maximumHeightMeters
        tile[index]["heightFile"] = "\(result.name)-height.png"
        tile[index]["albedoFile"] = "\(result.name)-albedo.png"
        var albedoEncoding = tile[index]["albedoEncoding"] as! [String: Any]
        albedoEncoding["minimumLinearReflectance"] = result.minimumLinearReflectance
        albedoEncoding["maximumLinearReflectance"] = result.maximumLinearReflectance
        tile[index]["albedoEncoding"] = albedoEncoding
        manifest["tiles"] = tile
    }
    var jsonData = try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.prettyPrinted, .sortedKeys]
    )
    jsonData.append(0x0A)
    try jsonData.write(to: outDir.appendingPathComponent("TerrainManifest.json"))

    for result in [near, medium, far] {
        print(String(
            format: "%@: heights %.1f…%.1f m (zero %.1f m), reflectance %.4f…%.4f",
            result.name,
            result.minimumHeightMeters,
            result.maximumHeightMeters,
            result.zeroPointMeters,
            result.minimumLinearReflectance,
            result.maximumLinearReflectance
        ))
    }
    print("wrote \(outDir.path)")
}

import simd

func sha256Hex(contentsOf url: URL) throws -> String {
    // Streaming SHA-256 so the 118 MB DTM never sits fully resident twice.
    var context = SHA256Context()
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    while true {
        let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
        if chunk.isEmpty { break }
        context.update(chunk)
    }
    return context.finalHex()
}

// Compact streaming SHA-256 (matches AGCSHA256 vectors).
struct SHA256Context {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]
    private var h: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]
    private var pending = [UInt8]()
    private var totalBytes: UInt64 = 0

    mutating func update(_ data: Data) {
        totalBytes += UInt64(data.count)
        pending.append(contentsOf: data)
        var offset = 0
        while pending.count - offset >= 64 {
            compress(Array(pending[offset..<offset + 64]))
            offset += 64
        }
        pending.removeFirst(offset)
    }

    mutating func finalHex() -> String {
        let bitLength = totalBytes * 8
        update(Data([0x80]))
        while pending.count % 64 != 56 {
            update(Data([0]))
        }
        var lengthBytes = [UInt8]()
        for shift in stride(from: 56, through: 0, by: -8) {
            lengthBytes.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }
        update(Data(lengthBytes))
        return h.map { String(format: "%02x%02x%02x%02x", ($0 >> 24) & 0xff, ($0 >> 16) & 0xff, ($0 >> 8) & 0xff, $0 & 0xff) }.joined()
    }

    private mutating func compress(_ block: [UInt8]) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            w[i] = UInt32(block[i * 4]) << 24 | UInt32(block[i * 4 + 1]) << 16
                | UInt32(block[i * 4 + 2]) << 8 | UInt32(block[i * 4 + 3])
        }
        for i in 16..<64 {
            let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var a = h[0], b = h[1], c = h[2], d = h[3]
        var e = h[4], f = h[5], g = h[6], hh = h[7]
        for i in 0..<64 {
            let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch = (e & f) ^ (~e & g)
            let temp1 = hh &+ s1 &+ ch &+ Self.k[i] &+ w[i]
            let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ maj
            hh = g; g = f; f = e; e = d &+ temp1
            d = c; c = b; b = a; a = temp1 &+ temp2
        }
        h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
        h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
    }

    private func rotr(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}

try run()
