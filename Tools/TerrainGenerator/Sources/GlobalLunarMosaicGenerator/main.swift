import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

private enum WACGlobal16PPD {
    static let productID = "WAC_GLOBAL_E000N0000_016P"
    static let productVersion = "v1.3"
    static let sourceURL =
        "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/BDR/WAC_GLOBAL/WAC_GLOBAL_E000N0000_016P.IMG"
    static let sourceByteCount = 66_378_240
    static let sourceSHA256 =
        "c75a49b48df0d1d8afad8f25e58332599e8383e4967424ffbb0ba38b0808b2b6"
    static let labelByteCount = 23_040
    static let width = 5_760
    static let height = 2_880
    static let pixelsPerDegree = 16.0
    static let metersPerPixel = 1_895.209_401_509_3
    static let minimumLatitudeDegrees = -90.0
    static let maximumLatitudeDegrees = 90.0
    static let westernmostLongitudeDegrees = -180.0
    static let easternmostLongitudeDegrees = 180.0
    static let lunarRadiusMeters = 1_737_400.0

    /// Matches the fixed, source-preserving transfer used by the existing
    /// Apollo 11 terrain generator. The product contains a linear reflectance
    /// proxy; PNG stores its display-safe sRGB encoding without normalizing
    /// each globe independently.
    static let minimumLinearReflectance = 0.015
    static let maximumLinearReflectance = 0.45
}

private enum GeneratorError: LocalizedError {
    case usage
    case invalidSourceByteCount(actual: Int)
    case invalidSourceHash(actual: String)
    case invalidLabel(String)
    case invalidImageData
    case couldNotCreateDestination
    case couldNotWritePNG

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: GlobalLunarMosaicGenerator <WAC_GLOBAL...IMG> <output.png> [metadata.json]"
        case .invalidSourceByteCount(let actual):
            return "Expected \(WACGlobal16PPD.sourceByteCount) source bytes, received \(actual)."
        case .invalidSourceHash(let actual):
            return "Pinned source SHA-256 mismatch: \(actual)"
        case .invalidLabel(let field):
            return "Attached PDS label does not contain the expected \(field)."
        case .invalidImageData:
            return "Could not create a CGImage from the decoded WAC pixels."
        case .couldNotCreateDestination:
            return "Could not create the PNG destination."
        case .couldNotWritePNG:
            return "ImageIO failed to finalize the PNG."
        }
    }
}

private struct PixelStatistics: Codable {
    let validPixelCount: Int
    let invalidPixelCount: Int
    let minimumLinearReflectance: Double
    let maximumLinearReflectance: Double
    let meanLinearReflectance: Double
}

private struct OutputMetadata: Codable {
    struct Source: Codable {
        let productID: String
        let productVersion: String
        let url: String
        let byteCount: Int
        let sha256: String
        let sampleType: String
        let sampleBits: Int
    }

    struct Texture: Codable {
        let file: String
        let width: Int
        let height: Int
        let format: String
        let colorSpace: String
        let sha256: String
        let minimumLinearReflectance: Double
        let maximumLinearReflectance: Double
    }

    struct Projection: Codable {
        let mapProjectionType: String
        let latitudeType: String
        let positiveLongitudeDirection: String
        let pixelsPerDegree: Double
        let metersPerPixel: Double
        let minimumLatitudeDegrees: Double
        let maximumLatitudeDegrees: Double
        let westernmostLongitudeDegrees: Double
        let easternmostLongitudeDegrees: Double
        let lunarRadiusMeters: Double
    }

    let schemaVersion: Int
    let generatorVersion: String
    let generatorSHA256: String
    let source: Source
    let texture: Texture
    let projection: Projection
    let statistics: PixelStatistics
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func validateLabel(in source: Data) throws {
    let labelData = source.prefix(WACGlobal16PPD.labelByteCount)
    guard let label = String(data: labelData, encoding: .ascii) else {
        throw GeneratorError.invalidLabel("ASCII encoding")
    }

    var fields: [String: String] = [:]
    for rawLine in label.split(whereSeparator: { $0.isNewline }) {
        let line = String(rawLine)
        guard let equals = line.firstIndex(of: "=") else { continue }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: equals)...]
            .trimmingCharacters(in: .whitespaces)
        fields[key] = value
    }

    let requiredFields = [
        "PRODUCT_ID": WACGlobal16PPD.productID,
        "PRODUCT_VERSION_ID": "\"\(WACGlobal16PPD.productVersion)\"",
        "RECORD_BYTES": String(WACGlobal16PPD.labelByteCount),
        "LABEL_RECORDS": "1",
        "^IMAGE": "2",
        "MAP_PROJECTION_TYPE": "EQUIRECTANGULAR",
        "COORDINATE_SYSTEM_NAME": "PLANETOCENTRIC",
        "POSITIVE_LONGITUDE_DIRECTION": "EAST",
        "LINES": String(WACGlobal16PPD.height),
        "LINE_SAMPLES": String(WACGlobal16PPD.width),
        "SAMPLE_TYPE": "PC_REAL",
        "SAMPLE_BITS": "32"
    ]

    for (key, expectedValue) in requiredFields where fields[key] != expectedValue {
        throw GeneratorError.invalidLabel("\(key) = \(expectedValue)")
    }
}

private func linearReflectanceToSRGB8(_ reflectance: Float) -> UInt8 {
    let clamped = min(
        max(Double(reflectance), WACGlobal16PPD.minimumLinearReflectance),
        WACGlobal16PPD.maximumLinearReflectance
    )
    let srgb = clamped <= 0.003_130_8
        ? clamped * 12.92
        : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    return UInt8((min(max(srgb, 0), 1) * 255).rounded())
}

private func decodePixels(_ source: Data) -> ([UInt8], PixelStatistics) {
    let pixelCount = WACGlobal16PPD.width * WACGlobal16PPD.height
    var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
    var validCount = 0
    var invalidCount = 0
    var minimum = Double.greatestFiniteMagnitude
    var maximum = -Double.greatestFiniteMagnitude
    var sum = 0.0

    source.withUnsafeBytes { rawBytes in
        for pixelIndex in 0..<pixelCount {
            let sourceOffset = WACGlobal16PPD.labelByteCount
                + pixelIndex * MemoryLayout<UInt32>.size
            let bits = rawBytes.loadUnaligned(fromByteOffset: sourceOffset, as: UInt32.self)
                .littleEndian
            let value = Float(bitPattern: bits)
            let isValid = value.isFinite && value >= 0 && value < 1
            let reflectance: Float
            if isValid {
                reflectance = value
                validCount += 1
                minimum = min(minimum, Double(value))
                maximum = max(maximum, Double(value))
                sum += Double(value)
            } else {
                reflectance = Float(WACGlobal16PPD.minimumLinearReflectance)
                invalidCount += 1
            }

            let encoded = linearReflectanceToSRGB8(reflectance)
            let outputOffset = pixelIndex * 4
            pixels[outputOffset] = encoded
            pixels[outputOffset + 1] = encoded
            pixels[outputOffset + 2] = encoded
            pixels[outputOffset + 3] = 255
        }
    }

    return (
        pixels,
        PixelStatistics(
            validPixelCount: validCount,
            invalidPixelCount: invalidCount,
            minimumLinearReflectance: minimum,
            maximumLinearReflectance: maximum,
            meanLinearReflectance: sum / Double(max(validCount, 1))
        )
    )
}

private func writePNG(pixels: [UInt8], to outputURL: URL) throws {
    let bytesPerRow = WACGlobal16PPD.width * 4
    let pixelData = Data(pixels)
    guard let provider = CGDataProvider(data: pixelData as CFData),
          let image = CGImage(
            width: WACGlobal16PPD.width,
            height: WACGlobal16PPD.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
          ) else {
        throw GeneratorError.invalidImageData
    }

    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        "public.png" as CFString,
        1,
        nil
    ) else {
        throw GeneratorError.couldNotCreateDestination
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw GeneratorError.couldNotWritePNG
    }
}

private func run() throws {
    guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
        throw GeneratorError.usage
    }

    let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let metadataURL = CommandLine.arguments.count == 4
        ? URL(fileURLWithPath: CommandLine.arguments[3])
        : outputURL.deletingPathExtension().appendingPathExtension("json")

    let source = try Data(contentsOf: inputURL, options: .mappedIfSafe)
    guard source.count == WACGlobal16PPD.sourceByteCount else {
        throw GeneratorError.invalidSourceByteCount(actual: source.count)
    }
    let sourceHash = sha256Hex(source)
    guard sourceHash == WACGlobal16PPD.sourceSHA256 else {
        throw GeneratorError.invalidSourceHash(actual: sourceHash)
    }
    try validateLabel(in: source)

    let (pixels, statistics) = decodePixels(source)
    try writePNG(pixels: pixels, to: outputURL)
    let textureData = try Data(contentsOf: outputURL, options: .mappedIfSafe)
    let textureHash = sha256Hex(textureData)
    let generatorHash = try sha256Hex(
        Data(contentsOf: URL(fileURLWithPath: #filePath), options: .mappedIfSafe)
    )

    let metadata = OutputMetadata(
        schemaVersion: 1,
        generatorVersion: "wac-global-morphologic-v1",
        generatorSHA256: generatorHash,
        source: .init(
            productID: WACGlobal16PPD.productID,
            productVersion: WACGlobal16PPD.productVersion,
            url: WACGlobal16PPD.sourceURL,
            byteCount: WACGlobal16PPD.sourceByteCount,
            sha256: WACGlobal16PPD.sourceSHA256,
            sampleType: "PC_REAL",
            sampleBits: 32
        ),
        texture: .init(
            file: outputURL.lastPathComponent,
            width: WACGlobal16PPD.width,
            height: WACGlobal16PPD.height,
            format: "RGBA8 PNG",
            colorSpace: "sRGB encoding of linear reflectance proxy",
            sha256: textureHash,
            minimumLinearReflectance: WACGlobal16PPD.minimumLinearReflectance,
            maximumLinearReflectance: WACGlobal16PPD.maximumLinearReflectance
        ),
        projection: .init(
            mapProjectionType: "EQUIRECTANGULAR",
            latitudeType: "PLANETOCENTRIC",
            positiveLongitudeDirection: "EAST",
            pixelsPerDegree: WACGlobal16PPD.pixelsPerDegree,
            metersPerPixel: WACGlobal16PPD.metersPerPixel,
            minimumLatitudeDegrees: WACGlobal16PPD.minimumLatitudeDegrees,
            maximumLatitudeDegrees: WACGlobal16PPD.maximumLatitudeDegrees,
            westernmostLongitudeDegrees: WACGlobal16PPD.westernmostLongitudeDegrees,
            easternmostLongitudeDegrees: WACGlobal16PPD.easternmostLongitudeDegrees,
            lunarRadiusMeters: WACGlobal16PPD.lunarRadiusMeters
        ),
        statistics: statistics
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var metadataData = try encoder.encode(metadata)
    metadataData.append(0x0A)
    try metadataData.write(to: metadataURL, options: .atomic)

    print("Generated \(outputURL.path)")
    print("Texture SHA-256: \(textureHash)")
    print(
        "Valid pixels: \(statistics.validPixelCount); mean linear reflectance: "
            + String(format: "%.8f", statistics.meanLinearReflectance)
    )
}

do {
    try run()
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
