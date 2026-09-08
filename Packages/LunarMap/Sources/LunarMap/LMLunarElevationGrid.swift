import CryptoKit
import Foundation

/// Decodes the exact fixed-record products in the source catalog. Samples stay
/// in their source datum and registration until the mesh/contact consumer asks
/// for an elevation; no procedural detail or presentation anchor enters here.
public struct LMLunarElevationGrid: Sendable {
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
    public let spacingMeters: Double
    let residualCapFraction: Double
    let width: Int
    let height: Int
    let pixelsPerDegree: Double
    let northEdgeDegrees: Double
    let westEdgeDegrees: Double
    let wrapsLongitude: Bool
    let format: Format
    private let firstSourceRow: Double
    private let data: Data
    private var northPoleMean: Double?
    private var southPoleMean: Double?

    init(data: Data, source: LMTerrainManifest.Source) throws {
        sourceID = source.id
        spacingMeters = source.postSpacingMeters ?? 0
        residualCapFraction = source.residualCapRatio ?? 0
        pixelsPerDegree = source.mapResolutionPixelsPerDegree ?? 0
        northEdgeDegrees = source.coverage.maximumLatitudeDegrees
        westEdgeDegrees = source.coverage.westernmostLongitudeDegrees
        firstSourceRow = Double(source.sourceRowStart ?? 0)
        switch source.productId {
        case "LDEM_16":
            guard source.productVersion == "V3.1", pixelsPerDegree == 16,
                  northEdgeDegrees == 90, westEdgeDegrees == 0 else { throw GridError.invalidDimensions }
            format = .lolaInt16HalfMeters
            width = 5_760
            height = 2_880
            wrapsLongitude = true
        case "LDEM_128":
            guard source.productVersion == "V3.0", pixelsPerDegree == 128,
                  source.sourceRowBytes == 92_160,
                  let first = source.sourceRowStart, let last = source.sourceRowEnd,
                  first >= 0, last >= first, last < 23_040,
                  northEdgeDegrees == 90 - Double(first) / 128, westEdgeDegrees == 0 else {
                throw GridError.invalidDimensions
            }
            format = .lolaInt16HalfMeters
            width = 46_080
            height = last - first + 1
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
        northPoleMean = nil
        southPoleMean = nil
        // Compute polar convergence once, not once per vertex in a fine mesh.
        if wrapsLongitude {
            if northEdgeDegrees == 90 {
                northPoleMean = (0..<width).reduce(0.0) { $0 + (elevation(row: 0, column: $1) ?? 0) } / Double(width)
            }
            if northEdgeDegrees - Double(height) / pixelsPerDegree == -90 {
                southPoleMean = (0..<width).reduce(0.0) { $0 + (elevation(row: height - 1, column: $1) ?? 0) } / Double(width)
            }
        }
    }

    /// Source-native post coordinates. The seam repeats a column, never a
    /// sample; callers can use column == width to address the wrapped neighbor.
    func coordinate(row: Int, column: Int) -> LMSelenographicCoordinate {
        .init(latitudeDegrees: northEdgeDegrees - (Double(row) + 0.5) / pixelsPerDegree,
              longitudeDegrees: westEdgeDegrees + (Double(column) + 0.5) / pixelsPerDegree)
    }

    func fractionalPost(at coordinate: LMSelenographicCoordinate) -> SIMD2<Double> {
        var longitude = coordinate.longitudeDegrees
        if longitude < westEdgeDegrees { longitude += 360 }
        var column = (longitude - westEdgeDegrees) * pixelsPerDegree - 0.5
        if wrapsLongitude {
            column = column.truncatingRemainder(dividingBy: Double(width))
            if column < 0 { column += Double(width) }
        }
        return SIMD2(column, fractionalRow(latitude: coordinate.latitudeDegrees))
    }

    private func fractionalRow(latitude: Double) -> Double {
        // Canonical source arithmetic makes the fractional part byte-identical
        // in overlapping strips, independent of each strip's local row index.
        let sourceNorth = northEdgeDegrees + firstSourceRow / pixelsPerDegree
        return (sourceNorth - latitude) * pixelsPerDegree - 0.5 - firstSourceRow
    }

    var northernCoverageLatitude: Double { northPoleMean == nil ? northernPostLatitude : 90 }
    var southernCoverageLatitude: Double { southPoleMean == nil ? southernPostLatitude : -90 }
    var northernPostLatitude: Double { northEdgeDegrees - 0.5 / pixelsPerDegree }
    var southernPostLatitude: Double { northEdgeDegrees - (Double(height) - 0.5) / pixelsPerDegree }
    var westernPostLongitude: Double { westEdgeDegrees + 0.5 / pixelsPerDegree }
    var easternPostLongitude: Double { westEdgeDegrees + (Double(width) - 0.5) / pixelsPerDegree }

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
        var y = fractionalRow(latitude: coordinate.latitudeDegrees)
        if wrapsLongitude {
            x = x.truncatingRemainder(dividingBy: Double(width))
            if x < 0 { x += Double(width) }
            guard (y >= 0 || northPoleMean != nil),
                  (y <= Double(height - 1) || southPoleMean != nil) else { return nil }
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
                guard let mean = coordinate.latitudeDegrees > 0 ? northPoleMean : southPoleMean else { return nil }
                if cap >= 1 { return mean }
                return value + (mean - value) * cap
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
