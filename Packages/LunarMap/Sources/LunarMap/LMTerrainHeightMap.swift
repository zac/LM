import CoreGraphics
import Foundation
import ImageIO
import LMCore
import UniformTypeIdentifiers

/// A decoded 16-bit grayscale terrain height map. Counts are centimeters
/// above the tile's zero point, recorded in the terrain manifest.
struct LMTerrainHeightMap: Equatable {
    let width: Int
    let height: Int
    /// Row-major big-endian-decoded counts, top row first.
    let counts: [UInt16]

    func heightMeters(
        atPost row: Int,
        column: Int,
        zeroPointMeters: Double,
        centimetersPerCount: Int
    ) -> Double {
        zeroPointMeters
            + Double(counts[row * width + column]) * Double(centimetersPerCount) / 100.0
    }

    /// Decode a PNG grayscale 16-bit file without losing precision. The image
    /// is read in its native 16-bpc gray layout; anything else is rejected so
    /// a silently resampled decode can never masquerade as terrain data.
    static func load(contentsOf url: URL) throws -> LMTerrainHeightMap {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CocoaError(.fileReadUnknown)
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard image.bitsPerComponent == 16,
              image.bitsPerPixel == 16,
              image.isMask == false,
              image.colorSpace?.model == .monochrome else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "\(url.lastPathComponent) is not 16-bit grayscale"
            ])
        }
        guard let provider = image.dataProvider, let data = provider.data as Data? else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        guard data.count >= bytesPerRow * height else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var counts = [UInt16](repeating: 0, count: width * height)
        data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self)
            for row in 0..<height {
                let rowStart = row * bytesPerRow
                for column in 0..<width {
                    // ImageIO decodes 16-bit gray into native little-endian
                    // samples; verified against the generator's known span.
                    let offset = rowStart + column * 2
                    counts[row * width + column] =
                        UInt16(base[offset]) | UInt16(base[offset + 1]) << 8
                }
            }
        }
        return LMTerrainHeightMap(width: width, height: height, counts: counts)
    }
}
