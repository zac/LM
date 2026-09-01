import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import simd

private struct WACGlobalProduct {
    let productID: String
    let productVersion: String
    let sourceURL: String
    let sourceByteCount: Int
    let sourceSHA256: String
    let labelByteCount: Int
    let width: Int
    let height: Int
    let pixelsPerDegree: Double
    let metersPerPixel: Double

    let minimumLatitudeDegrees = -90.0
    let maximumLatitudeDegrees = 90.0
    let westernmostLongitudeDegrees = -180.0
    let easternmostLongitudeDegrees = 180.0
    let lunarRadiusMeters = 1_737_400.0
}

private enum WACGlobalProducts {
    static let sixteenPPD = WACGlobalProduct(
        productID: "WAC_GLOBAL_E000N0000_016P",
        productVersion: "v1.3",
        sourceURL: "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/BDR/WAC_GLOBAL/WAC_GLOBAL_E000N0000_016P.IMG",
        sourceByteCount: 66_378_240,
        sourceSHA256: "c75a49b48df0d1d8afad8f25e58332599e8383e4967424ffbb0ba38b0808b2b6",
        labelByteCount: 23_040,
        width: 5_760,
        height: 2_880,
        pixelsPerDegree: 16,
        metersPerPixel: 1_895.209_401_509_3
    )

    static let sixtyFourPPD = WACGlobalProduct(
        productID: "WAC_GLOBAL_E000N0000_064P",
        productVersion: "v1.3",
        sourceURL: "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/BDR/WAC_GLOBAL/WAC_GLOBAL_E000N0000_064P.IMG",
        sourceByteCount: 1_061_775_360,
        sourceSHA256: "bc1feab6e86ae2cf47798a4f00cdf7f5e73030fcbc2223fba7fab59a5a2a34ec",
        labelByteCount: 92_160,
        width: 23_040,
        height: 11_520,
        pixelsPerDegree: 64,
        metersPerPixel: 473.802_350_377_34
    )

    static let all = [sixteenPPD, sixtyFourPPD]

    static func product(sourceByteCount: Int) -> WACGlobalProduct? {
        all.first { $0.sourceByteCount == sourceByteCount }
    }
}

private enum WACGlobalTransfer {
    /// Matches the fixed, source-preserving transfer used by the existing
    /// Apollo 11 terrain generator. The product contains a linear reflectance
    /// proxy; PNG stores its display-safe sRGB encoding without normalizing
    /// each globe independently.
    static let minimumLinearReflectance = 0.015
    static let maximumLinearReflectance = 0.45
}

private enum LOLALDEM16 {
    static let sourceID = "lola-ldem-16ppd-global"
    static let productID = "LDEM_16"
    static let productVersion = "V3.1"
    static let dataSetID = "LRO-L-LOLA-4-GDR-V1.0"
    static let sourceURL =
        "https://imbrium.mit.edu/DATA/LOLA_GDR/CYLINDRICAL/IMG/LDEM_16.IMG"
    static let labelURL =
        "https://imbrium.mit.edu/DATA/LOLA_GDR/CYLINDRICAL/IMG/LDEM_16.LBL"
    static let sourceByteCount = 33_177_600
    static let sourceSHA256 =
        "a511e40d7a3ea3275945b4da2a1df377133264fab0be94b7434b1cf8907254cb"
    static let labelByteCount = 5_121
    static let labelSHA256 =
        "9aef29463ccc6ed3a3fbe0df3ecd830a99c69e16b564f455507dee2697096579"
    static let width = 5_760
    static let height = 2_880
    static let pixelsPerDegree = 16.0
    static let metersPerPixel = 1_895.209_401_509_3
    static let scalingFactorMeters = 0.5
    static let datumOffsetMeters = 1_737_400.0
}

private enum GeneratorError: LocalizedError {
    case usage
    case invalidSourceByteCount(actual: Int)
    case invalidSourceHash(actual: String)
    case invalidLabel(String)
    case invalidImageData
    case incompleteElevationOptions
    case invalidElevationByteCount(actual: Int)
    case invalidElevationHash(actual: String)
    case invalidElevationLabelByteCount(actual: Int)
    case invalidElevationLabelHash(actual: String)
    case invalidElevationLabel(String)
    case couldNotCreateDestination
    case couldNotWritePNG

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: GlobalLunarMosaicGenerator <WAC_GLOBAL...IMG> <output.png> [metadata.json] [--elevation <LDEM_16.IMG> --elevation-label <LDEM_16.LBL> --normal-output <normal.png>]"
        case .invalidSourceByteCount(let actual):
            let supported = WACGlobalProducts.all
                .map { "\($0.productID)=\($0.sourceByteCount)" }
                .joined(separator: ", ")
            return "Unsupported WAC source byte count \(actual); expected one of \(supported)."
        case .invalidSourceHash(let actual):
            return "Pinned source SHA-256 mismatch: \(actual)"
        case .invalidLabel(let field):
            return "Attached PDS label does not contain the expected \(field)."
        case .invalidImageData:
            return "Could not create a CGImage from the decoded WAC pixels."
        case .incompleteElevationOptions:
            return "--elevation, --elevation-label, and --normal-output must be supplied together."
        case .invalidElevationByteCount(let actual):
            return "Expected \(LOLALDEM16.sourceByteCount) LDEM_16 bytes, received \(actual)."
        case .invalidElevationHash(let actual):
            return "Pinned LDEM_16 SHA-256 mismatch: \(actual)"
        case .invalidElevationLabelByteCount(let actual):
            return "Expected \(LOLALDEM16.labelByteCount) LDEM_16 label bytes, received \(actual)."
        case .invalidElevationLabelHash(let actual):
            return "Pinned LDEM_16 label SHA-256 mismatch: \(actual)"
        case .invalidElevationLabel(let field):
            return "LDEM_16 PDS label does not contain the expected \(field)."
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

    struct NormalMap: Codable {
        let file: String
        let width: Int
        let height: Int
        let format: String
        let coordinateFrame: String
        let encoding: String
        let sha256: String
        let sourceID: String
        let detail: String
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
    let elevationSource: Source?
    let texture: Texture
    let normalMap: NormalMap?
    let projection: Projection
    let statistics: PixelStatistics
}

private struct CommandOptions {
    let sourceURL: URL
    let outputURL: URL
    let metadataURL: URL
    let elevationURL: URL?
    let elevationLabelURL: URL?
    let normalOutputURL: URL?
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func validateLabel(in source: Data, product: WACGlobalProduct) throws {
    let labelData = source.prefix(product.labelByteCount)
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
        "PRODUCT_ID": product.productID,
        "PRODUCT_VERSION_ID": "\"\(product.productVersion)\"",
        "RECORD_BYTES": String(product.labelByteCount),
        "LABEL_RECORDS": "1",
        "^IMAGE": "2",
        "MAP_PROJECTION_TYPE": "EQUIRECTANGULAR",
        "COORDINATE_SYSTEM_NAME": "PLANETOCENTRIC",
        "POSITIVE_LONGITUDE_DIRECTION": "EAST",
        "LINES": String(product.height),
        "LINE_SAMPLES": String(product.width),
        "SAMPLE_TYPE": "PC_REAL",
        "SAMPLE_BITS": "32"
    ]

    for (key, expectedValue) in requiredFields where fields[key] != expectedValue {
        throw GeneratorError.invalidLabel("\(key) = \(expectedValue)")
    }
}

private func labelFields(in data: Data) throws -> [String: String] {
    guard let label = String(data: data, encoding: .ascii) else {
        throw GeneratorError.invalidElevationLabel("ASCII encoding")
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
    return fields
}

private func validateElevation(source: Data, label: Data) throws {
    guard source.count == LOLALDEM16.sourceByteCount else {
        throw GeneratorError.invalidElevationByteCount(actual: source.count)
    }
    let sourceHash = sha256Hex(source)
    guard sourceHash == LOLALDEM16.sourceSHA256 else {
        throw GeneratorError.invalidElevationHash(actual: sourceHash)
    }
    guard label.count == LOLALDEM16.labelByteCount else {
        throw GeneratorError.invalidElevationLabelByteCount(actual: label.count)
    }
    let labelHash = sha256Hex(label)
    guard labelHash == LOLALDEM16.labelSHA256 else {
        throw GeneratorError.invalidElevationLabelHash(actual: labelHash)
    }

    let fields = try labelFields(in: label)
    let requiredFields = [
        "PRODUCT_ID": "\"\(LOLALDEM16.productID)\"",
        "PRODUCT_VERSION_ID": "\"\(LOLALDEM16.productVersion)\"",
        "DATA_SET_ID": "\"\(LOLALDEM16.dataSetID)\"",
        "RECORD_BYTES": String(LOLALDEM16.width * MemoryLayout<Int16>.size),
        "FILE_RECORDS": String(LOLALDEM16.height),
        "^IMAGE": "\"LDEM_16.IMG\"",
        "LINES": String(LOLALDEM16.height),
        "LINE_SAMPLES": String(LOLALDEM16.width),
        "SAMPLE_TYPE": "LSB_INTEGER",
        "SAMPLE_BITS": "16",
        "SCALING_FACTOR": "0.5",
        "MAP_PROJECTION_TYPE": "\"SIMPLE CYLINDRICAL\"",
        "COORDINATE_SYSTEM_NAME": "\"MEAN EARTH/POLAR AXIS OF DE421\"",
        "POSITIVE_LONGITUDE_DIRECTION": "\"EAST\"",
        "MAP_RESOLUTION": "16 <pix/deg>"
    ]
    for (key, expectedValue) in requiredFields where fields[key] != expectedValue {
        throw GeneratorError.invalidElevationLabel("\(key) = \(expectedValue)")
    }
}

private func parseCommandLine() throws -> CommandOptions {
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count >= 2 else { throw GeneratorError.usage }
    let sourceURL = URL(fileURLWithPath: arguments.removeFirst())
    let outputURL = URL(fileURLWithPath: arguments.removeFirst())

    var metadataURL: URL?
    if let first = arguments.first, !first.hasPrefix("--") {
        metadataURL = URL(fileURLWithPath: arguments.removeFirst())
    }
    var elevationURL: URL?
    var elevationLabelURL: URL?
    var normalOutputURL: URL?
    while !arguments.isEmpty {
        let option = arguments.removeFirst()
        guard let value = arguments.first else { throw GeneratorError.usage }
        arguments.removeFirst()
        switch option {
        case "--elevation":
            elevationURL = URL(fileURLWithPath: value)
        case "--elevation-label":
            elevationLabelURL = URL(fileURLWithPath: value)
        case "--normal-output":
            normalOutputURL = URL(fileURLWithPath: value)
        default:
            throw GeneratorError.usage
        }
    }
    let elevationOptionCount = [elevationURL, elevationLabelURL, normalOutputURL]
        .compactMap { $0 }
        .count
    guard elevationOptionCount == 0 || elevationOptionCount == 3 else {
        throw GeneratorError.incompleteElevationOptions
    }
    return CommandOptions(
        sourceURL: sourceURL,
        outputURL: outputURL,
        metadataURL: metadataURL
            ?? outputURL.deletingPathExtension().appendingPathExtension("json"),
        elevationURL: elevationURL,
        elevationLabelURL: elevationLabelURL,
        normalOutputURL: normalOutputURL
    )
}

private func linearReflectanceToSRGB8(_ reflectance: Float) -> UInt8 {
    let clamped = min(
        max(Double(reflectance), WACGlobalTransfer.minimumLinearReflectance),
        WACGlobalTransfer.maximumLinearReflectance
    )
    let srgb = clamped <= 0.003_130_8
        ? clamped * 12.92
        : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    return UInt8((min(max(srgb, 0), 1) * 255).rounded())
}

private func decodePixels(
    _ source: Data,
    product: WACGlobalProduct
) -> ([UInt8], PixelStatistics) {
    let pixelCount = product.width * product.height
    var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
    var validCount = 0
    var invalidCount = 0
    var minimum = Double.greatestFiniteMagnitude
    var maximum = -Double.greatestFiniteMagnitude
    var sum = 0.0

    source.withUnsafeBytes { rawBytes in
        for pixelIndex in 0..<pixelCount {
            let sourceOffset = product.labelByteCount
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
                reflectance = Float(WACGlobalTransfer.minimumLinearReflectance)
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

private func writePNG(
    pixels: [UInt8],
    width: Int,
    height: Int,
    colorSpace: CGColorSpace,
    to outputURL: URL
) throws {
    let bytesPerRow = width * 4
    let pixelData = Data(pixels)
    guard let provider = CGDataProvider(data: pixelData as CFData),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
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

/// Encodes a Moon-fixed, Mean Earth/Polar-axis normal at each LDEM post.
/// The reference sphere is deliberately absent from the finite differences:
/// only height above the pinned 1,737,400 m datum perturbs the radial normal.
/// That detrending prevents absolute lunar radius from leaking into the map's
/// color channels, which is the defect in the legacy `moon.usdz` normal map.
private func makeMENormalMap(from elevationSource: Data) -> [UInt8] {
    let width = LOLALDEM16.width
    let height = LOLALDEM16.height
    let pixelCount = width * height
    var heights = [Float](repeating: 0, count: pixelCount)

    elevationSource.withUnsafeBytes { rawBytes in
        for row in 0..<height {
            for outputColumn in 0..<width {
                // LDEM_16 is published as 0...360 degrees east. The runtime
                // map is -180...+180, so rotate the samples by exactly 180
                // degrees while retaining the same ME longitude direction.
                let sourceColumn = (outputColumn + width / 2) % width
                let sourceIndex = row * width + sourceColumn
                let digitalNumber = rawBytes.loadUnaligned(
                    fromByteOffset: sourceIndex * MemoryLayout<Int16>.size,
                    as: Int16.self
                ).littleEndian
                heights[row * width + outputColumn] = Float(digitalNumber)
                    * Float(LOLALDEM16.scalingFactorMeters)
            }
        }
    }

    let radiansPerPost = Double.pi / (180 * LOLALDEM16.pixelsPerDegree)
    let northSpacingMeters = LOLALDEM16.datumOffsetMeters * radiansPerPost
    let longitudes: [(cosine: Double, sine: Double)] = (0..<width).map { column in
        let longitude = (-180
            + (Double(column) + 0.5) / LOLALDEM16.pixelsPerDegree) * Double.pi / 180
        return (cos(longitude), sin(longitude))
    }
    var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
    for row in 0..<height {
        let latitude = (90
            - (Double(row) + 0.5) / LOLALDEM16.pixelsPerDegree) * Double.pi / 180
        let cosLatitude = cos(latitude)
        let sinLatitude = sin(latitude)
        let eastSpacingMeters = max(
            LOLALDEM16.datumOffsetMeters * radiansPerPost * abs(cosLatitude),
            1
        )
        // Every longitude converges at the poles, while the cylindrical LDEM
        // still stores 5,760 separately quantized samples there. A direct
        // east derivative would divide that quantization by centimeters to
        // meters and create a false pinched cap. Taper only the relief
        // perturbation over the final five degrees; the ME radial normal stays
        // exact and the source becomes fully authoritative outside the map's
        // coordinate singularity.
        let angularDistanceFromPole = Double.pi / 2 - abs(latitude)
        let polarReliabilityInput = min(max(
            (angularDistanceFromPole - 0.5 * Double.pi / 180)
                / (4.5 * Double.pi / 180),
            0
        ), 1)
        let polarReliability = polarReliabilityInput * polarReliabilityInput
            * (3 - 2 * polarReliabilityInput)
        let northRow = max(row - 1, 0)
        let southRow = min(row + 1, height - 1)
        let northDenominator = Double(southRow - northRow) * northSpacingMeters

        for column in 0..<width {
            let westColumn = (column - 1 + width) % width
            let eastColumn = (column + 1) % width
            let centerIndex = row * width + column
            let eastSlope = Double(
                heights[row * width + eastColumn] - heights[row * width + westColumn]
            ) / (2 * eastSpacingMeters)
            let northSlope = Double(
                heights[northRow * width + column] - heights[southRow * width + column]
            ) / northDenominator

            let longitude = longitudes[column]
            let radial = SIMD3<Double>(
                cosLatitude * longitude.cosine,
                cosLatitude * longitude.sine,
                sinLatitude
            )
            let east = SIMD3<Double>(-longitude.sine, longitude.cosine, 0)
            let north = SIMD3<Double>(
                -sinLatitude * longitude.cosine,
                -sinLatitude * longitude.sine,
                cosLatitude
            )
            let normal = simd_normalize(
                radial - polarReliability * (eastSlope * east + northSlope * north)
            )
            let outputOffset = centerIndex * 4
            pixels[outputOffset] = encodeNormalComponent(normal.x)
            pixels[outputOffset + 1] = encodeNormalComponent(normal.y)
            pixels[outputOffset + 2] = encodeNormalComponent(normal.z)
            pixels[outputOffset + 3] = 255
        }
    }
    return pixels
}

private func encodeNormalComponent(_ value: Double) -> UInt8 {
    UInt8((min(max(value * 0.5 + 0.5, 0), 1) * 255).rounded())
}

private func run() throws {
    let options = try parseCommandLine()

    let source = try Data(contentsOf: options.sourceURL, options: .mappedIfSafe)
    guard let product = WACGlobalProducts.product(sourceByteCount: source.count) else {
        throw GeneratorError.invalidSourceByteCount(actual: source.count)
    }
    let sourceHash = sha256Hex(source)
    guard sourceHash == product.sourceSHA256 else {
        throw GeneratorError.invalidSourceHash(actual: sourceHash)
    }
    try validateLabel(in: source, product: product)

    let (pixels, statistics) = decodePixels(source, product: product)
    try writePNG(
        pixels: pixels,
        width: product.width,
        height: product.height,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        to: options.outputURL
    )
    let textureData = try Data(contentsOf: options.outputURL, options: .mappedIfSafe)
    let textureHash = sha256Hex(textureData)
    var elevationMetadata: OutputMetadata.Source?
    var normalMetadata: OutputMetadata.NormalMap?
    if let elevationURL = options.elevationURL,
       let elevationLabelURL = options.elevationLabelURL,
       let normalOutputURL = options.normalOutputURL {
        let elevationSource = try Data(contentsOf: elevationURL, options: .mappedIfSafe)
        let elevationLabel = try Data(contentsOf: elevationLabelURL, options: .mappedIfSafe)
        try validateElevation(source: elevationSource, label: elevationLabel)
        let normalPixels = makeMENormalMap(from: elevationSource)
        try writePNG(
            pixels: normalPixels,
            width: LOLALDEM16.width,
            height: LOLALDEM16.height,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            to: normalOutputURL
        )
        let normalHash = sha256Hex(
            try Data(contentsOf: normalOutputURL, options: .mappedIfSafe)
        )
        elevationMetadata = .init(
            productID: LOLALDEM16.productID,
            productVersion: LOLALDEM16.productVersion,
            url: LOLALDEM16.sourceURL,
            byteCount: LOLALDEM16.sourceByteCount,
            sha256: LOLALDEM16.sourceSHA256,
            sampleType: "LSB_INTEGER meters above the 1,737,400 m reference sphere",
            sampleBits: 16
        )
        normalMetadata = .init(
            file: normalOutputURL.lastPathComponent,
            width: LOLALDEM16.width,
            height: LOLALDEM16.height,
            format: "RGBA8 PNG",
            coordinateFrame: "IAU_ME",
            encoding: "linear RGB maps normalized ME x/y/z from [-1,1] to [0,1]",
            sha256: normalHash,
            sourceID: LOLALDEM16.sourceID,
            detail: "Detrended radial normal plus central-difference LDEM relief. Used only to perturb the ephemeris terminator multiplier; never as a second PBR lighting pass."
        )
        print("Normal-map SHA-256: \(normalHash)")
    }
    let generatorHash = try sha256Hex(
        Data(contentsOf: URL(fileURLWithPath: #filePath), options: .mappedIfSafe)
    )

    let metadata = OutputMetadata(
        schemaVersion: normalMetadata == nil ? 1 : 2,
        generatorVersion: normalMetadata == nil
            ? "wac-global-morphologic-v1"
            : "wac-global-morphologic-lola-normal-v2",
        generatorSHA256: generatorHash,
        source: .init(
            productID: product.productID,
            productVersion: product.productVersion,
            url: product.sourceURL,
            byteCount: product.sourceByteCount,
            sha256: product.sourceSHA256,
            sampleType: "PC_REAL",
            sampleBits: 32
        ),
        elevationSource: elevationMetadata,
        texture: .init(
            file: options.outputURL.lastPathComponent,
            width: product.width,
            height: product.height,
            format: "RGBA8 PNG",
            colorSpace: "sRGB encoding of linear reflectance proxy",
            sha256: textureHash,
            minimumLinearReflectance: WACGlobalTransfer.minimumLinearReflectance,
            maximumLinearReflectance: WACGlobalTransfer.maximumLinearReflectance
        ),
        normalMap: normalMetadata,
        projection: .init(
            mapProjectionType: "EQUIRECTANGULAR",
            latitudeType: "PLANETOCENTRIC",
            positiveLongitudeDirection: "EAST",
            pixelsPerDegree: product.pixelsPerDegree,
            metersPerPixel: product.metersPerPixel,
            minimumLatitudeDegrees: product.minimumLatitudeDegrees,
            maximumLatitudeDegrees: product.maximumLatitudeDegrees,
            westernmostLongitudeDegrees: product.westernmostLongitudeDegrees,
            easternmostLongitudeDegrees: product.easternmostLongitudeDegrees,
            lunarRadiusMeters: product.lunarRadiusMeters
        ),
        statistics: statistics
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var metadataData = try encoder.encode(metadata)
    metadataData.append(0x0A)
    try metadataData.write(to: options.metadataURL, options: .atomic)

    print("Generated \(options.outputURL.path)")
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
