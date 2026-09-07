import Foundation
import CryptoKit

/// Offline-pinned WAC imagery. Geometry and terrain sampling never use these pixels.
struct LMLunarImageryPyramid: Codable, Sendable {
    struct Asset: Codable, Sendable {
        let file: String
        let sha256: String
        let bytes: Int
        let width: Int
        let height: Int
    }
    struct Slab: Codable, Sendable {
        let rowStart: Int
        let rowCount: Int
        let sha256: String
    }
    struct Tile: Codable, Hashable, Sendable {
        let ppd: Int
        let row: Int
        let column: Int
        let sha256: String
        var id: String { "\(ppd)-\(row)-\(column)" }
    }
    let version: String
    let generatorSHA256: String
    let sourceURL: String
    let sourceSHA256: String
    let sourceBytes: Int
    let sourceWidth: Int
    let sourceHeight: Int
    let sourceOffsetBytes: Int
    let sourceLabelSHA256: String
    let tileSize: Int
    let gutter: Int
    let base: Asset
    let slabs: [Slab]
    let tiles: [Tile]

    static let currentVersion = "wac64-r8-box-pyramid-v1"
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Exactly the existing morphologic generator's transfer, including invalid pixels.
    static func encodeReflectance(_ value: Float) -> UInt8 {
        let valid = value.isFinite && value >= 0 && value < 1 ? value : 0.015
        let linear = min(max(Double(valid), 0.015), 0.45)
        let srgb = linear <= 0.003_130_8 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
        return UInt8((min(max(srgb, 0), 1) * 255).rounded())
    }

    var tilePixelWidth: Int { tileSize + 2 * gutter }

    func sourceRows(for tile: Tile) -> ClosedRange<Int> {
        let factor = 64 / tile.ppd
        let first = max(0, (tile.row * tileSize - gutter) * factor)
        let last = min(sourceHeight - 1, ((tile.row + 1) * tileSize + gutter) * factor - 1)
        return first...last
    }

    func slabs(for tile: Tile) -> [Slab] {
        let rows = sourceRows(for: tile)
        return slabs.filter { $0.rowStart <= rows.upperBound && $0.rowStart + $0.rowCount > rows.lowerBound }
    }

    /// Reconstruct the exact offline tile from verified contiguous Float32 rows.
    /// Longitude gutters wrap; latitude gutters clamp. 32 ppd is an integer
    /// box average of encoded 64 ppd samples, rounded identically on every host.
    func pixels(for tile: Tile, sourceRows data: Data, firstRow: Int) throws -> Data {
        guard [32, 64].contains(tile.ppd), tileSize == 360, gutter == 2,
              sourceWidth == 23040, sourceHeight == 11520,
              data.count % (sourceWidth * 4) == 0 else { throw CocoaError(.fileReadCorruptFile) }
        let rows = sourceRows(for: tile)
        guard firstRow <= rows.lowerBound,
              firstRow + data.count / (sourceWidth * 4) > rows.upperBound else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let factor = 64 / tile.ppd, side = tilePixelWidth
        var result = Data(count: side * side)
        try data.withUnsafeBytes { source in
            try result.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
                for y in 0..<side {
                    try Task.checkCancellation()
                    let py = tile.row * tileSize + y - gutter
                    for x in 0..<side {
                        let px = tile.column * tileSize + x - gutter
                        var sum = 0
                        for dy in 0..<factor {
                            let row = min(max(py * factor + dy, 0), sourceHeight - 1) - firstRow
                            for dx in 0..<factor {
                                let column = ((px * factor + dx) % sourceWidth + sourceWidth) % sourceWidth
                                let bits = source.loadUnaligned(fromByteOffset: (row * sourceWidth + column) * 4, as: UInt32.self)
                                sum += Int(Self.encodeReflectance(Float(bitPattern: UInt32(littleEndian: bits))))
                            }
                        }
                        let count = factor * factor
                        output[y * side + x] = UInt8((sum + count / 2) / count)
                    }
                }
            }
        }
        return result
    }

    func validate() throws {
        guard version == Self.currentVersion, sourceWidth == 23040, sourceHeight == 11520,
              sourceOffsetBytes == sourceWidth * 4, sourceBytes == sourceOffsetBytes + sourceWidth * sourceHeight * 4,
              tileSize == 360, gutter == 2, base.width == 5760, base.height == 2880,
              Set(tiles.map(\.id)).count == tiles.count, tiles.count == 2560 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var row = 0
        for slab in slabs {
            guard slab.rowStart == row, slab.rowCount > 0, slab.rowCount <= 128 else { throw CocoaError(.fileReadCorruptFile) }
            row += slab.rowCount
        }
        guard row == sourceHeight else { throw CocoaError(.fileReadCorruptFile) }
        for tile in tiles {
            guard [32, 64].contains(tile.ppd), tile.row >= 0, tile.row < 180 * tile.ppd / tileSize,
                  tile.column >= 0, tile.column < 360 * tile.ppd / tileSize,
                  tile.sha256.count == 64 else { throw CocoaError(.fileReadCorruptFile) }
        }
    }
}
