import CoreGraphics
import Foundation
import ImageIO
import simd

/// Deterministic regolith texture below the finest rendered triangle.
///
/// The clipmap's densest tile carries 0.125 m geometry, and the bundled WAC/NAC
/// albedo resolves 0.5 m. Neither can express what a regolith surface actually
/// looks like from a cockpit two meters above it: centimetre clods, small
/// fragments, and the 2-20 cm craterlets that cover every lunar surface Apollo
/// photographed. This model supplies exactly that band, as a normal and
/// reflectance field baked into small per-tile textures.
///
/// It is strictly appearance. It never reaches the mesh, the terrain height
/// query, or the landing-gear contact surface, so it cannot move a footpad or
/// change a landing outcome. `LMLunarGeologyModel` remains the only procedural
/// source of shape, and measured LROC posts remain authoritative above it.
struct LMRegolithMicrotextureModel: Equatable, Sendable {
    static let modelID = "regolith-microtexture-v1"
    /// Surveyor's small-crater size-frequency slope extended below the 0.22 m
    /// floor `LMLunarGeologyModel` uses for geometry. Nothing here is claimed
    /// as a surveyed Apollo 11 feature.
    static let surveyorSourceURL =
        "https://www.usgs.gov/publications/observations-lunar-regolith-and-earth-television-camera-surveyor-7"

    static let minimumCraterDiameterMeters = 0.02
    static let maximumCraterDiameterMeters = 0.20
    /// Relief stays inside a centimetre and a half, which is far below the
    /// 0.125 m triangles it is layered onto.
    static let maximumReliefMeters = 0.015

    let seed: UInt64
    let cellSizeMeters = 0.25
    let candidatesPerCell = 2
    let candidateAcceptance = 0.42

    init(seed: UInt64 = 0x52_45_47_4F_4C_49_54_48) {
        self.seed = seed
    }

    /// Micro-relief in meters at a lunar coordinate.
    func reliefMeters(
        eastMeters: Double,
        northMeters: Double,
        craterlets: LMRegolithCraterletField? = nil
    ) -> Double {
        var relief = valueNoise(eastMeters, northMeters, wavelengthMeters: 0.11, property: 3)
            * 0.0042
        relief += valueNoise(eastMeters, northMeters, wavelengthMeters: 0.034, property: 5)
            * 0.0016
        relief += valueNoise(eastMeters, northMeters, wavelengthMeters: 0.012, property: 7)
            * 0.0006

        let eastCell = Int64(floor(eastMeters / cellSizeMeters))
        let northCell = Int64(floor(northMeters / cellSizeMeters))
        for northOffset in -1...1 {
            for eastOffset in -1...1 {
                for candidate in 0..<candidatesPerCell {
                    guard let crater = resolvedCraterlet(
                        craterlets,
                        cellEast: eastCell + Int64(eastOffset),
                        cellNorth: northCell + Int64(northOffset),
                        candidate: candidate
                    ) else { continue }
                    relief += craterletRelief(
                        eastMeters: eastMeters,
                        northMeters: northMeters,
                        crater: crater
                    )
                }
            }
        }
        let limit = Self.maximumReliefMeters
        return limit * tanh(relief / limit)
    }

    /// Multiplicative reflectance modulation around 1.
    ///
    /// Fresh small craters expose immature, brighter regolith and throw bright
    /// haloes; degraded ones fade back into the background. Clods and fragments
    /// add the fine mottling that makes a regolith surface read as granular
    /// rather than as a smooth painted plane.
    func reflectanceModulation(
        eastMeters: Double,
        northMeters: Double,
        craterlets: LMRegolithCraterletField? = nil
    ) -> Double {
        var modulation = valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.16,
            property: 11
        ) * 0.055
        modulation += valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.045,
            property: 13
        ) * 0.038
        modulation += valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.013,
            property: 17
        ) * 0.020

        let eastCell = Int64(floor(eastMeters / cellSizeMeters))
        let northCell = Int64(floor(northMeters / cellSizeMeters))
        for northOffset in -1...1 {
            for eastOffset in -1...1 {
                for candidate in 0..<candidatesPerCell {
                    guard let crater = resolvedCraterlet(
                        craterlets,
                        cellEast: eastCell + Int64(eastOffset),
                        cellNorth: northCell + Int64(northOffset),
                        candidate: candidate
                    ) else { continue }
                    let radius = crater.diameterMeters / 2
                    let distance = hypot(
                        eastMeters - crater.eastMeters,
                        northMeters - crater.northMeters
                    ) / radius
                    guard distance < 2.2 else { continue }
                    let freshness = crater.sharpness
                    if distance < 0.85 {
                        modulation -= 0.05 * freshness * (0.85 - distance)
                    } else {
                        let halo = exp(-pow((distance - 1.0) / 0.75, 2))
                        modulation += 0.16 * freshness * halo
                    }
                }
            }
        }
        return min(max(1 + modulation, 0.78), 1.28)
    }

    struct Craterlet: Equatable, Sendable {
        let eastMeters: Double
        let northMeters: Double
        let diameterMeters: Double
        let sharpness: Double
    }

    func craterlet(cellEast: Int64, cellNorth: Int64, candidate: Int) -> Craterlet? {
        guard unit(cellEast, cellNorth, candidate, 0) < candidateAcceptance else {
            return nil
        }
        let minimumInverseSquare = 1 / pow(Self.minimumCraterDiameterMeters, 2)
        let maximumInverseSquare = 1 / pow(Self.maximumCraterDiameterMeters, 2)
        let draw = unit(cellEast, cellNorth, candidate, 1)
        let diameter = 1 / sqrt(
            minimumInverseSquare - draw * (minimumInverseSquare - maximumInverseSquare)
        )
        return Craterlet(
            eastMeters: (Double(cellEast) + unit(cellEast, cellNorth, candidate, 2))
                * cellSizeMeters,
            northMeters: (Double(cellNorth) + unit(cellEast, cellNorth, candidate, 3))
                * cellSizeMeters,
            diameterMeters: diameter,
            sharpness: 0.10 + unit(cellEast, cellNorth, candidate, 4) * 0.90
        )
    }

    /// Precompute every candidate craterlet over a bounded region. A 512-texel
    /// bake evaluates this field half a million times; without memoization the
    /// generator hash, not the geometry, dominates tile generation.
    func craterletField(
        eastMetersRange: ClosedRange<Double>,
        northMetersRange: ClosedRange<Double>,
        haloCells: Int = 2
    ) -> LMRegolithCraterletField {
        let minimumEast = Int64(floor(eastMetersRange.lowerBound / cellSizeMeters))
            - Int64(haloCells)
        let maximumEast = Int64(floor(eastMetersRange.upperBound / cellSizeMeters))
            + Int64(haloCells)
        let minimumNorth = Int64(floor(northMetersRange.lowerBound / cellSizeMeters))
            - Int64(haloCells)
        let maximumNorth = Int64(floor(northMetersRange.upperBound / cellSizeMeters))
            + Int64(haloCells)
        let eastCount = Int(maximumEast - minimumEast) + 1
        let northCount = Int(maximumNorth - minimumNorth) + 1

        var craterlets = [Craterlet?]()
        craterlets.reserveCapacity(eastCount * northCount * candidatesPerCell)
        for northIndex in 0..<northCount {
            for eastIndex in 0..<eastCount {
                for candidate in 0..<candidatesPerCell {
                    craterlets.append(craterlet(
                        cellEast: minimumEast + Int64(eastIndex),
                        cellNorth: minimumNorth + Int64(northIndex),
                        candidate: candidate
                    ))
                }
            }
        }
        return LMRegolithCraterletField(
            minimumEastCell: minimumEast,
            minimumNorthCell: minimumNorth,
            eastCellCount: eastCount,
            northCellCount: northCount,
            candidatesPerCell: candidatesPerCell,
            craterlets: craterlets
        )
    }

    private func resolvedCraterlet(
        _ field: LMRegolithCraterletField?,
        cellEast: Int64,
        cellNorth: Int64,
        candidate: Int
    ) -> Craterlet? {
        if let field, let cached = field.craterlet(
            cellEast: cellEast,
            cellNorth: cellNorth,
            candidate: candidate
        ) {
            return cached
        }
        return craterlet(cellEast: cellEast, cellNorth: cellNorth, candidate: candidate)
    }

    private func craterletRelief(
        eastMeters: Double,
        northMeters: Double,
        crater: Craterlet
    ) -> Double {
        let radius = crater.diameterMeters / 2
        let distance = hypot(
            eastMeters - crater.eastMeters,
            northMeters - crater.northMeters
        ) / radius
        guard distance < 1.5 else { return 0 }
        let depth = crater.diameterMeters * (0.03 + crater.sharpness * 0.10)
        let rim = crater.diameterMeters * (0.006 + crater.sharpness * 0.022)
        var relief = 0.0
        if distance < 1 {
            relief -= depth * pow(1 - distance * distance, 1.1)
        }
        let rimDistance = (distance - 1) / 0.22
        relief += rim * exp(-rimDistance * rimDistance)
        return relief
    }

    private func valueNoise(
        _ eastMeters: Double,
        _ northMeters: Double,
        wavelengthMeters: Double,
        property: UInt64
    ) -> Double {
        let east = eastMeters / wavelengthMeters
        let north = northMeters / wavelengthMeters
        let eastCell = Int64(floor(east))
        let northCell = Int64(floor(north))
        let eastBlend = Self.smoothstep(east - floor(east))
        let northBlend = Self.smoothstep(north - floor(north))
        func signed(_ x: Int64, _ y: Int64) -> Double {
            unit(x, y, 0, property) * 2 - 1
        }
        let northwest = signed(eastCell, northCell)
        let northeast = signed(eastCell + 1, northCell)
        let southwest = signed(eastCell, northCell + 1)
        let southeast = signed(eastCell + 1, northCell + 1)
        let top = northwest + (northeast - northwest) * eastBlend
        let bottom = southwest + (southeast - southwest) * eastBlend
        return top + (bottom - top) * northBlend
    }

    private func unit(
        _ cellEast: Int64,
        _ cellNorth: Int64,
        _ candidate: Int,
        _ property: UInt64
    ) -> Double {
        var value = UInt64(bitPattern: cellEast) &* 0x9E37_79B9_7F4A_7C15
        value ^= UInt64(bitPattern: cellNorth) &* 0xBF58_476D_1CE4_E5B9
        value ^= UInt64(candidate) &* 0x94D0_49BB_1331_11EB
        value ^= property &* 0xD6E8_FEB8_6659_FD93
        value ^= seed
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value & 0x001F_FFFF_FFFF_FFFF) / Double(0x0020_0000_0000_0000)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

/// Craterlets precomputed over a bounded block of microtexture cells.
///
/// Outside the block the lookup returns `nil` at the outer level, so callers
/// fall back to the model's on-demand derivation and get the same craterlet.
struct LMRegolithCraterletField: Sendable {
    let minimumEastCell: Int64
    let minimumNorthCell: Int64
    let eastCellCount: Int
    let northCellCount: Int
    let candidatesPerCell: Int
    let craterlets: [LMRegolithMicrotextureModel.Craterlet?]

    func craterlet(
        cellEast: Int64,
        cellNorth: Int64,
        candidate: Int
    ) -> LMRegolithMicrotextureModel.Craterlet?? {
        guard cellEast >= minimumEastCell,
              cellNorth >= minimumNorthCell,
              cellEast < minimumEastCell + Int64(eastCellCount),
              cellNorth < minimumNorthCell + Int64(northCellCount) else {
            return nil
        }
        let eastIndex = Int(cellEast - minimumEastCell)
        let northIndex = Int(cellNorth - minimumNorthCell)
        let offset = (northIndex * eastCellCount + eastIndex) * candidatesPerCell + candidate
        return .some(craterlets[offset])
    }
}

/// CPU-side copy of the measured near-field reflectance.
///
/// The bundled `near-field-albedo.png` encodes a linear 643 nm reflectance
/// proxy and is byte-for-byte gray, so one channel is lossless. Keeping it
/// resident lets each fine tile bake its own texture without ever inventing a
/// reflectance the WAC/NAC sources did not supply.
struct LMMeasuredAlbedoField: Sendable {
    let width: Int
    let height: Int
    /// Half-extent of the covered square, meters from the terrain origin.
    let halfExtentMeters: Double
    let luminance: [UInt8]

    enum FieldError: Error, Equatable {
        case unsupportedFormat
        case missingResource(String)
    }

    /// Bilinear reflectance in 0...1, or nil outside the measured tile.
    func reflectance(eastMeters: Double, northMeters: Double) -> Float? {
        let column = (eastMeters + halfExtentMeters) / (2 * halfExtentMeters)
            * Double(width - 1)
        let row = (halfExtentMeters - northMeters) / (2 * halfExtentMeters)
            * Double(height - 1)
        guard column >= 0, row >= 0,
              column <= Double(width - 1),
              row <= Double(height - 1) else {
            return nil
        }
        let x0 = Int(column.rounded(.down))
        let y0 = Int(row.rounded(.down))
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = Float(column - Double(x0))
        let ty = Float(row - Double(y0))
        func value(_ x: Int, _ y: Int) -> Float {
            Float(luminance[y * width + x]) / 255
        }
        let top = value(x0, y0) + (value(x1, y0) - value(x0, y0)) * tx
        let bottom = value(x0, y1) + (value(x1, y1) - value(x0, y1)) * tx
        return top + (bottom - top) * ty
    }

    static func load(
        tile: LMTerrainManifest.Tile,
        bundle: Bundle = .main
    ) throws -> LMMeasuredAlbedoField {
        let name = (tile.albedoFile as NSString).deletingPathExtension
        let ext = (tile.albedoFile as NSString).pathExtension
        guard let url = bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Terrain"
        ) ?? bundle.url(forResource: name, withExtension: ext) else {
            throw FieldError.missingResource(tile.albedoFile)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCache: false
              ] as CFDictionary) else {
            throw FieldError.unsupportedFormat
        }
        let width = image.width
        let height = image.height
        // Draw into the image's own color space so this is an identity copy.
        // The bundled texture stores its reflectance proxy encoded exactly the
        // way the renderer samples it; converting to a linear space here would
        // make baked tiles several times darker than the near-field mesh they
        // sit on top of.
        guard let space = image.colorSpace, space.numberOfComponents == 3 else {
            throw FieldError.unsupportedFormat
        }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        try rgba.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else {
                throw FieldError.unsupportedFormat
            }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
        }
        // The source is byte-for-byte gray, so one channel is lossless and
        // keeps the resident copy to a quarter of the decoded image.
        var luminance = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            luminance[index] = rgba[index * 4]
        }
        return LMMeasuredAlbedoField(
            width: width,
            height: height,
            halfExtentMeters: tile.extentMeters / 2,
            luminance: luminance
        )
    }
}

/// Baked appearance textures for one progressive terrain tile.
struct LMTerrainTileDetailTextures: Sendable {
    let resolution: Int
    /// 8-bit RGBA, measured reflectance modulated by bounded micro-contrast.
    let albedo: [UInt8]
    /// 8-bit RGBA tangent-space normals for the sub-triangle micro-relief.
    let normal: [UInt8]
}

/// Bakes the sub-triangle appearance of one clipmap tile.
///
/// Both textures use tile-local UVs, so the tile carries its own resampled
/// slice of the measured reflectance instead of sharing the 2 km near-field
/// atlas. That is what makes a second, world-scaled detail map unnecessary:
/// RealityKit's PBR materials expose only one texture-coordinate buffer.
enum LMTerrainTileDetailBaker {
    static let modelID = LMRegolithMicrotextureModel.modelID

    /// Texel budget per tile. A 16 m tile bakes at about 3 cm per texel and a
    /// 64 m tile at about 12 cm, for 1 MB of RGBA per texture.
    static let resolution = 512

    /// The tile's outer collar fades detail to nothing so the baked texture
    /// meets the coarser parent surface underneath it without a visible seam,
    /// mirroring the geometry's edge morph.
    static let edgeFadeFraction = 0.12

    nonisolated static func bake(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?,
        microtexture: LMRegolithMicrotextureModel = LMRegolithMicrotextureModel(),
        resolution: Int = resolution
    ) throws -> LMTerrainTileDetailTextures {
        let size = plan.sizeMeters
        let half = size / 2
        let texelSpacing = size / Double(resolution)
        let reach = half + texelSpacing
        let craterlets = microtexture.craterletField(
            eastMetersRange: (plan.centerEastMeters - reach)...(plan.centerEastMeters + reach),
            northMetersRange: (plan.centerNorthMeters - reach)...(plan.centerNorthMeters + reach)
        )

        // One extra row and column so central differences at the last texel do
        // not have to clamp, which would flatten the tile's own border.
        let gridSize = resolution + 2
        var relief = [Double](repeating: 0, count: gridSize * gridSize)
        for row in 0..<gridSize {
            try Task.checkCancellation()
            let north = plan.centerNorthMeters + half
                - (Double(row) - 0.5) * texelSpacing
            for column in 0..<gridSize {
                let east = plan.centerEastMeters - half
                    + (Double(column) - 0.5) * texelSpacing
                relief[row * gridSize + column] = microtexture.reliefMeters(
                    eastMeters: east,
                    northMeters: north,
                    craterlets: craterlets
                )
            }
        }

        var albedo = [UInt8](repeating: 0, count: resolution * resolution * 4)
        var normal = [UInt8](repeating: 0, count: resolution * resolution * 4)

        for row in 0..<resolution {
            try Task.checkCancellation()
            let north = plan.centerNorthMeters + half - (Double(row) + 0.5) * texelSpacing
            for column in 0..<resolution {
                let east = plan.centerEastMeters - half
                    + (Double(column) + 0.5) * texelSpacing
                let fade = edgeFade(
                    column: column,
                    row: row,
                    resolution: resolution
                )

                // Central differences on the padded relief grid. Row indices
                // run north to south, so a positive row step is southward.
                let gridIndex = (row + 1) * gridSize + (column + 1)
                let eastSlope = (relief[gridIndex + 1] - relief[gridIndex - 1])
                    / (2 * texelSpacing) * fade
                let northSlope = (
                    relief[gridIndex - gridSize] - relief[gridIndex + gridSize]
                ) / (2 * texelSpacing) * fade

                // Mesh tangent basis for this grid: T is east (RealityKit -Z),
                // B is south (-X), N is up. Project the world normal
                // (-dh/dnorth, 1, dh/deast) onto it.
                let tangentSpace = simd_normalize(SIMD3<Float>(
                    Float(-eastSlope),
                    Float(northSlope),
                    1
                ))
                let normalOffset = (row * resolution + column) * 4
                normal[normalOffset] = encode(tangentSpace.x)
                normal[normalOffset + 1] = encode(tangentSpace.y)
                normal[normalOffset + 2] = encode(tangentSpace.z)
                normal[normalOffset + 3] = 255

                let measured = albedoField?.reflectance(
                    eastMeters: east,
                    northMeters: north
                ) ?? 0.25
                let modulation = 1 + (
                    microtexture.reflectanceModulation(
                        eastMeters: east,
                        northMeters: north,
                        craterlets: craterlets
                    ) - 1
                ) * fade
                let value = UInt8(
                    min(max(Double(measured) * modulation, 0), 1) * 255
                )
                let albedoOffset = (row * resolution + column) * 4
                albedo[albedoOffset] = value
                albedo[albedoOffset + 1] = value
                albedo[albedoOffset + 2] = value
                albedo[albedoOffset + 3] = 255
            }
        }

        return LMTerrainTileDetailTextures(
            resolution: resolution,
            albedo: albedo,
            normal: normal
        )
    }

    /// Smooth 0 at the tile border rising to 1 inside the collar.
    private static func edgeFade(column: Int, row: Int, resolution: Int) -> Double {
        let collar = max(1.0, Double(resolution) * edgeFadeFraction)
        let distance = Double(min(
            min(column, resolution - 1 - column),
            min(row, resolution - 1 - row)
        ))
        let normalized = min(max(distance / collar, 0), 1)
        return normalized * normalized * (3 - 2 * normalized)
    }

    private static func encode(_ component: Float) -> UInt8 {
        UInt8(min(max((component * 0.5 + 0.5) * 255, 0), 255))
    }

    /// Wrap baked texels as a CGImage. Safe off the main actor; only the
    /// `TextureResource` it feeds has to be created on it.
    nonisolated static func image(
        from texels: [UInt8],
        resolution: Int,
        colorSpace: CGColorSpace
    ) -> CGImage? {
        let data = Data(texels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: resolution,
            height: resolution,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: resolution * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
