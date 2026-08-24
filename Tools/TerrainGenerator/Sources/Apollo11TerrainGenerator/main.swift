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
//     --out LM/Terrain

// MARK: - Pinned sources (Docs/visionOS Immersive.md)

struct PinnedSource {
    let url: String
    let sha256: String?
    let bytes: Int?
    let sourceBytes: Int?
    let byteRangeStart: Int?
    let byteRangeEnd: Int?
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

/// Apollo 11 retroreflector (LRR-3) alignment per Docs/visionOS Immersive.md.
let siteLatitudeDegrees = 0.673_433
let siteLongitudeDegrees = 23.473_113

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

/// Mission-appropriate sun at touchdown (1969-07-20T20:17:40Z): low sun out of
/// the west-southwest. Elevation from ALSJ mission-planning data; azimuth is
/// an approximation recorded in the manifest detail.
let sunElevationDegrees = 10.77
let sunAzimuthDegreesClockwiseFromNorth = 276.4

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

// MARK: - Manifest model (mirrored by LM/LM/LMTerrainManifest.swift)

func manifestJSON() -> [String: Any] {
    [
        "schemaVersion": 1,
        "scenarioID": "apollo11-progressive-real-data-terrain",
        "landingOrigin": [
            "latitudeDegrees": siteLatitudeDegrees,
            "longitudeDegrees": siteLongitudeDegrees,
            "detail": "Apollo 11 retroreflector alignment; heights are relative to the DTM elevation sampled at this point."
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
                "id": "nac-dtm-apollo11",
                "role": "geometry",
                "url": pinnedDTM.url,
                "sha256": pinnedDTM.sha256 ?? "",
                "bytes": pinnedDTM.bytes ?? 0,
                "productId": "NAC_DTM_APOLLO11",
                "productVersion": "v1.9",
                "labelURL": pinnedLabel.url,
                "detail": "LROC NAC DTM. The companion photometric orthophoto (NAC_ANAPOLLO11.EOR) is not present in volume LROLRC_2001; committed albedo layers are flat neutral regolith until a pinned orthophoto source is added, and the mission-sun DirectionalLight shades the mesh normals. Per-tile hillshade PNGs are regenerable diagnostics."
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
                detail: "Exact PDS byte-range slab covering the 262.144 km Apollo 11 far field. Native SLDEM2015 posts are about 236.9 m at the equator; the 512 m render grid is boundary-registered to the medium field."
            )
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
    detail: String
) -> [String: Any] {
    [
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
}

func nearManifestTile() -> [String: Any] {
    tileManifest(
        id: "near-field",
        posts: nearTilePosts,
        postSpacing: nearTilePostSpacingMeters,
        sourceIDs: ["nac-dtm-apollo11"],
        nativeSourceSpacing: dtmMetersPerPost,
        centimetersPerCount: 1,
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
        sourceIDs: ["nac-dtm-apollo11", "sldem2015-512-apollo11-slab"],
        nativeSourceSpacing: sldemMediumMetersPerPost,
        centimetersPerCount: 1,
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
        sourceIDs: ["sldem2015-512-apollo11-slab", "sldem2015-128-apollo11-slab"],
        nativeSourceSpacing: sldemFarMetersPerPost,
        centimetersPerCount: 25,
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
            "detail": "Flat neutral regolith (RGB 140). Shading is applied in-engine from tile mesh normals under the mission sun."
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

// MARK: - Tile generation

struct TileResult {
    let name: String
    let zeroPointMeters: Double
    let minimumHeightMeters: Double
    let maximumHeightMeters: Double
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

    // Albedo PNG: flat neutral regolith. Shading comes from the mesh normals
    // under the in-engine mission sun; a baked hillshade would double-shade.
    // The hillshade is still written beside the manifest as a diagnostic.
    var shadePixels = [UInt8](repeating: 0, count: posts * posts * 3)
    var albedoPixels = [UInt8](repeating: 0, count: posts * posts * 3)
    let inverseCentralDifferenceSpan = 1.0 / (2.0 * postSpacing)
    for row in 0..<posts {
        for column in 0..<posts {
            let p = (row * posts + column) * 3
            albedoPixels[p] = 140
            albedoPixels[p + 1] = 140
            albedoPixels[p + 2] = 140
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
    try writeRGB8PNG(
        pixels: albedoPixels,
        width: posts,
        height: posts,
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
        maximumHeightMeters: maxHeight
    )
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
    var outDir = URL(fileURLWithPath: "LM/Terrain")
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
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
        case "--out":
            outDir = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        default:
            throw TerrainError("unknown argument \(arguments[0])")
        }
    }
    guard let dtmPath, let sldemMediumPath, let sldemFarPath else {
        throw TerrainError(
            "usage: Apollo11TerrainGenerator --dtm <NAC_DTM_APOLLO11.TIF> "
                + "--sldem-medium <SLDEM512-row-slab> --sldem-far <SLDEM128-row-slab> --out <dir>"
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

    let near = try generateTile(
        id: "near-field",
        posts: nearTilePosts,
        postSpacing: nearTilePostSpacingMeters,
        centimetersPerCount: 1,
        relativeElevation: nearElevation,
        sunENU: sunENU,
        outDir: outDir
    )
    let medium = try generateTile(
        id: "medium-field",
        posts: mediumTilePosts,
        postSpacing: mediumTilePostSpacingMeters,
        centimetersPerCount: 1,
        relativeElevation: mediumElevation,
        sunENU: sunENU,
        outDir: outDir
    )
    let far = try generateTile(
        id: "far-field",
        posts: farTilePosts,
        postSpacing: farTilePostSpacingMeters,
        centimetersPerCount: 25,
        relativeElevation: farElevation,
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
        manifest["tiles"] = tile
    }
    var jsonData = try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.prettyPrinted, .sortedKeys]
    )
    jsonData.append(0x0A)
    try jsonData.write(to: outDir.appendingPathComponent("TerrainManifest.json"))

    for result in [near, medium, far] {
        print(String(format: "%@: heights %.1f…%.1f m (zero %.1f m)", result.name, result.minimumHeightMeters, result.maximumHeightMeters, result.zeroPointMeters))
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
