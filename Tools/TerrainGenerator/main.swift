import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Terrain preprocessing for the full-immersion Apollo 11 terminal descent.
//
// Source-pinned pipeline: reads the LROC NAC DTM product for the Apollo 11
// landing site (NAC_DTM_APOLLO11, volume LROLRC_2001), verifies it against the
// committed PDS label, and emits two georeferenced tiles — a dense near-field
// tile around Tranquility Base and a coarser horizon tile — plus a provenance
// manifest recording source URLs, SHA-256 checksums, projection, sampling, and
// the landing origin.
//
// Usage:
//   swift Tools/TerrainGenerator/main.swift \
//     --dtm Tools/TerrainGenerator/cache/NAC_DTM_APOLLO11.TIF \
//     [--ortho path/to/orthophoto] \
//     --out LM/Terrain

// MARK: - Pinned sources (Docs/visionOS Immersive.md)

struct PinnedSource {
    let url: String
    let sha256: String?
    let bytes: Int?
}

let pinnedDTM = PinnedSource(
    url: "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/SDP/NAC_DTM/APOLLO11/NAC_DTM_APOLLO11.TIF",
    sha256: "920da622e3d7c3f047c67a970b5429aaadf00f886804e3fc6c72f6e5298043e9",
    bytes: 118_142_727
)
let pinnedLabel = PinnedSource(
    url: "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/SDP/NAC_DTM/APOLLO11/NAC_DTM_APOLLO11.LBL",
    sha256: nil,
    bytes: nil
)

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

let nearTilePosts = 1024
let nearTilePostSpacingMeters = 2.0
let horizonTilePosts = 512
let horizonTilePostSpacingMeters = 32.0

// MARK: - Manifest model (mirrored by LM/LM/LMTerrainManifest.swift)

func manifestJSON() -> [String: Any] {
    [
        "schemaVersion": 1,
        "scenarioID": "apollo11-source-backed-foundation",
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
                "role": "geometry-and-albedo",
                "url": pinnedDTM.url,
                "sha256": pinnedDTM.sha256 ?? "",
                "bytes": pinnedDTM.bytes ?? 0,
                "productId": "NAC_DTM_APOLLO11",
                "productVersion": "v1.9",
                "labelURL": pinnedLabel.url,
                "detail": "LROC NAC DTM. The companion photometric orthophoto (NAC_ANAPOLLO11.EOR) is not present in volume LROLRC_2001; committed albedo layers are flat neutral regolith until a pinned orthophoto source is added, and the mission-sun DirectionalLight shades the mesh normals. Per-tile hillshade PNGs are regenerable diagnostics."
            ]
        ],
        "tiles": [
            nearManifestTile(),
            horizonManifestTile()
        ]
    ]
}

func nearManifestTile() -> [String: Any] {
    tileManifest(
        id: "near-field",
        posts: nearTilePosts,
        postSpacing: nearTilePostSpacingMeters,
        detail: "Dense near field around Tranquility Base."
    )
}

func horizonManifestTile() -> [String: Any] {
    tileManifest(
        id: "horizon",
        posts: horizonTilePosts,
        postSpacing: horizonTilePostSpacingMeters,
        detail: "Lower-resolution relief for the far field and skyline."
    )
}

func tileManifest(id: String, posts: Int, postSpacing: Double, detail: String) -> [String: Any] {
    [
        "id": id,
        "postsPerSide": posts,
        "postSpacingMeters": postSpacing,
        "extentMeters": Double(posts - 1) * postSpacing,
        "heightEncoding": [
            "format": "PNG_GRAYSCALE_16LE",
            "centimetersPerCount": 1,
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
        "edgeHandling": "clamped-extrapolation",
        "detail": detail
    ]
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
        samples.withUnsafeMutableBytes { dst in
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

func generateTile(
    id: String,
    posts: Int,
    postSpacing: Double,
    sampler: GridSampler,
    siteLine: Double,
    siteSample: Double,
    siteElevation: Double,
    sunENU: (x: Double, y: Double, z: Double),
    outDir: URL
) throws -> TileResult {
    let mDeg = metersPerDegree(latitudeDegrees: siteLatitudeDegrees)
    let halfExtent = Double(posts - 1) / 2.0 * postSpacing
    var heights = [Double](repeating: 0, count: posts * posts)

    for row in 0..<posts {
        let northOffset = halfExtent - Double(row) * postSpacing
        for column in 0..<posts {
            let eastOffset = Double(column) * postSpacing - halfExtent
            let lat = siteLatitudeDegrees + northOffset / mDeg.north
            let lon = siteLongitudeDegrees + eastOffset / mDeg.east
            let lineF = (dtmMaximumLatitude - lat)
                / (dtmMaximumLatitude - dtmMinimumLatitude)
                * Double(dtmLines - 1)
            let sampleF = (lon - dtmWesternmostLongitude)
                / (dtmEasternmostLongitude - dtmWesternmostLongitude)
                * Double(dtmSamples - 1)
            // Beyond the DTM footprint the nearest covered elevation is held
            // (clamped extrapolation); the curvature term still drops distant
            // ground below the skyline.
            let clampedLine = min(max(lineF, 0), Double(dtmLines - 1))
            let clampedSample = min(max(sampleF, 0), Double(dtmSamples - 1))
            let value = sampler.bilinear(lineF: clampedLine, sampleF: clampedSample)
                ?? sampler.nearestValid(
                    line: Int(clampedLine.rounded()),
                    sample: Int(clampedSample.rounded())
                )
            guard let value else {
                throw TerrainError("\(id): no valid DTM coverage at lat \(lat), lon \(lon)")
            }
            let radiusSquared = northOffset * northOffset + eastOffset * eastOffset
            let curvatureDrop = radiusSquared / (2.0 * lunarRadiusMeters)
            heights[row * posts + column] = Double(value) - siteElevation - curvatureDrop
        }
    }

    let minHeight = heights.min() ?? 0
    let maxHeight = heights.max() ?? 0

    // Height PNG: 16-bit gray, centimeters above the tile minimum.
    var heightPixels = [UInt16](repeating: 0, count: posts * posts)
    for i in heights.indices {
        let centimeters = ((heights[i] - minHeight) * 100.0).rounded()
        heightPixels[i] = UInt16(max(0, min(65_535, centimeters)))
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
    let normalScale = 100.0 / postSpacing
    for row in 0..<posts {
        for column in 0..<posts {
            let p = (row * posts + column) * 3
            albedoPixels[p] = 140
            albedoPixels[p + 1] = 140
            albedoPixels[p + 2] = 140
            let l = min(max(row, 1), posts - 2)
            let s = min(max(column, 1), posts - 2)
            let dzdnorth = -(heights[(l - 1) * posts + s] - heights[(l + 1) * posts + s]) * normalScale
            let dzdeast = (heights[l * posts + s + 1] - heights[l * posts + s - 1]) * normalScale
            var normal = SIMD3(dzdnorth, dzdeast, 1.0)
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
    let destination = try CGImageDestinationCreateWithURL(
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
    var orthoPath: URL? // Reserved for a pinned photometric orthophoto source.
    var outDir = URL(fileURLWithPath: "LM/Terrain")
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        switch arguments[0] {
        case "--dtm":
            dtmPath = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        case "--ortho":
            orthoPath = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        case "--out":
            outDir = URL(fileURLWithPath: arguments[1]); arguments.removeFirst(2)
        default:
            throw TerrainError("unknown argument \(arguments[0])")
        }
    }
    guard let dtmPath else {
        throw TerrainError("usage: main.swift --dtm <NAC_DTM_APOLLO11.TIF> [--ortho <EOR>] --out <dir>")
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
    if let labelText = try? String(contentsOf: URL(
        fileURLWithPath: "Tools/TerrainGenerator/Sources/NAC_DTM_APOLLO11.LBL"
    ), encoding: .utf8) {
        try verifyLabel(parseLabel(labelText))
        print("label constants verified")
    }

    print("reading \(dtmPath.path)…")
    let tif = try FloatGeoTIFF.load(contentsOf: dtmPath)
    guard tif.width == dtmSamples, tif.height == dtmLines else {
        throw TerrainError("DTM dimensions \(tif.width)x\(tif.height) != label")
    }
    let sampler = GridSampler(tif: tif)

    let siteSample = (siteLongitudeDegrees - dtmWesternmostLongitude)
        / (dtmEasternmostLongitude - dtmWesternmostLongitude) * Double(dtmSamples - 1)
    let siteLine = (dtmMaximumLatitude - siteLatitudeDegrees)
        / (dtmMaximumLatitude - dtmMinimumLatitude) * Double(dtmLines - 1)
    guard let siteElevation = sampler.bilinear(lineF: siteLine, sampleF: siteSample) else {
        throw TerrainError("landing origin has no valid DTM elevation")
    }
    print(String(format: "site pixel (%.1f, %.1f), elevation %.2f m", siteSample, siteLine, siteElevation))

    let elevationRadians = sunElevationDegrees * .pi / 180.0
    let azimuthRadians = sunAzimuthDegreesClockwiseFromNorth * .pi / 180.0
    let sunENU = (
        x: cos(elevationRadians) * cos(azimuthRadians),
        y: cos(elevationRadians) * sin(azimuthRadians),
        z: sin(elevationRadians)
    )

    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let near = try generateTile(
        id: "near-field",
        posts: nearTilePosts,
        postSpacing: nearTilePostSpacingMeters,
        sampler: sampler,
        siteLine: siteLine,
        siteSample: siteSample,
        siteElevation: Double(siteElevation),
        sunENU: sunENU,
        outDir: outDir
    )
    let horizon = try generateTile(
        id: "horizon",
        posts: horizonTilePosts,
        postSpacing: horizonTilePostSpacingMeters,
        sampler: sampler,
        siteLine: siteLine,
        siteSample: siteSample,
        siteElevation: Double(siteElevation),
        sunENU: sunENU,
        outDir: outDir
    )

    var manifest = manifestJSON()
    manifest["generated"] = ISO8601DateFormatter().string(from: Date())
    manifest["landingOriginElevationMeters"] = Double(siteElevation)
    manifest["toolSHA256"] = digest
    for (index, result) in [near, horizon].enumerated() {
        var tile = manifest["tiles"] as! [[String: Any]]
        tile[index]["zeroPointMeters"] = result.zeroPointMeters
        tile[index]["minimumHeightMeters"] = result.minimumHeightMeters
        tile[index]["maximumHeightMeters"] = result.maximumHeightMeters
        tile[index]["heightFile"] = "\(result.name)-height.png"
        tile[index]["albedoFile"] = "\(result.name)-albedo.png"
        manifest["tiles"] = tile
    }
    let jsonData = try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.prettyPrinted, .sortedKeys]
    )
    try jsonData.write(to: outDir.appendingPathComponent("TerrainManifest.json"))

    for result in [near, horizon] {
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
