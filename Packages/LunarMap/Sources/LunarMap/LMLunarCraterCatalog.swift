import Foundation

/// Frozen output of the offline NAC crater detector.
///
/// The catalog records only observations that can be recovered from the
/// registered photograph: position, diameter, freshness, and confidence. It
/// deliberately does not contain height samples. `LMLunarGeologyModel` turns
/// those observations into bounded sub-resolution relief while the measured
/// DTM remains authoritative at every post.
public struct LMLunarCraterCatalog: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    enum CoordinateFrame: String, Codable, Sendable {
        case landingOriginLocalNorthEastMeters = "landing-origin-local-north-east-meters"
    }

    struct Entry: Codable, Equatable, Sendable {
        let id: String
        let eastMeters: Double
        let northMeters: Double
        let diameterMeters: Double
        let sharpness: Double
        let confidence: Double
        /// Optional shape estimates. The detector may omit these when the
        /// image evidence supports a circle but not a stable ellipse fit.
        let aspectRatio: Double?
        let rotationRadians: Double?

        init(
            id: String,
            eastMeters: Double,
            northMeters: Double,
            diameterMeters: Double,
            sharpness: Double,
            confidence: Double,
            aspectRatio: Double? = nil,
            rotationRadians: Double? = nil
        ) {
            self.id = id
            self.eastMeters = eastMeters
            self.northMeters = northMeters
            self.diameterMeters = diameterMeters
            self.sharpness = sharpness
            self.confidence = confidence
            self.aspectRatio = aspectRatio
            self.rotationRadians = rotationRadians
        }
    }

    enum CatalogError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
        case emptyCatalogID
        case emptyGeneratorVersion
        case missingSourceIDs
        case duplicateSourceID(String)
        case emptyEntryID
        case duplicateEntryID(String)
        case nonFiniteValue(entryID: String, field: String)
        case invalidDiameter(entryID: String, value: Double)
        case invalidSharpness(entryID: String, value: Double)
        case invalidConfidence(entryID: String, value: Double)
        case invalidAspectRatio(entryID: String, value: Double)
    }

    let schemaVersion: Int
    let catalogID: String
    let generatorVersion: String
    let sourceIDs: [String]
    let coordinateFrame: CoordinateFrame
    let entries: [Entry]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        catalogID: String,
        generatorVersion: String,
        sourceIDs: [String],
        coordinateFrame: CoordinateFrame = .landingOriginLocalNorthEastMeters,
        entries: [Entry]
    ) throws {
        self.schemaVersion = schemaVersion
        self.catalogID = catalogID
        self.generatorVersion = generatorVersion
        self.sourceIDs = sourceIDs
        self.coordinateFrame = coordinateFrame
        // Canonical order makes catalog-driven sampling independent of JSON
        // ordering and gives the offline generator one stable serialization.
        self.entries = entries.sorted { $0.id < $1.id }
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            catalogID: container.decode(String.self, forKey: .catalogID),
            generatorVersion: container.decode(String.self, forKey: .generatorVersion),
            sourceIDs: container.decode([String].self, forKey: .sourceIDs),
            coordinateFrame: container.decode(CoordinateFrame.self, forKey: .coordinateFrame),
            entries: container.decode([Entry].self, forKey: .entries)
        )
    }

    var versionedModelID: String {
        "\(catalogID)@\(generatorVersion)"
    }

    static func load(
        fileName: String,
        bundle: Bundle = LunarMap.resources
    ) throws -> LMLunarCraterCatalog {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Terrain"
        ) ?? bundle.url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(
            LMLunarCraterCatalog.self,
            from: Data(contentsOf: url)
        )
    }

    private func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CatalogError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !catalogID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CatalogError.emptyCatalogID
        }
        guard !generatorVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CatalogError.emptyGeneratorVersion
        }
        guard !sourceIDs.isEmpty else { throw CatalogError.missingSourceIDs }
        var uniqueSourceIDs = Set<String>()
        for sourceID in sourceIDs {
            guard uniqueSourceIDs.insert(sourceID).inserted else {
                throw CatalogError.duplicateSourceID(sourceID)
            }
        }

        var uniqueEntryIDs = Set<String>()
        for entry in entries {
            guard !entry.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CatalogError.emptyEntryID
            }
            guard uniqueEntryIDs.insert(entry.id).inserted else {
                throw CatalogError.duplicateEntryID(entry.id)
            }
            try requireFinite(entry.eastMeters, field: "eastMeters", entryID: entry.id)
            try requireFinite(entry.northMeters, field: "northMeters", entryID: entry.id)
            try requireFinite(entry.diameterMeters, field: "diameterMeters", entryID: entry.id)
            try requireFinite(entry.sharpness, field: "sharpness", entryID: entry.id)
            try requireFinite(entry.confidence, field: "confidence", entryID: entry.id)
            guard entry.diameterMeters > 0 else {
                throw CatalogError.invalidDiameter(
                    entryID: entry.id,
                    value: entry.diameterMeters
                )
            }
            guard (0...1).contains(entry.sharpness) else {
                throw CatalogError.invalidSharpness(
                    entryID: entry.id,
                    value: entry.sharpness
                )
            }
            guard (0...1).contains(entry.confidence) else {
                throw CatalogError.invalidConfidence(
                    entryID: entry.id,
                    value: entry.confidence
                )
            }
            if let aspectRatio = entry.aspectRatio {
                try requireFinite(aspectRatio, field: "aspectRatio", entryID: entry.id)
                guard aspectRatio > 0, aspectRatio <= 1 else {
                    throw CatalogError.invalidAspectRatio(
                        entryID: entry.id,
                        value: aspectRatio
                    )
                }
            }
            if let rotationRadians = entry.rotationRadians {
                try requireFinite(
                    rotationRadians,
                    field: "rotationRadians",
                    entryID: entry.id
                )
            }
        }
    }

    private func requireFinite(
        _ value: Double,
        field: String,
        entryID: String
    ) throws {
        guard value.isFinite else {
            throw CatalogError.nonFiniteValue(entryID: entryID, field: field)
        }
    }
}

/// Spatial lookup for catalog craters.
///
/// Each observed crater is inserted into every cell touched by its full
/// morphology envelope. Sampling therefore performs a single dictionary
/// lookup instead of walking the complete production catalog per vertex.
struct LMLunarCraterCatalogIndex: Equatable, Sendable {
    private struct Cell: Hashable, Sendable {
        let east: Int64
        let north: Int64
    }

    let catalog: LMLunarCraterCatalog
    private let cellSizeMeters: Double
    private let buckets: [Cell: [Int]]

    init(catalog: LMLunarCraterCatalog, cellSizeMeters: Double = 4) {
        self.catalog = catalog
        self.cellSizeMeters = cellSizeMeters
        var buckets = [Cell: [Int]]()
        for (index, entry) in catalog.entries.enumerated() {
            let influenceRadius = entry.diameterMeters * 0.5 * 1.65
            let eastCells = Self.cellRange(
                minimum: entry.eastMeters - influenceRadius,
                maximum: entry.eastMeters + influenceRadius,
                cellSizeMeters: cellSizeMeters
            )
            let northCells = Self.cellRange(
                minimum: entry.northMeters - influenceRadius,
                maximum: entry.northMeters + influenceRadius,
                cellSizeMeters: cellSizeMeters
            )
            for northCell in northCells {
                for eastCell in eastCells {
                    buckets[Cell(east: eastCell, north: northCell), default: []]
                        .append(index)
                }
            }
        }
        self.buckets = buckets
    }

    func cratersAffecting(
        eastMeters: Double,
        northMeters: Double,
        minimumDiameterMeters: Double
    ) -> [LMLunarGeologyModel.Crater] {
        let cell = Cell(
            east: Int64(floor(eastMeters / cellSizeMeters)),
            north: Int64(floor(northMeters / cellSizeMeters))
        )
        return (buckets[cell] ?? []).compactMap { index in
            let entry = catalog.entries[index]
            guard entry.diameterMeters >= minimumDiameterMeters else { return nil }
            return crater(for: entry)
        }
    }

    func overlapsHashCrater(_ crater: LMLunarGeologyModel.Crater) -> Bool {
        let radius = crater.diameterMeters * 0.5
        let eastCells = Self.cellRange(
            minimum: crater.eastMeters - radius,
            maximum: crater.eastMeters + radius,
            cellSizeMeters: cellSizeMeters
        )
        let northCells = Self.cellRange(
            minimum: crater.northMeters - radius,
            maximum: crater.northMeters + radius,
            cellSizeMeters: cellSizeMeters
        )
        var visited = Set<Int>()
        for northCell in northCells {
            for eastCell in eastCells {
                for index in buckets[Cell(east: eastCell, north: northCell)] ?? []
                where visited.insert(index).inserted {
                    let catalogCrater = catalog.entries[index]
                    let combinedRadius = radius + catalogCrater.diameterMeters * 0.5
                    if hypot(
                        crater.eastMeters - catalogCrater.eastMeters,
                        crater.northMeters - catalogCrater.northMeters
                    ) < combinedRadius {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func crater(for entry: LMLunarCraterCatalog.Entry)
        -> LMLunarGeologyModel.Crater {
        LMLunarGeologyModel.Crater(
            eastMeters: entry.eastMeters,
            northMeters: entry.northMeters,
            diameterMeters: entry.diameterMeters,
            aspectRatio: entry.aspectRatio ?? 1,
            rotationRadians: entry.rotationRadians ?? 0,
            sharpness: entry.sharpness,
            rimPhase: stableUnit(entry.id, salt: 1) * 2 * .pi,
            rimLobes: 3 + Int(stableUnit(entry.id, salt: 2) * 5),
            ejectaPhase: stableUnit(entry.id, salt: 3) * 2 * .pi
        )
    }

    private func stableUnit(_ id: String, salt: UInt64) -> Double {
        var value = 0xcbf2_9ce4_8422_2325 ^ salt
        for byte in id.utf8 {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01B3
        }
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value & 0x001F_FFFF_FFFF_FFFF)
            / Double(0x0020_0000_0000_0000)
    }

    private static func cellRange(
        minimum: Double,
        maximum: Double,
        cellSizeMeters: Double
    ) -> ClosedRange<Int64> {
        let lower = Int64(floor(minimum / cellSizeMeters))
        let upper = Int64(floor(maximum / cellSizeMeters))
        return lower...upper
    }
}
