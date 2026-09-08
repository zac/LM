import Foundation

/// Compact catalog of overlapping raw PDS strips. Every byte range has its
/// own digest; the full image never enters the application cache or bundle.
package struct LMLunarElevationCatalog: Decodable, Sendable {
    let schemaVersion: Int
    let generatorVersion: String
    let productID: String
    let productVersion: String
    let url: String
    let labelURL: String
    let labelFile: String
    let labelSHA256: String
    let sourceSHA256: String
    let sourceBytes: Int
    let rows: Int
    let rowBytes: Int
    let pixelsPerDegree: Double
    let coreRows: Int
    let haloRows: Int
    let postSpacingMeters: Double
    let residualCapRatio: Double
    let detail: String
    let sha256: [String]

    enum CatalogError: Error { case missingResource, invalidCatalog }

    package static func load(bundle: Bundle = LunarMap.resources) throws -> Self {
        let manifest = try LMTerrainManifest.load(bundle: bundle)
        guard let resource = manifest.remoteElevationCatalog,
              let location = bundle.url(forResource: resource.file, withExtension: nil, subdirectory: "Terrain") ?? bundle.url(forResource: resource.file, withExtension: nil) else {
            throw CatalogError.missingResource
        }
        let data = try Data(contentsOf: location)
        guard LMLunarElevationGrid.digest(data) == resource.sha256 else { throw CatalogError.invalidCatalog }
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1, catalog.productID == "LDEM_128",
              catalog.productVersion == "V3.0", catalog.rows == 23_040,
              catalog.rowBytes == 92_160, catalog.sourceBytes == 2_123_366_400,
              catalog.coreRows == 32, catalog.haloRows == 1, catalog.pixelsPerDegree == 128,
              catalog.sha256.count == 720, catalog.residualCapRatio == 0.12,
              let labelURL = bundle.url(forResource: catalog.labelFile, withExtension: nil, subdirectory: "Terrain") ?? bundle.url(forResource: catalog.labelFile, withExtension: nil),
              LMLunarElevationGrid.digest(try Data(contentsOf: labelURL)) == catalog.labelSHA256 else {
            throw CatalogError.invalidCatalog
        }
        return catalog
    }

    func source(at index: Int) -> LMTerrainManifest.Source {
        precondition(sha256.indices.contains(index))
        let first = max(0, index * coreRows - haloRows)
        let last = min(rows - 1, (index + 1) * coreRows + haloRows - 1)
        return .init(
            id: "lola-128-strip-\(index)", role: "global-elevation",
            coverage: .init(minimumLatitudeDegrees: 90 - Double(last + 1) / pixelsPerDegree,
                            maximumLatitudeDegrees: 90 - Double(first) / pixelsPerDegree,
                            westernmostLongitudeDegrees: 0, easternmostLongitudeDegrees: 360),
            postSpacingMeters: postSpacingMeters, residualCapRatio: residualCapRatio,
            url: url, sha256: sha256[index], bytes: (last - first + 1) * rowBytes,
            sourceBytes: sourceBytes, byteRangeStart: first * rowBytes,
            byteRangeEnd: (last + 1) * rowBytes - 1, sourceMD5: nil,
            bundledFile: nil, bundledLabelFile: nil, sourceRowStart: first,
            sourceRowEnd: last, sourceRowBytes: rowBytes,
            mapResolutionPixelsPerDegree: pixelsPerDegree, productId: productID,
            productVersion: productVersion, labelURL: labelURL,
            labelSHA256: labelSHA256, labelBytes: 5_133, detail: detail
        )
    }

    /// Full longitude rows also cover a region that crosses a pole or meridian.
    /// Radius is a surface arc distance, converted through the coordinate datum.
    func sources(around coordinate: LMSelenographicCoordinate,
                 radiusMeters: Double) -> [LMTerrainManifest.Source] {
        guard coordinate.latitudeDegrees.isFinite, abs(coordinate.latitudeDegrees) <= 90,
              radiusMeters.isFinite, radiusMeters >= 0 else { return [] }
        let radiusDegrees = radiusMeters / LMSelenographicCoordinateSystem.meanEarthPolarRadiusMeters * 180 / .pi
        let north = min(90, coordinate.latitudeDegrees + radiusDegrees)
        let south = max(-90, coordinate.latitudeDegrees - radiusDegrees)
        let first = max(0, min(sha256.count - 1, Int(floor((90 - north) * pixelsPerDegree / Double(coreRows)))))
        let last = max(first, min(sha256.count - 1, Int(floor((90 - south) * pixelsPerDegree / Double(coreRows)))))
        return (first...last).map { source(at: $0) }
    }
}
