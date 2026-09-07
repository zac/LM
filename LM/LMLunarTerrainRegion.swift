import Foundation

/// A region is resolved once into immutable source ownership. It is shared by
/// rendering and contact; a network completion cannot silently alter a landing.
struct LMLunarTerrainRegion: Sendable {
    let terrain: LMLunarResolvedTerrain
    let frame: LMSelenographicLocalFrame
    let albedo: LMMeasuredAlbedoField
    let sourceIDs: [String]
    let unavailableSourceIDs: [String]
    let measuredFloorMeters: Double

    /// The bundled NAC pack retains its original planar evaluator and bytes.
    /// Select it by its declared footprint, leaving a full morph collar inside
    /// the measured tile. Future packs can provide the same selection contract.
    static func bundledSitePosition(at coordinate: LMSelenographicCoordinate,
                                    manifest: LMTerrainManifest) -> LMSiteENUPosition? {
        guard let tile = manifest.tile(id: "near-field"),
              tile.sourceIDs?.contains(where: { id in
                  manifest.sources.contains { $0.id == id && $0.productId.hasPrefix("NAC_DTM_") }
              }) == true else { return nil }
        let point = manifest.selenographicCoordinateSystem.sitePosition(for: coordinate,
                                                                          relativeTo: manifest.landingOriginCoordinate)
        let half = tile.extentMeters / 2 - 128
        return abs(point.northMeters) <= half && abs(point.eastMeters) <= half ? point : nil
    }

    static func sources(at coordinate: LMSelenographicCoordinate, manifest: LMTerrainManifest,
                        catalog: LMLunarElevationCatalog) -> [LMTerrainManifest.Source] {
        catalog.sources(around: coordinate, radiusMeters: 25_000) + manifest.sources.filter {
            ($0.productId.hasPrefix("WAC_EMP_") || $0.productId == "SLDEM2015_512_00N_30N_000_045_FLOAT")
                && $0.coverage.contains(latitudeDegrees: coordinate.latitudeDegrees, longitudeDegrees: coordinate.longitudeDegrees)
        }
    }

    static func load(at coordinate: LMSelenographicCoordinate, store: LMLunarElevationStore,
                     offline: Bool = false, bundle: Bundle = .main) async throws -> Self {
        let interval = LMLunarTerrainTiming.begin("source-resolution")
        defer { LMLunarTerrainTiming.end(interval) }
        let manifest = try LMTerrainManifest.load(bundle: bundle)
        let catalog = try LMLunarElevationCatalog.load(bundle: bundle)
        guard let source = manifest.sources.first(where: { $0.productId == "LDEM_16" }),
              let url = bundle.url(forResource: source.bundledFile, withExtension: nil) else {
            throw LMLunarElevationCatalog.CatalogError.missingResource
        }
        let base = try LMLunarTerrainTiming.measure("base-verify-decode") {
            try LMLunarElevationGrid(data: Data(contentsOf: url, options: .mappedIfSafe), source: source)
        }
        var grids = [LMLunarElevationGrid]()
        var reflectance = [LMLunarReflectanceField.Slab]()
        var unavailable = [String]()
        var identifiers = [source.id]
        let requestedSources = sources(at: coordinate, manifest: manifest, catalog: catalog)
        let fetchInterval = LMLunarTerrainTiming.begin("source-batch")
        let results: [Result<Data, Error>]
        do {
            defer { LMLunarTerrainTiming.end(fetchInterval) }
            results = try await store.data(for: requestedSources, offline: offline)
        }
        for (source, result) in zip(requestedSources, results) {
            try Task.checkCancellation()
            do {
                let data = try result.get()
                if source.productId.hasPrefix("WAC_EMP_") {
                    reflectance.append(try .init(data: data, source: source))
                } else {
                    grids.append(try LMLunarTerrainTiming.measure("strip-verify-decode") {
                        try .init(data: data, source: source)
                    })
                }
                identifiers.append(source.id)
            } catch is CancellationError { throw CancellationError() }
            catch { unavailable.append(source.id) }
        }
        let terrain = LMLunarResolvedTerrain(base: base, refinements: grids.sorted { $0.pixelsPerDegree < $1.pixelsPerDegree })
        guard let focus = terrain.sample(at: coordinate, spacingMeters: .greatestFiniteMagnitude) else {
            throw LMLunarElevationGrid.GridError.invalidDimensions
        }
        let frame = LMSelenographicCoordinateSystem().localFrame(at: .init(latitudeDegrees: coordinate.latitudeDegrees,
                                                                           longitudeDegrees: coordinate.longitudeDegrees,
                                                                           heightMeters: focus.measuredMeters))
        let albedo = LMMeasuredAlbedoField(width: 0, height: 0, halfExtentMeters: 0, luminance: [],
                                          lunarField: .init(frame: frame, slabs: reflectance.sorted { $0.ppd < $1.ppd }))
        return .init(terrain: terrain, frame: frame, albedo: albedo, sourceIDs: identifiers,
                     unavailableSourceIDs: unavailable, measuredFloorMeters: focus.sourceSpacingMeters)
    }
}

/// Only the photometrically normalized 643 nm product is accepted here.
/// The global morphologic mosaic belongs to the unlit globe, never this field.
struct LMLunarReflectanceField: Sendable {
    struct Slab: Sendable {
        let data: Data
        let source: LMTerrainManifest.Source
        let width: Int
        let height: Int
        let ppd: Double

        init(data: Data, source: LMTerrainManifest.Source) throws {
            guard source.productId.hasPrefix("WAC_EMP_643NM_"), source.productVersion == "V2.0",
                  let rowBytes = source.sourceRowBytes, rowBytes > 0, rowBytes % 4 == 0,
                  let first = source.sourceRowStart, let last = source.sourceRowEnd, last >= first,
                  let ppd = source.mapResolutionPixelsPerDegree, ppd > 0,
                  data.count == (last - first + 1) * rowBytes, data.count == source.bytes,
                  LMLunarElevationGrid.digest(data) == source.sha256 else {
                throw LMLunarElevationGrid.GridError.invalidDimensions
            }
            self.data = data; self.source = source; self.width = rowBytes / 4
            self.height = last - first + 1; self.ppd = ppd
        }

        func sample(at coordinate: LMSelenographicCoordinate) -> (linear: Double, weight: Double)? {
            var longitude = coordinate.longitudeDegrees
            if longitude < 0 { longitude += 360 }
            let x = (longitude - source.coverage.westernmostLongitudeDegrees) * ppd - 0.5
            let y = (source.coverage.maximumLatitudeDegrees - coordinate.latitudeDegrees) * ppd - 0.5
            guard x >= 0, y >= 0, x <= Double(width - 1), y <= Double(height - 1) else { return nil }
            let x0 = Int(x), y0 = Int(y), x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
            func value(_ x: Int, _ y: Int) -> Double? {
                let v = data.withUnsafeBytes { bytes in
                    Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: (y * width + x) * 4, as: UInt32.self)))
                }
                return v.isFinite && v > 0 && v < 1 ? Double(v) : nil
            }
            guard let nw = value(x0, y0), let ne = value(x1, y0), let sw = value(x0, y1), let se = value(x1, y1) else { return nil }
            let tx = x - Double(x0), ty = y - Double(y0)
            let north = nw + (ne - nw) * tx, south = sw + (se - sw) * tx
            // Appearance has no measured-post contract. Fade missing-coverage
            // edges over eight source posts rather than introduce a rectangle.
            let t = min(1, max(0, min(x, y, Double(width - 1) - x, Double(height - 1) - y) / 8))
            return (north + (south - north) * ty, t * t * (3 - 2 * t))
        }
    }

    let frame: LMSelenographicLocalFrame
    let slabs: [Slab]

    func reflectance(east: Double, north: Double) -> Float {
        let coordinate = frame.coordinate(for: .init(northMeters: north, eastMeters: east, upMeters: 0))
        // Existing uniform material fallback is 0.25 encoded, approximately
        // 0.0509 linear. It is explicitly a model where normalized WAC is absent.
        var linear = pow((0.25 + 0.055) / 1.055, 2.4)
        for slab in slabs {
            if let sample = slab.sample(at: coordinate) { linear += (sample.linear - linear) * sample.weight }
        }
        return Float(linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055)
    }
}
