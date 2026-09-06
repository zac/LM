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
    static let modelID = "regolith-microtexture-v2"
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
        sampleSpacingMeters: Double = 0,
        craterlets: LMRegolithCraterletField? = nil
    ) -> Double {
        var relief = valueNoise(eastMeters, northMeters, wavelengthMeters: 0.11, property: 3)
            * 0.0042 * samplingWeight(
                featureSizeMeters: 0.11,
                sampleSpacingMeters: sampleSpacingMeters
            )
        relief += valueNoise(eastMeters, northMeters, wavelengthMeters: 0.034, property: 5)
            * 0.0016 * samplingWeight(
                featureSizeMeters: 0.034,
                sampleSpacingMeters: sampleSpacingMeters
            )
        relief += valueNoise(eastMeters, northMeters, wavelengthMeters: 0.012, property: 7)
            * 0.0006 * samplingWeight(
                featureSizeMeters: 0.012,
                sampleSpacingMeters: sampleSpacingMeters
            )

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
                    relief += craterletContribution(
                        eastMeters: eastMeters,
                        northMeters: northMeters,
                        crater: crater
                    ).reliefMeters * samplingWeight(
                        featureSizeMeters: crater.diameterMeters,
                        sampleSpacingMeters: sampleSpacingMeters
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
        sampleSpacingMeters: Double = 0,
        craterlets: LMRegolithCraterletField? = nil
    ) -> Double {
        var modulation = valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.16,
            property: 11
        ) * 0.055 * samplingWeight(
            featureSizeMeters: 0.16,
            sampleSpacingMeters: sampleSpacingMeters
        )
        modulation += valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.045,
            property: 13
        ) * 0.038 * samplingWeight(
            featureSizeMeters: 0.045,
            sampleSpacingMeters: sampleSpacingMeters
        )
        modulation += valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.013,
            property: 17
        ) * 0.020 * samplingWeight(
            featureSizeMeters: 0.013,
            sampleSpacingMeters: sampleSpacingMeters
        )

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
                    modulation += craterletContribution(
                        eastMeters: eastMeters,
                        northMeters: northMeters,
                        crater: crater
                    ).reflectanceDelta * samplingWeight(
                        featureSizeMeters: crater.diameterMeters,
                        sampleSpacingMeters: sampleSpacingMeters
                    )
                }
            }
        }
        return min(max(1 + modulation, 0.78), 1.28)
    }

    /// Joint sample used by the tile baker. Relief and reflectance depend on
    /// the same nearby craterlets, so resolving that deterministic field once
    /// avoids a second 3x3 candidate walk for every texture texel.
    func appearanceSample(
        eastMeters: Double,
        northMeters: Double,
        sampleSpacingMeters: Double = 0,
        craterlets: LMRegolithCraterletField? = nil
    ) -> (reliefMeters: Double, reflectanceModulation: Double) {
        var relief = valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.11,
            property: 3
        ) * 0.0042 * samplingWeight(
            featureSizeMeters: 0.11,
            sampleSpacingMeters: sampleSpacingMeters
        )
        relief += valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.034,
            property: 5
        ) * 0.0016 * samplingWeight(
            featureSizeMeters: 0.034,
            sampleSpacingMeters: sampleSpacingMeters
        )
        relief += valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.012,
            property: 7
        ) * 0.0006 * samplingWeight(
            featureSizeMeters: 0.012,
            sampleSpacingMeters: sampleSpacingMeters
        )

        var modulation = valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.16,
            property: 11
        ) * 0.055 * samplingWeight(
            featureSizeMeters: 0.16,
            sampleSpacingMeters: sampleSpacingMeters
        )
        modulation += valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.045,
            property: 13
        ) * 0.038 * samplingWeight(
            featureSizeMeters: 0.045,
            sampleSpacingMeters: sampleSpacingMeters
        )
        modulation += valueNoise(
            eastMeters,
            northMeters,
            wavelengthMeters: 0.013,
            property: 17
        ) * 0.020 * samplingWeight(
            featureSizeMeters: 0.013,
            sampleSpacingMeters: sampleSpacingMeters
        )

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
                    let contribution = craterletContribution(
                        eastMeters: eastMeters,
                        northMeters: northMeters,
                        crater: crater
                    )
                    let weight = samplingWeight(
                        featureSizeMeters: crater.diameterMeters,
                        sampleSpacingMeters: sampleSpacingMeters
                    )
                    relief += contribution.reliefMeters * weight
                    modulation += contribution.reflectanceDelta * weight
                }
            }
        }
        let limit = Self.maximumReliefMeters
        return (
            limit * tanh(relief / limit),
            min(max(1 + modulation, 0.78), 1.28)
        )
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

    private func craterletContribution(
        eastMeters: Double,
        northMeters: Double,
        crater: Craterlet
    ) -> (reliefMeters: Double, reflectanceDelta: Double) {
        let radius = crater.diameterMeters / 2
        let distance = hypot(
            eastMeters - crater.eastMeters,
            northMeters - crater.northMeters
        ) / radius
        var relief = 0.0
        if distance < 1.5 {
            let depth = crater.diameterMeters * (0.03 + crater.sharpness * 0.10)
            let rim = crater.diameterMeters * (0.006 + crater.sharpness * 0.022)
            if distance < 1 {
                relief -= depth * pow(1 - distance * distance, 1.1)
            }
            let rimDistance = (distance - 1) / 0.22
            relief += rim * exp(-rimDistance * rimDistance)
        }

        var reflectanceDelta = 0.0
        if distance < 2.2 {
            let freshness = crater.sharpness
            if distance < 0.85 {
                reflectanceDelta -= 0.05 * freshness * (0.85 - distance)
            } else {
                let halo = exp(-pow((distance - 1.0) / 0.75, 2))
                reflectanceDelta += 0.16 * freshness * halo
            }
        }
        return (relief, reflectanceDelta)
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

    /// Smoothly removes features that cannot be represented by the current
    /// texel footprint. This is the procedural equivalent of a mip filter:
    /// parent and child tiles retain the same low-frequency field, while only
    /// the child introduces newly resolvable craterlets and noise octaves.
    private func samplingWeight(
        featureSizeMeters: Double,
        sampleSpacingMeters: Double
    ) -> Double {
        guard sampleSpacingMeters > 0 else { return 1 }
        let samplesAcrossFeature = featureSizeMeters / sampleSpacingMeters
        let normalized = (samplesAcrossFeature - 1.5) / (4.0 - 1.5)
        return Self.smoothstep(normalized)
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
    var lunarField: LMLunarReflectanceField? = nil

    enum FieldError: Error, Equatable {
        case unsupportedFormat
        case missingResource(String)
    }

    /// Bilinear reflectance in 0...1, or nil outside the measured tile.
    func reflectance(eastMeters: Double, northMeters: Double) -> Float? {
        if let lunarField { return lunarField.reflectance(east: eastMeters, north: northMeters) }
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
        guard let space = image.colorSpace else {
            throw FieldError.unsupportedFormat
        }
        if space.numberOfComponents == 1 {
            var luminance = [UInt8](repeating: 0, count: width * height)
            try luminance.withUnsafeMutableBytes { raw in
                guard let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                ) else {
                    throw FieldError.unsupportedFormat
                }
                context.interpolationQuality = .none
                context.draw(
                    image,
                    in: CGRect(x: 0, y: 0, width: width, height: height)
                )
            }
            return LMMeasuredAlbedoField(
                width: width,
                height: height,
                halfExtentMeters: tile.extentMeters / 2,
                luminance: luminance
            )
        }
        guard space.numberOfComponents == 3 else {
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

/// Sun-independent distribution of the tangent-space normals baked into one
/// appearance tile. Keeping the distribution with the texture product lets a
/// later material realization evaluate mean rough-surface shading for any sun
/// direction without rebaking or making the cache sun-dependent.
struct LMTerrainNormalDistribution: Equatable, Sendable {
    static let azimuthBinCount = 12
    static let slopeBinCount = 8

    let sampleCount: Int
    let counts: [UInt32]
    let normalSums: [SIMD3<Float>]

    static let flat: LMTerrainNormalDistribution = {
        var accumulator = Accumulator()
        accumulator.add(SIMD3<Float>(0, 0, 1))
        return accumulator.finalized()
    }()

    /// Approximate mean clamped-Lambert response for a normalized sun vector
    /// expressed in the same tangent basis as the normal map.
    func meanLambertianResponse(
        sunDirectionTangentSpace: SIMD3<Float>
    ) -> Float {
        guard sampleCount > 0 else { return 0 }
        let sun = simd_normalize(sunDirectionTangentSpace)
        var total: Float = 0
        for index in counts.indices where counts[index] > 0 {
            let representative = simd_normalize(normalSums[index])
            total += max(simd_dot(representative, sun), 0)
                * Float(counts[index])
        }
        return total / Float(sampleCount)
    }

    struct Accumulator {
        private var counts = [UInt32](
            repeating: 0,
            count: azimuthBinCount * slopeBinCount
        )
        private var normalSums = [SIMD3<Float>](
            repeating: .zero,
            count: azimuthBinCount * slopeBinCount
        )
        private var sampleCount = 0

        mutating func add(_ normal: SIMD3<Float>) {
            let normalized = simd_normalize(normal)
            let slope = acos(min(max(normalized.z, 0), 1))
            let slopeFraction = slope / (.pi / 2)
            let slopeBin = min(
                Int(slopeFraction * Float(slopeBinCount)),
                slopeBinCount - 1
            )
            var azimuth = atan2(normalized.y, normalized.x)
            if azimuth < 0 { azimuth += 2 * .pi }
            let azimuthBin = min(
                Int(azimuth / (2 * .pi) * Float(azimuthBinCount)),
                azimuthBinCount - 1
            )
            let index = slopeBin * azimuthBinCount + azimuthBin
            counts[index] &+= 1
            normalSums[index] += normalized
            sampleCount += 1
        }

        func finalized() -> LMTerrainNormalDistribution {
            LMTerrainNormalDistribution(
                sampleCount: sampleCount,
                counts: counts,
                normalSums: normalSums
            )
        }
    }
}

/// Baked appearance textures for one progressive terrain tile.
struct LMTerrainTileDetailTextures: Sendable {
    let resolution: Int
    /// 8-bit RGBA, measured reflectance modulated by bounded micro-contrast.
    let albedo: [UInt8]
    /// 8-bit RGBA tangent-space normals for the sub-triangle micro-relief.
    let normal: [UInt8]
    let normalDistribution: LMTerrainNormalDistribution

    init(
        resolution: Int,
        albedo: [UInt8],
        normal: [UInt8],
        normalDistribution: LMTerrainNormalDistribution = .flat
    ) {
        self.resolution = resolution
        self.albedo = albedo
        self.normal = normal
        self.normalDistribution = normalDistribution
    }
}

/// Bakes the sub-triangle appearance of one clipmap tile.
///
/// Both textures use tile-local UVs, so the tile carries its own resampled
/// slice of the measured reflectance instead of sharing the 2 km near-field
/// atlas. That is what makes a second, world-scaled detail map unnecessary:
/// RealityKit's PBR materials expose only one texture-coordinate buffer.
enum LMTerrainTileDetailBaker {
    static let modelID = LMRegolithMicrotextureModel.modelID

    /// Convert centimetre-scale procedural relief into a restrained normal
    /// response. The relief field remains at physical scale for deterministic
    /// frequency matching, but realizing its full derivative in a tangent
    /// normal map overstates grazing-light contrast after per-tile mipmapping:
    /// distant 16 m tiles read as alternating dark cards. This factor affects
    /// appearance normals only. It cannot change measured terrain, rocks,
    /// contact, or the reflectance texture's preserved high-frequency detail.
    static let normalReliefScale = 0.30

    /// Texel budget per tile. A 16 m tile bakes at about 3 cm per texel and a
    /// 64 m tile at about 12 cm, for 1 MB of RGBA per texture.
    static let resolution = 512

    /// Neighboring tile edges are byte-identical, but a sampler at UV 0 or 1
    /// cannot see beyond its own texture. Give anisotropic filtering a small
    /// repeated-edge gutter and map the mesh to the original 512 texels inside
    /// it. The neural model and byte-bounded cache keep their 512 px contract;
    /// this padding exists only in the final GPU realization.
    static let samplingGutterTexels = 8
    static let renderingResolution = resolution + samplingGutterTexels * 2

    /// The bundled NAC height field is the last geometric parent in the
    /// progressive hierarchy. A child below this spacing hands appearance to
    /// another generated tile; the terminal 0.5 m tile hands directly to the
    /// measured material, which has no procedural relief or modulation.
    static let measuredGeometrySpacingMeters = 2.0

    /// The residency footprint's outer collar crossfades the complete child
    /// material into its live parent, mirroring the geometry's edge morph.
    /// Detail itself must remain full-strength through this collar. Fading the
    /// baked albedo and normal first and then fading the material a second time
    /// creates a visibly flat tonal band at grazing lunar-light angles.
    // The view/velocity-prefetched perimeter keeps the handoff outside the
    // inspected region. Confine frequency matching to its outer quarter so a
    // perimeter tile does not read as a full rectangular detail ramp.
    static let edgeFadeFraction = 0.25

    private struct RowBake: Sendable {
        let startRow: Int
        let rowCount: Int
        let albedo: [UInt8]
        let normal: [UInt8]
        let normalDistribution: LMTerrainNormalDistribution
    }

    nonisolated static func bake(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?,
        microtexture: LMRegolithMicrotextureModel = LMRegolithMicrotextureModel(),
        resolution: Int = resolution
    ) throws -> LMTerrainTileDetailTextures {
        // At this footprint every microtexture feature has exactly zero
        // sampling weight. Avoid allocating a sub-meter crater cache over a
        // regional tile that may span tens of kilometers.
        if plan.sizeMeters / Double(max(1, resolution - 1))
            >= LMRegolithMicrotextureModel.maximumCraterDiameterMeters / 1.5 {
            var albedo = [UInt8](repeating: 255, count: resolution * resolution * 4)
            var normal = albedo
            let half = plan.sizeMeters / 2
            let step = plan.sizeMeters / Double(max(1, resolution - 1))
            for row in 0..<resolution {
                try Task.checkCancellation()
                for column in 0..<resolution {
                    let value = albedoField?.reflectance(eastMeters: plan.centerEastMeters - half + Double(column) * step,
                                                        northMeters: plan.centerNorthMeters + half - Double(row) * step) ?? 0.25
                    let offset = (row * resolution + column) * 4
                    let byte = UInt8(min(1, max(0, value)) * 255)
                    albedo[offset] = byte; albedo[offset + 1] = byte; albedo[offset + 2] = byte
                    // Use the full baker's identical neutral encoding. 128
                    // versus its truncating 127 tilted coarse and fine normals
                    // in opposite directions, exposing LOD cards at low Sun.
                    normal[offset] = encode(0); normal[offset + 1] = encode(0)
                }
            }
            // The constant-normal shortcut still represents every texel.
            // A one-sample histogram underweights this tile in ensemble checks.
            let flat = LMTerrainNormalDistribution.flat
            let count = resolution * resolution
            let distribution = LMTerrainNormalDistribution(
                sampleCount: count, counts: flat.counts.map { $0 * UInt32(count) },
                normalSums: flat.normalSums.map { $0 * Float(count) })
            return LMTerrainTileDetailTextures(resolution: resolution, albedo: albedo, normal: normal,
                                              normalDistribution: distribution)
        }
        let craterlets = craterletField(
            plan: plan,
            microtexture: microtexture,
            resolution: resolution
        )
        let rows = try bakeRows(
            0..<resolution,
            plan: plan,
            albedoField: albedoField,
            microtexture: microtexture,
            craterlets: craterlets,
            resolution: resolution
        )
        return LMTerrainTileDetailTextures(
            resolution: resolution,
            albedo: rows.albedo,
            normal: rows.normal,
            normalDistribution: rows.normalDistribution
        )
    }

    nonisolated static func addingSamplingGutter(
        to detail: LMTerrainTileDetailTextures
    ) -> LMTerrainTileDetailTextures {
        guard detail.resolution == resolution,
              detail.albedo.count == resolution * resolution * 4,
              detail.normal.count == resolution * resolution * 4 else {
            return detail
        }
        return LMTerrainTileDetailTextures(
            resolution: renderingResolution,
            albedo: paddedRGBA(detail.albedo),
            normal: paddedRGBA(detail.normal),
            normalDistribution: detail.normalDistribution
        )
    }

    nonisolated static func renderingTextureCoordinate(
        contentFraction: Float
    ) -> Float {
        let contentIndex = contentFraction * Float(resolution - 1)
        return (Float(samplingGutterTexels) + contentIndex)
            / Float(renderingResolution - 1)
    }

    nonisolated private static func paddedRGBA(_ source: [UInt8]) -> [UInt8] {
        var result = [UInt8](
            repeating: 0,
            count: renderingResolution * renderingResolution * 4
        )
        for row in 0..<renderingResolution {
            let sourceRow = min(max(row - samplingGutterTexels, 0), resolution - 1)
            for column in 0..<renderingResolution {
                let sourceColumn = min(
                    max(column - samplingGutterTexels, 0),
                    resolution - 1
                )
                let sourceOffset = (sourceRow * resolution + sourceColumn) * 4
                let destinationOffset = (row * renderingResolution + column) * 4
                result[destinationOffset] = source[sourceOffset]
                result[destinationOffset + 1] = source[sourceOffset + 1]
                result[destinationOffset + 2] = source[sourceOffset + 2]
                result[destinationOffset + 3] = source[sourceOffset + 3]
            }
        }
        return result
    }

    private nonisolated static func craterletField(
        plan: LMTerrainTilePlan,
        microtexture: LMRegolithMicrotextureModel,
        resolution: Int
    ) -> LMRegolithCraterletField {
        let size = plan.sizeMeters
        let half = size / 2
        let texelSpacing = size / Double(max(resolution - 1, 1))
        let reach = half + texelSpacing
        return microtexture.craterletField(
            eastMetersRange: (plan.centerEastMeters - reach)...(plan.centerEastMeters + reach),
            northMetersRange: (plan.centerNorthMeters - reach)...(plan.centerNorthMeters + reach)
        )
    }

    private nonisolated static func bakeRows(
        _ rowRange: Range<Int>,
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?,
        microtexture: LMRegolithMicrotextureModel,
        craterlets: LMRegolithCraterletField,
        resolution: Int
    ) throws -> RowBake {
        let size = plan.sizeMeters
        let half = size / 2
        // UV 0 and 1 address the edge texels. Sampling the exact world-space
        // tile boundaries there makes neighboring tiles byte-identical at a
        // shared edge instead of clamping two different half-texel centers.
        let texelSpacing = size / Double(max(resolution - 1, 1))
        let rowCount = rowRange.count

        // One extra row and column so central differences at the last texel do
        // not have to clamp, which would flatten the tile's own border.
        let gridWidth = resolution + 2
        let gridHeight = rowCount + 2
        var relief = [Double](repeating: 0, count: gridWidth * gridHeight)
        var modulation = [Double](repeating: 1, count: rowCount * resolution)
        for localGridRow in 0..<gridHeight {
            try Task.checkCancellation()
            let globalGridRow = rowRange.lowerBound + localGridRow - 1
            let north = plan.centerNorthMeters + half
                - Double(globalGridRow) * texelSpacing
            for column in 0..<gridWidth {
                let east = plan.centerEastMeters - half
                    + Double(column - 1) * texelSpacing
                let transition = transitionWeight(
                    row: Double(globalGridRow),
                    column: Double(column - 1),
                    resolution: resolution,
                    edges: plan.transitionEdges
                )
                if localGridRow > 0, localGridRow <= rowCount,
                   column > 0, column <= resolution {
                    let fine = microtexture.appearanceSample(
                        eastMeters: east,
                        northMeters: north,
                        sampleSpacingMeters: texelSpacing,
                        craterlets: craterlets
                    )
                    let sample = parentMatchedSample(
                        fine,
                        transition: transition,
                        eastMeters: east,
                        northMeters: north,
                        parentSampleSpacingMeters:
                            parentAppearanceSampleSpacingMeters(
                                plan: plan,
                                texelSpacingMeters: texelSpacing
                            ),
                        microtexture: microtexture,
                        craterlets: craterlets
                    )
                    relief[localGridRow * gridWidth + column] = sample.reliefMeters
                    modulation[(localGridRow - 1) * resolution + column - 1] =
                        sample.reflectanceModulation
                } else {
                    let fine = microtexture.reliefMeters(
                        eastMeters: east,
                        northMeters: north,
                        sampleSpacingMeters: texelSpacing,
                        craterlets: craterlets
                    )
                    if transition >= 1 {
                        relief[localGridRow * gridWidth + column] = fine
                    } else {
                        let parent = parentAppearanceSampleSpacingMeters(
                            plan: plan,
                            texelSpacingMeters: texelSpacing
                        ).map {
                            microtexture.reliefMeters(
                                eastMeters: east,
                                northMeters: north,
                                sampleSpacingMeters: $0,
                                craterlets: craterlets
                            )
                        } ?? 0
                        relief[localGridRow * gridWidth + column] = parent
                            + (fine - parent) * transition
                    }
                }
            }
        }

        var albedo = [UInt8](repeating: 0, count: rowCount * resolution * 4)
        var normal = [UInt8](repeating: 0, count: rowCount * resolution * 4)
        var normalDistribution = LMTerrainNormalDistribution.Accumulator()

        for localRow in 0..<rowCount {
            try Task.checkCancellation()
            let row = rowRange.lowerBound + localRow
            let north = plan.centerNorthMeters + half - Double(row) * texelSpacing
            for column in 0..<resolution {
                let east = plan.centerEastMeters - half
                    + Double(column) * texelSpacing
                // Central differences on the padded relief grid. Row indices
                // run north to south, so a positive row step is southward.
                let gridIndex = (localRow + 1) * gridWidth + (column + 1)
                let eastSlope = (
                    relief[gridIndex + 1] - relief[gridIndex - 1]
                ) / (2 * texelSpacing) * normalReliefScale
                let northSlope = (
                    relief[gridIndex - gridWidth] - relief[gridIndex + gridWidth]
                ) / (2 * texelSpacing) * normalReliefScale

                // Mesh tangent basis for this grid: T is east (RealityKit -Z),
                // B is south (-X), N is up. Project the world normal
                // (-dh/dnorth, 1, dh/deast) onto it.
                let tangentSpace = simd_normalize(SIMD3<Float>(
                    Float(-eastSlope),
                    Float(northSlope),
                    1
                ))
                normalDistribution.add(tangentSpace)
                let normalOffset = (localRow * resolution + column) * 4
                normal[normalOffset] = encode(tangentSpace.x)
                normal[normalOffset + 1] = encode(tangentSpace.y)
                normal[normalOffset + 2] = encode(tangentSpace.z)
                normal[normalOffset + 3] = 255

                let measured = albedoField?.reflectance(
                    eastMeters: east,
                    northMeters: north
                ) ?? 0.25
                let appearanceModulation = modulation[
                    localRow * resolution + column
                ]
                let value = UInt8(
                    min(max(Double(measured) * appearanceModulation, 0), 1) * 255
                )
                let albedoOffset = (localRow * resolution + column) * 4
                albedo[albedoOffset] = value
                albedo[albedoOffset + 1] = value
                albedo[albedoOffset + 2] = value
                albedo[albedoOffset + 3] = 255
            }
        }

        return RowBake(
            startRow: rowRange.lowerBound,
            rowCount: rowCount,
            albedo: albedo,
            normal: normal,
            normalDistribution: normalDistribution.finalized()
        )
    }

    /// Match the next coarser level analytically through the footprint's outer
    /// collar. The child still fades as a complete material, but its albedo and
    /// normal field now approach the exact spatial-frequency band its parent
    /// can represent instead of approaching a flat texture. This keeps the
    /// collar neutral under grazing light and avoids a visible rectangular
    /// change in granularity.
    private nonisolated static func parentMatchedSample(
        _ fine: (reliefMeters: Double, reflectanceModulation: Double),
        transition: Double,
        eastMeters: Double,
        northMeters: Double,
        parentSampleSpacingMeters: Double?,
        microtexture: LMRegolithMicrotextureModel,
        craterlets: LMRegolithCraterletField
    ) -> (reliefMeters: Double, reflectanceModulation: Double) {
        guard transition < 1 else { return fine }
        let parent = parentSampleSpacingMeters.map {
            microtexture.appearanceSample(
                eastMeters: eastMeters,
                northMeters: northMeters,
                sampleSpacingMeters: $0,
                craterlets: craterlets
            )
        } ?? (reliefMeters: 0, reflectanceModulation: 1)
        return (
            parent.reliefMeters
                + (fine.reliefMeters - parent.reliefMeters) * transition,
            parent.reflectanceModulation
                + (fine.reflectanceModulation - parent.reflectanceModulation)
                    * transition
        )
    }

    /// Appearance is sampled more densely than geometry. When the live parent
    /// is another generated tile, match that tile's actual texel frequency
    /// (four times the child's world texel spacing), not its coarser mesh
    /// spacing. Once the next geometric parent is the measured NAC field,
    /// return `nil`: the exact parent appearance is measured reflectance with
    /// no invented microrelief.
    nonisolated static func parentAppearanceSampleSpacingMeters(
        plan: LMTerrainTilePlan,
        texelSpacingMeters: Double
    ) -> Double? {
        let parentGeometrySpacing = plan.sampleSpacingMeters * 4
        guard parentGeometrySpacing
                < measuredGeometrySpacingMeters - 1e-6 else {
            return nil
        }
        return texelSpacingMeters * 4
    }

    private nonisolated static func transitionWeight(
        row: Double,
        column: Double,
        resolution: Int,
        edges: LMTerrainTileEdges
    ) -> Double {
        guard !edges.isEmpty else { return 1 }
        let maximumIndex = Double(max(resolution - 1, 1))
        var distance = Double.greatestFiniteMagnitude
        if edges.contains(.west) { distance = min(distance, column) }
        if edges.contains(.east) { distance = min(distance, maximumIndex - column) }
        if edges.contains(.north) { distance = min(distance, row) }
        if edges.contains(.south) { distance = min(distance, maximumIndex - row) }
        let collar = max(1, maximumIndex * edgeFadeFraction)
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
