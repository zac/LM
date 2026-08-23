import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum GeneratorError: Error, CustomStringConvertible {
    case usage
    case cannotLoadImage(URL)
    case unsupportedDTM(String)
    case cropOutsideSource
    case cannotWritePNG(URL)

    var description: String {
        switch self {
        case .usage:
            return "Usage: Apollo11TerrainGenerator <NAC_DTM_APOLLO11.TIF> <NAC_DTM_APOLLO11_SHADE.TIF> <output-directory>"
        case .cannotLoadImage(let url):
            return "Could not decode \(url.path)"
        case .unsupportedDTM(let reason):
            return "Unsupported DTM: \(reason)"
        case .cropOutsideSource:
            return "The Apollo 11 site crop falls outside the source DTM."
        case .cannotWritePNG(let url):
            return "Could not write \(url.path)"
        }
    }
}

private struct TerrainManifest: Codable {
    let schemaVersion: Int
    let productID: String
    let sourceDTMURL: String
    let sourceHillshadeURL: String
    let sourceDTMSHA256: String
    let sourceHillshadeSHA256: String
    let sourceWidthPixels: Int
    let sourceHeightPixels: Int
    let sourcePostSpacingMeters: Double
    let sourceMinimumLatitudeDegrees: Double
    let sourceMaximumLatitudeDegrees: Double
    let sourceWesternLongitudeDegrees: Double
    let sourceEasternLongitudeDegrees: Double
    let landingLatitudeDegrees: Double
    let landingLongitudeDegrees: Double
    let landingPixelX: Int
    let landingPixelY: Int
    let cropOriginX: Int
    let cropOriginY: Int
    let cropSizePixels: Int
    let meshWidth: Int
    let meshHeight: Int
    let meshSampleStridePixels: Int
    let meshSpacingMeters: Double
    let landingElevationMeters: Float
    let minimumRelativeElevationMeters: Float
    let maximumRelativeElevationMeters: Float
    let heightEncoding: String
    let axisConvention: String
}

private struct FloatTIFF {
    let image: CGImage
    let data: Data

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let providerData = image.dataProvider?.data else {
            throw GeneratorError.cannotLoadImage(url)
        }
        guard image.bitsPerComponent == 32,
              image.bitsPerPixel == 32,
              image.bytesPerRow == image.width * MemoryLayout<Float>.size else {
            throw GeneratorError.unsupportedDTM(
                "expected one uncompressed 32-bit float per pixel; got \(image.bitsPerComponent) bits/component, \(image.bitsPerPixel) bits/pixel, \(image.bytesPerRow) bytes/row"
            )
        }
        self.image = image
        self.data = providerData as Data
    }

    func value(x: Int, y: Int) -> Float {
        data.withUnsafeBytes { bytes in
            bytes.loadUnaligned(
                fromByteOffset: (y * image.width + x) * MemoryLayout<Float>.size,
                as: Float.self
            )
        }
    }
}

private let sourceDTMURL = "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/SDP/NAC_DTM/APOLLO11/NAC_DTM_APOLLO11.TIF"
private let sourceHillshadeURL = "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/SDP/NAC_DTM/APOLLO11/NAC_DTM_APOLLO11_SHADE.TIF"

// Values come from NAC_DTM_APOLLO11.LBL. The site coordinate is the NASA
// Apollo 11 Lunar Surface Journal mission-overview coordinate.
private let sourceWidth = 2_111
private let sourceHeight = 13_978
private let postSpacingMeters = 2.000_000_000_000_6
private let minimumLatitude = 0.314_609
private let maximumLatitude = 1.236_538_8
private let westernLongitude = 23.372_275_8
private let easternLongitude = 23.511_529_6
private let landingLatitude = 0.674_09
private let landingLongitude = 23.472_98

private let cropRadiusPixels = 512
private let cropSizePixels = cropRadiusPixels * 2 + 1
private let meshSampleStride = 4
private let meshSize = cropSizePixels / meshSampleStride + 1

private func pixelX(longitude: Double) -> Int {
    Int(((longitude - westernLongitude) / (easternLongitude - westernLongitude)
         * Double(sourceWidth - 1)).rounded())
}

private func pixelY(latitude: Double) -> Int {
    Int(((maximumLatitude - latitude) / (maximumLatitude - minimumLatitude)
         * Double(sourceHeight - 1)).rounded())
}

private func sha256(url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 4 * 1_024 * 1_024), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private func writeHillshadeCrop(
    sourceURL: URL,
    outputURL: URL,
    cropOriginX: Int,
    cropOriginY: Int
) throws {
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw GeneratorError.cannotLoadImage(sourceURL)
    }
    guard image.width == sourceWidth, image.height == sourceHeight,
          let grayscaleCrop = image.cropping(to: CGRect(
            x: cropOriginX,
            y: cropOriginY,
            width: cropSizePixels,
            height: cropSizePixels
          )),
          let colorContext = CGContext(
            data: nil,
            width: cropSizePixels,
            height: cropSizePixels,
            bitsPerComponent: 8,
            bytesPerRow: cropSizePixels * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          ) else {
        throw GeneratorError.cannotWritePNG(outputURL)
    }

    // The PDS hillshade is a one-channel grayscale TIFF. RealityKit interprets
    // that PNG as a red-only texture, so explicitly expand luminance into RGB.
    colorContext.interpolationQuality = .none
    colorContext.draw(
        grayscaleCrop,
        in: CGRect(x: 0, y: 0, width: cropSizePixels, height: cropSizePixels)
    )
    guard let colorCrop = colorContext.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
          ) else {
        throw GeneratorError.cannotWritePNG(outputURL)
    }
    CGImageDestinationAddImage(destination, colorCrop, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw GeneratorError.cannotWritePNG(outputURL)
    }
}

private func run() throws {
    guard CommandLine.arguments.count == 4 else { throw GeneratorError.usage }

    let dtmURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let hillshadeURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let dtm = try FloatTIFF(url: dtmURL)
    guard dtm.image.width == sourceWidth, dtm.image.height == sourceHeight else {
        throw GeneratorError.unsupportedDTM(
            "expected \(sourceWidth)x\(sourceHeight), got \(dtm.image.width)x\(dtm.image.height)"
        )
    }

    let landingX = pixelX(longitude: landingLongitude)
    let landingY = pixelY(latitude: landingLatitude)
    let cropOriginX = landingX - cropRadiusPixels
    let cropOriginY = landingY - cropRadiusPixels
    guard cropOriginX >= 0, cropOriginY >= 0,
          cropOriginX + cropSizePixels <= sourceWidth,
          cropOriginY + cropSizePixels <= sourceHeight else {
        throw GeneratorError.cropOutsideSource
    }

    let landingElevation = dtm.value(x: landingX, y: landingY)
    guard landingElevation.isFinite, landingElevation > -1e20 else {
        throw GeneratorError.unsupportedDTM("landing-site pixel is NoData")
    }

    var heights = Data(capacity: meshSize * meshSize * MemoryLayout<Float>.size)
    var minimumRelative = Float.greatestFiniteMagnitude
    var maximumRelative = -Float.greatestFiniteMagnitude
    for row in 0..<meshSize {
        for column in 0..<meshSize {
            let sourceX = cropOriginX + column * meshSampleStride
            let sourceY = cropOriginY + row * meshSampleStride
            let sourceElevation = dtm.value(x: sourceX, y: sourceY)
            guard sourceElevation.isFinite, sourceElevation > -1e20 else {
                throw GeneratorError.unsupportedDTM("NoData inside the requested cockpit crop at \(sourceX),\(sourceY)")
            }
            var relative = sourceElevation - landingElevation
            minimumRelative = min(minimumRelative, relative)
            maximumRelative = max(maximumRelative, relative)
            withUnsafeBytes(of: &relative) { heights.append(contentsOf: $0) }
        }
    }

    let heightURL = outputDirectory.appendingPathComponent("Apollo11TerrainHeightmap.bin")
    let hillshadeOutputURL = outputDirectory.appendingPathComponent("Apollo11TerrainHillshade.png")
    let manifestURL = outputDirectory.appendingPathComponent("Apollo11Terrain.json")
    try heights.write(to: heightURL, options: .atomic)
    try writeHillshadeCrop(
        sourceURL: hillshadeURL,
        outputURL: hillshadeOutputURL,
        cropOriginX: cropOriginX,
        cropOriginY: cropOriginY
    )

    let manifest = TerrainManifest(
        schemaVersion: 1,
        productID: "NAC_DTM_APOLLO11",
        sourceDTMURL: sourceDTMURL,
        sourceHillshadeURL: sourceHillshadeURL,
        sourceDTMSHA256: try sha256(url: dtmURL),
        sourceHillshadeSHA256: try sha256(url: hillshadeURL),
        sourceWidthPixels: sourceWidth,
        sourceHeightPixels: sourceHeight,
        sourcePostSpacingMeters: postSpacingMeters,
        sourceMinimumLatitudeDegrees: minimumLatitude,
        sourceMaximumLatitudeDegrees: maximumLatitude,
        sourceWesternLongitudeDegrees: westernLongitude,
        sourceEasternLongitudeDegrees: easternLongitude,
        landingLatitudeDegrees: landingLatitude,
        landingLongitudeDegrees: landingLongitude,
        landingPixelX: landingX,
        landingPixelY: landingY,
        cropOriginX: cropOriginX,
        cropOriginY: cropOriginY,
        cropSizePixels: cropSizePixels,
        meshWidth: meshSize,
        meshHeight: meshSize,
        meshSampleStridePixels: meshSampleStride,
        meshSpacingMeters: postSpacingMeters * Double(meshSampleStride),
        landingElevationMeters: landingElevation,
        minimumRelativeElevationMeters: minimumRelative,
        maximumRelativeElevationMeters: maximumRelative,
        heightEncoding: "row-major little-endian Float32 meters relative to the landing-site post",
        axisConvention: "+X east, +Z south, +Y elevation; the app maps simulation +Y north onto RealityKit -Z"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

    print("Generated \(meshSize)x\(meshSize) terrain at \(manifest.meshSpacingMeters)m spacing")
    print("Landing pixel: \(landingX),\(landingY); elevation: \(landingElevation)m")
    print("Relative elevation: \(minimumRelative)...\(maximumRelative)m")
    print("Output: \(outputDirectory.path)")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
