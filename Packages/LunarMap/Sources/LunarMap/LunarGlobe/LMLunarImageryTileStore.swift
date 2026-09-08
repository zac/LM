import Foundation

/// Imagery has separate cache ownership from elevation. Only complete, verified
/// source slabs and exact offline tile bytes can become visible textures.
actor LMLunarImageryTileStore {
    let pyramid: LMLunarImageryPyramid
    private let slabs: LMLunarElevationStore
    private let directory: URL
    private let capacityBytes: Int
    private var inFlight = [String: Task<Data, Error>]()

    init(pyramid: LMLunarImageryPyramid, directory: URL, capacityBytes: Int = 32 * 1024 * 1024,
         fetch: @escaping LMLunarElevationStore.Fetch = LMLunarElevationStore.fetchPDS) throws {
        self.pyramid = pyramid
        self.directory = directory.appendingPathComponent("tiles")
        self.capacityBytes = capacityBytes
        self.slabs = try LMLunarElevationStore(directory: directory.appendingPathComponent("slabs"), fetch: fetch)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func pixels(for tile: LMLunarImageryPyramid.Tile, offline: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        guard pyramid.tiles.contains(tile) else { throw CocoaError(.fileReadCorruptFile) }
        let url = directory.appendingPathComponent(tile.sha256 + ".r8")
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           data.count == pyramid.tilePixelWidth * pyramid.tilePixelWidth,
           LMLunarImageryPyramid.digest(data) == tile.sha256 {
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return data
        }
        // Cached source slabs may reconstruct an evicted derived tile offline.
        if let pending = inFlight[tile.id] { return try await pending.value }
        let pyramid = self.pyramid, slabs = self.slabs
        let task = Task<Data, Error> {
            let selected = pyramid.slabs(for: tile)
            let sources = selected.map { Self.source($0, pyramid: pyramid) }
            let results = try await slabs.data(for: sources, offline: offline)
            try Task.checkCancellation()
            var rows = Data()
            rows.reserveCapacity(selected.reduce(0) { $0 + $1.rowCount * pyramid.sourceWidth * 4 })
            for result in results { rows.append(try result.get()) }
            let pixels = try LMLunarTerrainTiming.measure("globe-tile-cpu") {
                try pyramid.pixels(for: tile, sourceRows: rows, firstRow: selected[0].rowStart)
            }
            guard LMLunarImageryPyramid.digest(pixels) == tile.sha256 else {
                throw LMLunarElevationStore.StoreError.digestMismatch
            }
            try Task.checkCancellation()
            try pixels.write(to: url, options: .atomic)
            try self.trim()
            return pixels
        }
        inFlight[tile.id] = task
        defer { inFlight.removeValue(forKey: tile.id) }
        return try await withTaskCancellationHandler(operation: { try await task.value },
            onCancel: { task.cancel() })
    }

    private func trim() throws {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys)).filter { $0.pathExtension == "r8" }
        var entries = try files.map { url -> (URL, Int, Date) in
            let values = try url.resourceValues(forKeys: keys)
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var bytes = entries.reduce(0) { $0 + $1.1 }
        while bytes > capacityBytes, !entries.isEmpty {
            let entry = entries.removeFirst()
            try FileManager.default.removeItem(at: entry.0)
            bytes -= entry.1
        }
    }

    nonisolated static func source(_ slab: LMLunarImageryPyramid.Slab,
                                   pyramid: LMLunarImageryPyramid) -> LMTerrainManifest.Source {
        let rowBytes = pyramid.sourceWidth * 4
        return .init(id: "wac64-imagery-rows-\(slab.rowStart)", role: "globe-imagery-slab",
            coverage: .init(minimumLatitudeDegrees: 90 - Double(slab.rowStart + slab.rowCount) / 64,
                maximumLatitudeDegrees: 90 - Double(slab.rowStart) / 64,
                westernmostLongitudeDegrees: -180, easternmostLongitudeDegrees: 180),
            postSpacingMeters: nil, residualCapRatio: nil, url: pyramid.sourceURL, sha256: slab.sha256,
            bytes: slab.rowCount * rowBytes, sourceBytes: pyramid.sourceBytes,
            byteRangeStart: pyramid.sourceOffsetBytes + slab.rowStart * rowBytes,
            byteRangeEnd: pyramid.sourceOffsetBytes + (slab.rowStart + slab.rowCount) * rowBytes - 1,
            sourceMD5: nil, bundledFile: nil, bundledLabelFile: nil,
            sourceRowStart: slab.rowStart, sourceRowEnd: slab.rowStart + slab.rowCount - 1,
            sourceRowBytes: rowBytes, mapResolutionPixelsPerDegree: 64,
            productId: "WAC_GLOBAL_E000N0000_064P", productVersion: "1",
            labelURL: pyramid.sourceURL, labelSHA256: pyramid.sourceLabelSHA256,
            labelBytes: pyramid.sourceOffsetBytes,
            detail: "Pinned Float32 source rows used only to reconstruct offline-hashed imagery tiles.")
    }
}
