import Foundation

/// Build with LMLunarImageryPyramid.swift. Emits canonical raw R8 tiles and a
/// manifest; runtime reconstruction uses that exact same transfer function.
@main
enum GenerateLunarImageryPyramid {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 5 else {
            fatalError("usage: generator <pinned WAC IMG> <GPUBase-P3.png> <shared Swift source> <fresh output>")
        }
        let source = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
        let sourceSHA = LMLunarImageryPyramid.digest(source)
        guard sourceSHA == "bc1feab6e86ae2cf47798a4f00cdf7f5e73030fcbc2223fba7fab59a5a2a34ec" else {
            fatalError("Pinned WAC source mismatch")
        }
        let base = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        guard LMLunarImageryPyramid.digest(base) == "840379f0f6cc9311e3674086579bce2a6cc8bd30d822cb1e63e3200e2bc2303e" else {
            fatalError("Pinned GPU color companion mismatch")
        }
        let shared = try Data(contentsOf: URL(fileURLWithPath: args[3]))
        let output = URL(fileURLWithPath: args[4], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Output must be fresh") }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let width = 23040, height = 11520, rowBytes = width * 4
        let sourceURL = "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/BDR/WAC_GLOBAL/WAC_GLOBAL_E000N0000_064P.IMG"
        let slabs = stride(from: 0, to: height, by: 128).map { row in
            LMLunarImageryPyramid.Slab(rowStart: row, rowCount: min(128, height - row),
                sha256: LMLunarImageryPyramid.digest(source.subdata(in: ((row + 1) * rowBytes)..<((min(row + 128, height) + 1) * rowBytes))))
        }
        func manifest(_ tiles: [LMLunarImageryPyramid.Tile]) -> LMLunarImageryPyramid {
            .init(version: LMLunarImageryPyramid.currentVersion,
                generatorSHA256: LMLunarImageryPyramid.digest(shared), sourceURL: sourceURL,
                sourceSHA256: sourceSHA, sourceBytes: source.count, sourceWidth: width, sourceHeight: height,
                sourceOffsetBytes: rowBytes, sourceLabelSHA256: LMLunarImageryPyramid.digest(source.prefix(rowBytes)),
                tileSize: 360, gutter: 2,
                base: .init(file: "WACGlobal64GPUBase-P3.pngdata", sha256: LMLunarImageryPyramid.digest(base),
                    bytes: base.count, width: 5760, height: 2880), slabs: slabs, tiles: tiles)
        }
        var tiles = [LMLunarImageryPyramid.Tile]()
        let layout = manifest([])
        for ppd in [32, 64] {
            for row in 0..<(180 * ppd / 360) {
                // Read only this tile band's rows once, including both gutters.
                let template = LMLunarImageryPyramid.Tile(ppd: ppd, row: row, column: 0, sha256: "")
                let range = layout.sourceRows(for: template)
                let data = source.subdata(in: ((range.lowerBound + 1) * rowBytes)..<((range.upperBound + 2) * rowBytes))
                for column in 0..<(360 * ppd / 360) {
                    let tile = LMLunarImageryPyramid.Tile(ppd: ppd, row: row, column: column, sha256: "")
                    let pixels = try layout.pixels(for: tile, sourceRows: data, firstRow: range.lowerBound)
                    let digest = LMLunarImageryPyramid.digest(pixels)
                    try pixels.write(to: output.appendingPathComponent(digest + ".r8"))
                    tiles.append(.init(ppd: ppd, row: row, column: column, sha256: digest))
                }
                print("ppd=\(ppd) row=\(row) tiles=\(tiles.count)")
            }
        }
        let result = manifest(tiles)
        try result.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(result).write(to: output.appendingPathComponent("LunarImageryPyramid.json"))
        print("Generated \(tiles.count) verified tiles")
    }
}
