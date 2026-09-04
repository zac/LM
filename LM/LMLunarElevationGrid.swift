import CryptoKit
import Foundation

/// Decodes the exact fixed-record products in the source catalog. Samples stay
/// in their source datum and registration until the mesh/contact consumer asks
/// for an elevation; no procedural detail or presentation anchor enters here.
struct LMLunarElevationGrid: Sendable {
    enum Format: Sendable {
        case lolaInt16HalfMeters
        case sldemFloat32Kilometers

        var bytesPerSample: Int {
            switch self {
            case .lolaInt16HalfMeters: 2
            case .sldemFloat32Kilometers: 4
            }
        }
    }

    enum GridError: Error, Equatable {
        case unsupportedProduct
        case invalidDimensions
        case digestMismatch
    }

    let sourceID: String
    let spacingMeters: Double
    let width: Int
    let height: Int
    let pixelsPerDegree: Double
    let northEdgeDegrees: Double
    let westEdgeDegrees: Double
    let wrapsLongitude: Bool
    let format: Format
    private let data: Data

    init(data: Data, source: LMTerrainManifest.Source) throws {
        sourceID = source.id
        spacingMeters = source.postSpacingMeters ?? 0
        pixelsPerDegree = source.mapResolutionPixelsPerDegree ?? 0
        northEdgeDegrees = source.coverage.maximumLatitudeDegrees
        westEdgeDegrees = source.coverage.westernmostLongitudeDegrees
        switch source.productId {
        case "LDEM_16":
            guard source.productVersion == "V3.1", pixelsPerDegree == 16,
                  northEdgeDegrees == 90, westEdgeDegrees == 0 else { throw GridError.invalidDimensions }
            format = .lolaInt16HalfMeters
            width = 5_760
            height = 2_880
            wrapsLongitude = true
        case "SLDEM2015_512_00N_30N_000_045_FLOAT":
            guard source.productVersion == "V2.0", pixelsPerDegree == 512,
                  source.sourceRowBytes == 92_160,
                  let first = source.sourceRowStart, let last = source.sourceRowEnd,
                  first >= 0, last >= first, last < 15_360 else { throw GridError.invalidDimensions }
            format = .sldemFloat32Kilometers
            width = 23_040
            height = last - first + 1
            wrapsLongitude = false
        default:
            throw GridError.unsupportedProduct
        }
        guard width > 1, height > 1, pixelsPerDegree > 0, spacingMeters > 0,
              data.count == width * height * format.bytesPerSample,
              data.count == source.bytes else { throw GridError.invalidDimensions }
        guard Self.digest(data) == source.sha256 else { throw GridError.digestMismatch }
        self.data = data
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Measured posts bypass interpolation exactly. Pixel registration uses a
    /// half-post offset; the manifest coverage records outer pixel edges.
    func elevation(at coordinate: LMSelenographicCoordinate) -> Double? {
        guard coordinate.latitudeDegrees.isFinite, coordinate.longitudeDegrees.isFinite,
              abs(coordinate.latitudeDegrees) <= 90 else { return nil }
        var longitude = coordinate.longitudeDegrees
        if longitude < westEdgeDegrees { longitude += 360 }
        var x = (longitude - westEdgeDegrees) * pixelsPerDegree - 0.5
        var y = (northEdgeDegrees - coordinate.latitudeDegrees) * pixelsPerDegree - 0.5
        if wrapsLongitude {
            x = x.truncatingRemainder(dividingBy: Double(width))
            if x < 0 { x += Double(width) }
            y = min(max(y, 0), Double(height - 1))
        } else {
            guard x >= 0, x <= Double(width - 1), y >= 0, y <= Double(height - 1) else { return nil }
        }
        let x0 = Int(x.rounded(.down))
        let y0 = Int(y.rounded(.down))
        let x1 = wrapsLongitude ? (x0 + 1) % width : min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = x - Double(x0)
        let ty = y - Double(y0)
        guard let nw = elevation(row: y0, column: x0),
              let ne = elevation(row: y0, column: x1),
              let sw = elevation(row: y1, column: x0),
              let se = elevation(row: y1, column: x1) else { return nil }
        let north = nw + (ne - nw) * tx
        let south = sw + (se - sw) * tx
        let value = north + (south - north) * ty
        // Converge the half-post polar caps onto one height per pole. The first
        // measured row remains untouched, and longitude is irrelevant at 90°.
        if wrapsLongitude {
            let cap = (abs(coordinate.latitudeDegrees) - (90 - 0.5 / pixelsPerDegree))
                * pixelsPerDegree * 2
            if cap > 0 {
                let row = coordinate.latitudeDegrees > 0 ? 0 : height - 1
                var sum = 0.0
                for column in 0..<width {
                    guard let sample = elevation(row: row, column: column) else { return nil }
                    sum += sample
                }
                return value + (sum / Double(width) - value) * min(cap, 1)
            }
        }
        return value
    }

    func elevation(row: Int, column: Int) -> Double? {
        guard (0..<height).contains(row), (0..<width).contains(column) else { return nil }
        let offset = (row * width + column) * format.bytesPerSample
        let value: Double = data.withUnsafeBytes { bytes in
            switch format {
            case .lolaInt16HalfMeters:
                Double(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self))) * 0.5
            case .sldemFloat32Kilometers:
                Double(Float(bitPattern: UInt32(littleEndian:
                    bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))) * 1_000
            }
        }
        return value.isFinite ? value : nil
    }
}
