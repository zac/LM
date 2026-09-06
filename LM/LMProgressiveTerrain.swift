import Foundation

enum LMTerrainSampleProvenance: Equatable, Sendable {
    case measuredInterpolated
    case measuredWithProceduralSubresolution
}

struct LMResolvedTerrainSample: Equatable, Sendable {
    let measuredElevationMeters: Float
    let proceduralResidualMeters: Float
    let elevationMeters: Float
    let provenance: LMTerrainSampleProvenance
}

/// Resolves terrain without confusing synthesized micro-relief with measured topography.
///
/// The bundled LROC posts remain authoritative. Procedural residual is deterministic,
/// bounded, and exactly zero at every measured grid post. A future 0.5 m DTM can
/// therefore replace the current 2 m source without changing the renderer contract.
struct LMProgressiveTerrainSampler: Sendable {
    let heightField: any LMTerrainHeightField
    let geology: LMLunarGeologyModel
    let maximumResidualMeters: Float
    /// Optional memoization of the geology cells over a bounded work region.
    /// It changes nothing about the surface, only how often the hash runs.
    let craterField: LMLunarGeologyCraterField?

    init(
        heightField: any LMTerrainHeightField,
        seed: UInt64 = 0x4C_52_4F_43_41_31_31,
        maximumResidualMeters: Float = 0.24,
        craterCatalog: LMLunarCraterCatalog? = nil,
        craterField: LMLunarGeologyCraterField? = nil
    ) {
        self.heightField = heightField
        geology = LMLunarGeologyModel(
            seed: seed,
            craterCatalog: craterCatalog ?? heightField.craterCatalog
        )
        self.maximumResidualMeters = maximumResidualMeters
        self.craterField = craterField
    }

    /// A sampler that has precomputed the geology over one region.
    func prepared(
        eastMetersRange: ClosedRange<Double>,
        northMetersRange: ClosedRange<Double>
    ) -> LMProgressiveTerrainSampler {
        if heightField.resolvesProceduralSamples {
            return LMProgressiveTerrainSampler(
                heightField: heightField.prepared(eastMetersRange: eastMetersRange,
                                                  northMetersRange: northMetersRange),
                seed: geology.seed, maximumResidualMeters: maximumResidualMeters
            )
        }
        return LMProgressiveTerrainSampler(
            heightField: heightField,
            seed: geology.seed,
            maximumResidualMeters: maximumResidualMeters,
            craterCatalog: geology.craterCatalog,
            craterField: geology.craterField(
                eastMetersRange: eastMetersRange,
                northMetersRange: northMetersRange
            )
        )
    }

    func sample(
        eastMeters: Double,
        northMeters: Double,
        requestedSpacingMeters: Double
    ) -> LMResolvedTerrainSample? {
        if heightField.resolvesProceduralSamples {
            return heightField.resolvedSample(eastMeters: eastMeters, northMeters: northMeters,
                                             requestedSpacingMeters: requestedSpacingMeters)
        }
        guard let measured = heightField.relativeElevation(
            eastMeters: eastMeters,
            northMeters: northMeters
        ) else {
            return nil
        }

        let sourceSpacing = heightField.spacingMeters
        guard requestedSpacingMeters < sourceSpacing else {
            return LMResolvedTerrainSample(
                measuredElevationMeters: measured,
                proceduralResidualMeters: 0,
                elevationMeters: measured,
                provenance: .measuredInterpolated
            )
        }

        let detailFraction = Float(1 - requestedSpacingMeters / sourceSpacing)
        let unboundedResidual = anchoredResidual(
            eastMeters: eastMeters,
            northMeters: northMeters,
            requestedSpacingMeters: requestedSpacingMeters
        ) * Double(detailFraction)
        let limit = Double(maximumResidualMeters)
        let residual = Float(limit * tanh(unboundedResidual / limit))
        return LMResolvedTerrainSample(
            measuredElevationMeters: measured,
            proceduralResidualMeters: residual,
            elevationMeters: measured + residual,
            provenance: .measuredWithProceduralSubresolution
        )
    }

    /// Removes the bilinear interpolation of the unmeasured morphology at the
    /// four surrounding source posts. Unlike a sine envelope, this is continuous
    /// across source-cell boundaries while remaining exactly zero at every post.
    private func anchoredResidual(
        eastMeters: Double,
        northMeters: Double,
        requestedSpacingMeters: Double
    ) -> Double {
        let spacing = heightField.spacingMeters
        let halfWidth = Double(heightField.width - 1) * spacing / 2
        let halfDepth = Double(heightField.height - 1) * spacing / 2
        let column = (eastMeters + halfWidth) / spacing
        let row = (halfDepth - northMeters) / spacing
        let column0 = floor(column)
        let row0 = floor(row)
        let columnFraction = column - floor(column)
        let rowFraction = row - floor(row)
        let west = -halfWidth + column0 * spacing
        let north = halfDepth - row0 * spacing

        func raw(_ east: Double, _ north: Double) -> Double {
            geology.visualReliefMeters(
                eastMeters: east,
                northMeters: north,
                requestedSpacingMeters: requestedSpacingMeters,
                craterField: craterField
            )
        }

        let northwest = raw(west, north)
        let northeast = raw(west + spacing, north)
        let southwest = raw(west, north - spacing)
        let southeast = raw(west + spacing, north - spacing)
        let rawNorth = northwest + (northeast - northwest) * columnFraction
        let rawSouth = southwest + (southeast - southwest) * columnFraction
        let anchor = rawNorth + (rawSouth - rawNorth) * rowFraction
        return raw(eastMeters, northMeters) - anchor
    }
}

/// Deterministic morphology below the measured 2 m LROC sampling limit.
///
/// Surveyor observations constrain the cumulative small-crater size-frequency
/// slope to -2 from roughly 0.13...3 m. The exact feature locations, ages,
/// ellipticity, rim breakup, and ejecta below are synthesized and must never be
/// presented as surveyed Apollo 11 topography.
struct LMLunarGeologyModel: Equatable, Sendable {
    static let modelID = "surveyor-degraded-microrelief-v3"
    static let cumulativeCraterDiameterExponent = -2.0
    static let minimumCraterDiameterMeters = 0.22
    static let maximumCraterDiameterMeters = 1.2
    static let surveyorSourceURL =
        "https://www.usgs.gov/publications/physical-characteristics-lunar-regolith-determined-surveyor-television-observations"
    static let apollo11SourceURL =
        "https://ntrs.nasa.gov/api/citations/19700000726/downloads/19700000726.pdf"

    let seed: UInt64
    let craterCatalog: LMLunarCraterCatalog?
    private let craterCatalogIndex: LMLunarCraterCatalogIndex?
    let cellSizeMeters = 2.0
    let candidatesPerCell = 2
    /// Surveyor constrains the size-frequency slope but not a normalization for
    /// this exact site. Keep synthesized fresh/degraded bowls sparse enough that
    /// measured LROC morphology, not repeated circles, dominates the view.
    let candidateAcceptance = 0.18

    init(
        seed: UInt64 = 0x4C_52_4F_43_41_31_31,
        craterCatalog: LMLunarCraterCatalog? = nil
    ) {
        self.seed = seed
        self.craterCatalog = craterCatalog
        craterCatalogIndex = craterCatalog.map {
            LMLunarCraterCatalogIndex(catalog: $0)
        }
    }

    /// Includes the frozen detector version when a photo-derived catalog is
    /// active, so geometry caches cannot mix catalog realizations.
    var versionedModelID: String {
        guard let craterCatalog else { return Self.modelID }
        return "\(Self.modelID)+\(craterCatalog.versionedModelID)"
    }

    func visualReliefMeters(
        eastMeters: Double,
        northMeters: Double,
        requestedSpacingMeters: Double,
        craterField: LMLunarGeologyCraterField? = nil
    ) -> Double {
        let minimumRenderableDiameter = max(
            Self.minimumCraterDiameterMeters,
            requestedSpacingMeters * 2
        )
        let eastCell = Int64(floor(eastMeters / cellSizeMeters))
        let northCell = Int64(floor(northMeters / cellSizeMeters))
        var relief = regolithReliefMeters(
            eastMeters: eastMeters,
            northMeters: northMeters,
            requestedSpacingMeters: requestedSpacingMeters
        )

        if let craterCatalogIndex {
            for crater in craterCatalogIndex.cratersAffecting(
                eastMeters: eastMeters,
                northMeters: northMeters,
                minimumDiameterMeters: minimumRenderableDiameter
            ) {
                relief += Self.craterReliefMeters(
                    eastMeters: eastMeters,
                    northMeters: northMeters,
                    crater: crater
                )
            }
        }

        for northOffset in -1...1 {
            for eastOffset in -1...1 {
                let cellEast = eastCell + Int64(eastOffset)
                let cellNorth = northCell + Int64(northOffset)
                for candidate in 0..<candidatesPerCell {
                    guard let crater = resolvedCrater(
                        craterField,
                        cellEast: cellEast,
                        cellNorth: cellNorth,
                        candidate: candidate
                    ), crater.diameterMeters >= minimumRenderableDiameter else {
                        continue
                    }
                    relief += Self.craterReliefMeters(
                        eastMeters: eastMeters,
                        northMeters: northMeters,
                        crater: crater
                    )
                }
            }
        }
        return relief
    }

    /// A precomputed cell if the field covers it, otherwise the on-demand
    /// derivation. Both paths produce the same crater.
    func resolvedCrater(
        _ field: LMLunarGeologyCraterField?,
        cellEast: Int64,
        cellNorth: Int64,
        candidate: Int
    ) -> Crater? {
        let crater: Crater?
        if let field, let cached = field.crater(
            cellEast: cellEast,
            cellNorth: cellNorth,
            candidate: candidate
        ) {
            crater = cached
        } else {
            crater = self.crater(
                cellEast: cellEast,
                cellNorth: cellNorth,
                candidate: candidate
            )
        }
        guard let crater else { return nil }
        guard craterCatalogIndex?.overlapsHashCrater(crater) != true else { return nil }
        return crater
    }

    /// Precompute every candidate crater over a bounded region.
    ///
    /// Each sample otherwise re-derives the nine surrounding cells from the
    /// hash, and a single tile evaluates the relief field tens of thousands of
    /// times through the parent chain and the anchoring correction. The values
    /// are identical to the on-demand path; only the work is shared.
    func craterField(
        eastMetersRange: ClosedRange<Double>,
        northMetersRange: ClosedRange<Double>,
        haloCells: Int = 2
    ) -> LMLunarGeologyCraterField {
        let minimumEastCell = Int64(floor(eastMetersRange.lowerBound / cellSizeMeters))
            - Int64(haloCells)
        let maximumEastCell = Int64(floor(eastMetersRange.upperBound / cellSizeMeters))
            + Int64(haloCells)
        let minimumNorthCell = Int64(floor(northMetersRange.lowerBound / cellSizeMeters))
            - Int64(haloCells)
        let maximumNorthCell = Int64(floor(northMetersRange.upperBound / cellSizeMeters))
            + Int64(haloCells)
        let eastCount = Int(maximumEastCell - minimumEastCell) + 1
        let northCount = Int(maximumNorthCell - minimumNorthCell) + 1

        var craters = [Crater?]()
        craters.reserveCapacity(eastCount * northCount * candidatesPerCell)
        for northIndex in 0..<northCount {
            for eastIndex in 0..<eastCount {
                for candidate in 0..<candidatesPerCell {
                    craters.append(crater(
                        cellEast: minimumEastCell + Int64(eastIndex),
                        cellNorth: minimumNorthCell + Int64(northIndex),
                        candidate: candidate
                    ))
                }
            }
        }
        return LMLunarGeologyCraterField(
            minimumEastCell: minimumEastCell,
            minimumNorthCell: minimumNorthCell,
            eastCellCount: eastCount,
            northCellCount: northCount,
            candidatesPerCell: candidatesPerCell,
            craters: craters
        )
    }

    struct Crater: Equatable, Sendable {
        let eastMeters: Double
        let northMeters: Double
        let diameterMeters: Double
        let aspectRatio: Double
        let rotationRadians: Double
        let sharpness: Double
        let rimPhase: Double
        let rimLobes: Int
        let ejectaPhase: Double
    }

    func crater(
        cellEast: Int64,
        cellNorth: Int64,
        candidate: Int
    ) -> Crater? {
        guard unit(cellEast, cellNorth, candidate, 0) < candidateAcceptance else {
            return nil
        }
        let minimumInverseSquare = 1 / pow(Self.minimumCraterDiameterMeters, 2)
        let maximumInverseSquare = 1 / pow(Self.maximumCraterDiameterMeters, 2)
        let diameterDraw = unit(cellEast, cellNorth, candidate, 3)
        let diameter = 1 / sqrt(
            minimumInverseSquare
                - diameterDraw * (minimumInverseSquare - maximumInverseSquare)
        )
        return Crater(
            eastMeters: (Double(cellEast) + unit(cellEast, cellNorth, candidate, 1))
                * cellSizeMeters,
            northMeters: (Double(cellNorth) + unit(cellEast, cellNorth, candidate, 2))
                * cellSizeMeters,
            diameterMeters: diameter,
            aspectRatio: 0.76 + unit(cellEast, cellNorth, candidate, 4) * 0.24,
            rotationRadians: unit(cellEast, cellNorth, candidate, 5) * 2 * .pi,
            sharpness: 0.08 + unit(cellEast, cellNorth, candidate, 6) * 0.48,
            rimPhase: unit(cellEast, cellNorth, candidate, 7) * 2 * .pi,
            rimLobes: 3 + Int(unit(cellEast, cellNorth, candidate, 8) * 5),
            ejectaPhase: unit(cellEast, cellNorth, candidate, 9) * 2 * .pi
        )
    }

    static func craterReliefMeters(
        eastMeters: Double,
        northMeters: Double,
        crater: Crater
    ) -> Double {
        let eastDelta = eastMeters - crater.eastMeters
        let northDelta = northMeters - crater.northMeters
        let cosine = cos(crater.rotationRadians)
        let sine = sin(crater.rotationRadians)
        let localX = eastDelta * cosine + northDelta * sine
        let localY = (-eastDelta * sine + northDelta * cosine) / crater.aspectRatio
        let radius = crater.diameterMeters / 2
        let normalizedRadius = sqrt(localX * localX + localY * localY) / radius
        guard normalizedRadius < 1.65 else { return 0 }

        let angle = atan2(localY, localX)
        let depth = crater.diameterMeters * (0.025 + crater.sharpness * 0.060)
        let rimHeight = crater.diameterMeters * (0.006 + crater.sharpness * 0.014)
        let rimBreakup = 0.78 + 0.22 * sin(
            Double(crater.rimLobes) * angle + crater.rimPhase
        )

        var relief = 0.0
        if normalizedRadius < 1 {
            let bowl = 1 - normalizedRadius * normalizedRadius
            relief -= depth * pow(bowl, 1.15)
        }

        let rimWidth = 0.10 + (1 - crater.sharpness) * 0.16
        let rimDistance = (normalizedRadius - 1) / rimWidth
        relief += rimHeight * exp(-rimDistance * rimDistance) * rimBreakup

        if normalizedRadius > 1 {
            let ejectaDistance = (normalizedRadius - 1) / 0.65
            let ejectaEnvelope = smoothstep(1 - ejectaDistance)
            let rays = 0.45 + 0.55 * pow(
                0.5 + 0.5 * cos(5 * angle + crater.ejectaPhase),
                3
            )
            relief += crater.diameterMeters * 0.0035 * crater.sharpness
                * ejectaEnvelope * rays
        }
        return relief
    }

    /// Continuous, deterministic regolith relief prevents sub-resolution
    /// detail from reading as a field of stamped crater decals. It is strictly
    /// visual synthesis; `LMProgressiveTerrainSampler` subtracts its bilinear
    /// value at each measured post, preserving every LROC datum exactly.
    private func regolithReliefMeters(
        eastMeters: Double,
        northMeters: Double,
        requestedSpacingMeters: Double
    ) -> Double {
        guard requestedSpacingMeters <= 0.5 else { return 0 }
        var relief = valueNoise(
            eastMeters: eastMeters,
            northMeters: northMeters,
            wavelengthMeters: 1.1,
            property: 31
        ) * 0.014
        if requestedSpacingMeters <= 0.25 {
            relief += valueNoise(
                eastMeters: eastMeters,
                northMeters: northMeters,
                wavelengthMeters: 0.34,
                property: 47
            ) * 0.0045
        }
        return relief
    }

    private func valueNoise(
        eastMeters: Double,
        northMeters: Double,
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
        let northValue = northwest + (northeast - northwest) * eastBlend
        let southValue = southwest + (southeast - southwest) * eastBlend
        return northValue + (southValue - northValue) * northBlend
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
        return Double(value & 0x001F_FFFF_FFFF_FFFF)
            / Double(0x0020_0000_0000_0000)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

/// Craters precomputed over a bounded block of generator cells.
///
/// Outside the block the lookup returns `nil` twice over: it cannot tell
/// "no crater" from "not covered", so callers fall back to the model's
/// on-demand derivation, which produces the same values.
struct LMLunarGeologyCraterField: Sendable {
    let minimumEastCell: Int64
    let minimumNorthCell: Int64
    let eastCellCount: Int
    let northCellCount: Int
    let candidatesPerCell: Int
    let craters: [LMLunarGeologyModel.Crater?]

    func covers(cellEast: Int64, cellNorth: Int64) -> Bool {
        cellEast >= minimumEastCell
            && cellNorth >= minimumNorthCell
            && cellEast < minimumEastCell + Int64(eastCellCount)
            && cellNorth < minimumNorthCell + Int64(northCellCount)
    }

    func crater(
        cellEast: Int64,
        cellNorth: Int64,
        candidate: Int
    ) -> LMLunarGeologyModel.Crater?? {
        guard covers(cellEast: cellEast, cellNorth: cellNorth) else { return nil }
        let eastIndex = Int(cellEast - minimumEastCell)
        let northIndex = Int(cellNorth - minimumNorthCell)
        let offset = (northIndex * eastCellCount + eastIndex) * candidatesPerCell + candidate
        return .some(craters[offset])
    }
}

struct LMTerrainTileID: Hashable, Sendable {
    let level: Int
    let eastIndex: Int
    let northIndex: Int
}

/// Edges where a fine terrain footprint meets its coarser parent.
///
/// Adjacent tiles at the same level deliberately omit their shared edge. This
/// lets a residency footprint behave as one continuous clipmap patch while
/// retaining the parent morph only around the outside perimeter.
struct LMTerrainTileEdges: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    static let west = Self(rawValue: 1 << 0)
    static let east = Self(rawValue: 1 << 1)
    static let south = Self(rawValue: 1 << 2)
    static let north = Self(rawValue: 1 << 3)
    static let all: Self = [.west, .east, .south, .north]
}

struct LMTerrainTilePlan: Equatable, Sendable {
    let id: LMTerrainTileID
    let centerEastMeters: Double
    let centerNorthMeters: Double
    let sizeMeters: Double
    let sampleSpacingMeters: Double
    let containsProceduralSubresolution: Bool
    let transitionEdges: LMTerrainTileEdges

    init(
        id: LMTerrainTileID,
        centerEastMeters: Double,
        centerNorthMeters: Double,
        sizeMeters: Double,
        sampleSpacingMeters: Double,
        containsProceduralSubresolution: Bool,
        transitionEdges: LMTerrainTileEdges = .all
    ) {
        self.id = id
        self.centerEastMeters = centerEastMeters
        self.centerNorthMeters = centerNorthMeters
        self.sizeMeters = sizeMeters
        self.sampleSpacingMeters = sampleSpacingMeters
        self.containsProceduralSubresolution = containsProceduralSubresolution
        self.transitionEdges = transitionEdges
    }

    func withTransitionEdges(_ transitionEdges: LMTerrainTileEdges) -> Self {
        Self(
            id: id,
            centerEastMeters: centerEastMeters,
            centerNorthMeters: centerNorthMeters,
            sizeMeters: sizeMeters,
            sampleSpacingMeters: sampleSpacingMeters,
            containsProceduralSubresolution: containsProceduralSubresolution,
            transitionEdges: transitionEdges
        )
    }
}

/// Selects only the sub-resolution detail that can contribute at the current
/// flight altitude. Measured source geometry remains present at every altitude.
struct LMTerrainDetailPolicy: Equatable, Sendable {
    var globalBands = false
    let approachAltitudeMeters: Double
    let terminalAltitudeMeters: Double
    let landingAltitudeMeters: Double
    let landingPresentationBlendStartAltitudeMeters: Double
    let landingPresentationBlendEndAltitudeMeters: Double
    let approachSpacingMeters: Double
    let terminalSpacingMeters: Double
    let landingSpacingMeters: Double

    init(
        approachAltitudeMeters: Double = 2_500,
        terminalAltitudeMeters: Double = 250,
        landingAltitudeMeters: Double = 60,
        landingPresentationBlendStartAltitudeMeters: Double = 40,
        landingPresentationBlendEndAltitudeMeters: Double = 25,
        approachSpacingMeters: Double = 2,
        terminalSpacingMeters: Double = 0.5,
        landingSpacingMeters: Double = 0.125
    ) {
        self.approachAltitudeMeters = approachAltitudeMeters
        self.terminalAltitudeMeters = terminalAltitudeMeters
        self.landingAltitudeMeters = landingAltitudeMeters
        self.landingPresentationBlendStartAltitudeMeters =
            landingPresentationBlendStartAltitudeMeters
        self.landingPresentationBlendEndAltitudeMeters =
            landingPresentationBlendEndAltitudeMeters
        self.approachSpacingMeters = approachSpacingMeters
        self.terminalSpacingMeters = terminalSpacingMeters
        self.landingSpacingMeters = landingSpacingMeters
    }

    func finestSpacingMeters(altitudeMeters: Double) -> Double? {
        if altitudeMeters <= landingAltitudeMeters {
            return landingSpacingMeters
        }
        if altitudeMeters <= terminalAltitudeMeters {
            return terminalSpacingMeters
        }
        if altitudeMeters <= approachAltitudeMeters {
            return approachSpacingMeters
        }
        if globalBands {
            if altitudeMeters <= 10_000 { return 8 }
            if altitudeMeters <= 40_000 { return 32 }
            if altitudeMeters <= 160_000 { return 128 }
            return 512
        }
        return nil
    }

    /// The landing tile is resident before it contributes to the cockpit datum.
    /// This gives asynchronous generation twenty meters of descent margin and
    /// prevents a late tile from moving the lunar world at its load instant.
    func presentationBlend(
        sampleSpacingMeters: Double,
        altitudeMeters: Double
    ) -> Double {
        guard abs(sampleSpacingMeters - landingSpacingMeters) < 1e-6 else {
            return 1
        }
        let span = landingPresentationBlendStartAltitudeMeters
            - landingPresentationBlendEndAltitudeMeters
        guard span > 0 else { return 1 }
        let progress = (
            landingPresentationBlendStartAltitudeMeters - altitudeMeters
        ) / span
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

/// Stable clipmap planning around the vehicle. The plan is renderer-independent so
/// tiles can later be generated by RealityKit meshes, Metal tessellation, or streamed USD.
struct LMProgressiveTerrainPlanner: Sendable {
    static let globalLevels: [Level] = [
        .init(tileSizeMeters: 64, sampleSpacingMeters: 0.5, radiusInTiles: 2),
        .init(tileSizeMeters: 16, sampleSpacingMeters: 0.125, radiusInTiles: 2),
        .init(tileSizeMeters: 256, sampleSpacingMeters: 2, radiusInTiles: 2),
        .init(tileSizeMeters: 1_024, sampleSpacingMeters: 8, radiusInTiles: 2),
        .init(tileSizeMeters: 4_096, sampleSpacingMeters: 32, radiusInTiles: 2),
        .init(tileSizeMeters: 16_384, sampleSpacingMeters: 128, radiusInTiles: 2),
        .init(tileSizeMeters: 65_536, sampleSpacingMeters: 512, radiusInTiles: 2),
    ]
    private static let spacingToleranceMeters = 1e-6

    struct Level: Equatable, Sendable {
        let tileSizeMeters: Double
        let sampleSpacingMeters: Double
        let radiusInTiles: Int
    }

    let levels: [Level]
    let sourceSpacingMeters: Double

    init(
        sourceSpacingMeters: Double,
        levels: [Level] = [
            .init(tileSizeMeters: 64, sampleSpacingMeters: 0.5, radiusInTiles: 2),
            .init(tileSizeMeters: 16, sampleSpacingMeters: 0.125, radiusInTiles: 2),
            .init(tileSizeMeters: 256, sampleSpacingMeters: 2, radiusInTiles: 2),
            .init(tileSizeMeters: 1_024, sampleSpacingMeters: 8, radiusInTiles: 2),
            .init(tileSizeMeters: 4_096, sampleSpacingMeters: 32, radiusInTiles: 2),
        ]
    ) {
        self.sourceSpacingMeters = sourceSpacingMeters
        self.levels = levels
    }

    func plan(focusEastMeters: Double, focusNorthMeters: Double) -> [LMTerrainTilePlan] {
        let plans = levels.enumerated().flatMap { levelIndex, level in
            let focusEastIndex = Int(floor(focusEastMeters / level.tileSizeMeters))
            let focusNorthIndex = Int(floor(focusNorthMeters / level.tileSizeMeters))
            return (-level.radiusInTiles...level.radiusInTiles).flatMap { northOffset in
                (-level.radiusInTiles...level.radiusInTiles).map { eastOffset in
                    let eastIndex = focusEastIndex + eastOffset
                    let northIndex = focusNorthIndex + northOffset
                    return LMTerrainTilePlan(
                        id: .init(
                            level: levelIndex,
                            eastIndex: eastIndex,
                            northIndex: northIndex
                        ),
                        centerEastMeters: (Double(eastIndex) + 0.5) * level.tileSizeMeters,
                        centerNorthMeters: (Double(northIndex) + 0.5) * level.tileSizeMeters,
                        sizeMeters: level.tileSizeMeters,
                        sampleSpacingMeters: level.sampleSpacingMeters,
                        containsProceduralSubresolution: level.sampleSpacingMeters
                            < sourceSpacingMeters - Self.spacingToleranceMeters
                    )
                }
            }
        }
        return applyingFootprintPerimeter(to: plans)
    }

    /// A compact safety footprint per useful detail level. Keeping only the
    /// tile containing the vehicle put Eagle within roughly one footpad radius
    /// of two landing-tile edges, so the level's outer morph collar was visible
    /// through the window and could split the gear across two LODs. The bounded
    /// footprint below requests adjacent tiles only when the inspection/contact
    /// radius reaches an edge. It normally retains two to six tiles across the
    /// active levels instead of a fixed 3x3 neighborhood.
    func focusedPlans(
        focusEastMeters: Double,
        focusNorthMeters: Double,
        altitudeMeters: Double,
        policy: LMTerrainDetailPolicy = .init()
    ) -> [LMTerrainTilePlan] {
        guard let finestSpacing = policy.finestSpacingMeters(
            altitudeMeters: altitudeMeters
        ) else {
            return []
        }

        let coverageRadii = coverageRadiiMeters(finestSpacing: finestSpacing)
        let plans = levels.enumerated().flatMap { levelIndex, level in
            guard let coverageRadius = coverageRadii[levelIndex] else {
                return [LMTerrainTilePlan]()
            }
            let epsilon = Self.spacingToleranceMeters
            let minimumEastIndex = Int(floor(
                (focusEastMeters - coverageRadius + epsilon) / level.tileSizeMeters
            ))
            let maximumEastIndex = Int(floor(
                (focusEastMeters + coverageRadius - epsilon) / level.tileSizeMeters
            ))
            let minimumNorthIndex = Int(floor(
                (focusNorthMeters - coverageRadius + epsilon) / level.tileSizeMeters
            ))
            let maximumNorthIndex = Int(floor(
                (focusNorthMeters + coverageRadius - epsilon) / level.tileSizeMeters
            ))
            return (minimumNorthIndex...maximumNorthIndex).flatMap { northIndex in
                (minimumEastIndex...maximumEastIndex).map { eastIndex in
                    LMTerrainTilePlan(
                        id: .init(
                            level: levelIndex,
                            eastIndex: eastIndex,
                            northIndex: northIndex
                        ),
                        centerEastMeters: (Double(eastIndex) + 0.5)
                            * level.tileSizeMeters,
                        centerNorthMeters: (Double(northIndex) + 0.5)
                            * level.tileSizeMeters,
                        sizeMeters: level.tileSizeMeters,
                        sampleSpacingMeters: level.sampleSpacingMeters,
                        containsProceduralSubresolution: true
                    )
                }
            }
        }
        return applyingFootprintPerimeter(to: plans)
    }

    /// Sixteen meters encloses the 9.4 m LM gear footprint and keeps the landing
    /// level's forward handoff outside the oblique cockpit/explorer ground view.
    /// At Eagle, a 12 m radius ended only 12.4 m north of the focus and exposed
    /// the landing-to-terminal appearance falloff in the surface preset. The
    /// larger radius adds one 16 m row there while remaining inside the 32 MB
    /// detail-cache working set.
    /// The terminal level gets a wider collar because it is visible over a
    /// larger footprint. A landing focus normally retains a 3x3 set of nine
    /// tiles instead of exposing a 16 m tile boundary inside the inspected
    /// region.
    ///
    /// Every coarser active level must additionally enclose the finer level's
    /// footprint by at least its own outer morph collar. Equal radii left the
    /// nesting to tile quantization: whenever the focus sat near a 64 m
    /// boundary, the terminal and landing footprints ended on the same line,
    /// stacking both collars there so the full sub-source relief and detail
    /// handed off to the bare 2 m mesh across a single 4 m band. Tile-tint
    /// residency captures show exactly that landing-to-nothing edge as the
    /// strongest rectangular card in the surface preset.
    private func coverageRadiiMeters(finestSpacing: Double) -> [Int: Double] {
        let active = levels.enumerated()
            .filter { _, level in
                level.sampleSpacingMeters >= finestSpacing
                    && level.sampleSpacingMeters
                        < sourceSpacingMeters - Self.spacingToleranceMeters
            }
            .sorted { $0.element.sampleSpacingMeters < $1.element.sampleSpacingMeters }
        var radii = [Int: Double]()
        var finerRadius: Double?
        for (position, entry) in active.enumerated() {
            let level = entry.element
            let base = min(
                level.tileSizeMeters,
                max(16, level.sampleSpacingMeters * 32)
            )
            var radius = base
            if let finerRadius {
                // Mirror the renderer's morph width for this level: its parent
                // is the next coarser active level, or the measured source.
                let parentSpacing = position + 1 < active.count
                    ? active[position + 1].element.sampleSpacingMeters
                    : sourceSpacingMeters
                let morphWidth = min(
                    level.tileSizeMeters / 4,
                    parentSpacing * 8
                )
                radius = max(base, finerRadius + morphWidth)
            }
            radii[entry.offset] = radius
            finerRadius = radius
        }
        return radii
    }

    /// Keeps both the current safety footprint and the six-second projected
    /// footprint resident. Their overlap normally makes this much smaller than
    /// two complete neighborhoods while removing the parent-only gap observed
    /// when generation began after a 16 m boundary crossing.
    func prefetchedPlans(
        focusEastMeters: Double,
        focusNorthMeters: Double,
        velocityEastMetersPerSecond: Double,
        velocityNorthMetersPerSecond: Double,
        altitudeMeters: Double,
        lookaheadSeconds: Double = 6,
        policy: LMTerrainDetailPolicy = .init()
    ) -> [LMTerrainTilePlan] {
        let current = focusedPlans(
            focusEastMeters: focusEastMeters,
            focusNorthMeters: focusNorthMeters,
            altitudeMeters: altitudeMeters,
            policy: policy
        )
        let predicted = focusedPlans(
            focusEastMeters: focusEastMeters
                + velocityEastMetersPerSecond * lookaheadSeconds,
            focusNorthMeters: focusNorthMeters
                + velocityNorthMetersPerSecond * lookaheadSeconds,
            altitudeMeters: altitudeMeters,
            policy: policy
        )
        return mergedPlans(current + predicted)
    }

    /// Keeps a continuous, view-aligned inspection corridor resident.
    ///
    /// Explorer has no vehicle velocity, but its oblique camera can see well
    /// beyond the compact contact footprint around the selected point. Merely
    /// requesting the start and end footprints leaves a parent-only gap when
    /// they are farther apart than one tile. Sampling at the finest active
    /// tile width keeps the union contiguous while bounding the number of
    /// generated tiles.
    func viewCorridorPlans(
        focusEastMeters: Double,
        focusNorthMeters: Double,
        headingDegrees: Double,
        forwardDistanceMeters: Double,
        altitudeMeters: Double,
        policy: LMTerrainDetailPolicy = .init()
    ) -> [LMTerrainTilePlan] {
        guard forwardDistanceMeters > 0,
              let finestSpacing = policy.finestSpacingMeters(
                  altitudeMeters: altitudeMeters
              ),
              let finestLevel = levels.first(where: {
                  abs($0.sampleSpacingMeters - finestSpacing)
                      < Self.spacingToleranceMeters
              }) else {
            return focusedPlans(
                focusEastMeters: focusEastMeters,
                focusNorthMeters: focusNorthMeters,
                altitudeMeters: altitudeMeters,
                policy: policy
            )
        }
        let sampleCount = max(
            1,
            Int(ceil(forwardDistanceMeters / finestLevel.tileSizeMeters))
        )
        let heading = headingDegrees * .pi / 180
        let eastDirection = cos(heading)
        let northDirection = sin(heading)
        let samples = (0...sampleCount).flatMap { index in
            let fraction = Double(index) / Double(sampleCount)
            let distance = forwardDistanceMeters * fraction
            return focusedPlans(
                focusEastMeters: focusEastMeters + eastDirection * distance,
                focusNorthMeters: focusNorthMeters + northDirection * distance,
                altitudeMeters: altitudeMeters,
                policy: policy
            )
        }
        return mergedPlans(samples)
    }

    /// Merges independently projected residency samples into one continuous
    /// footprint, then assigns transition ownership only at its final outer
    /// edge. Explorer uses this for a view corridor; descent uses the same
    /// operation for current and projected vehicle positions.
    func mergedPlans(_ plans: [LMTerrainTilePlan]) -> [LMTerrainTilePlan] {
        var seen = Set<LMTerrainTileID>()
        let union = plans.filter { seen.insert($0.id).inserted }
        return applyingFootprintPerimeter(to: union)
    }

    /// The edge-only collar encoding describes a rectangle. A stepped union
    /// can end one tile's collar at an internal corner while its neighbor has
    /// full relief there. Close each global footprint into a rectangle, and
    /// enclose the quantized child extent before assigning any edge masks.
    /// Apollo callers retain their established planning and cache keys.
    func rectangularPlansEnclosingChildren(_ plans: [LMTerrainTilePlan]) -> [LMTerrainTilePlan] {
        let groups = Dictionary(grouping: plans, by: { $0.id.level }).values.sorted {
            $0[0].sampleSpacingMeters < $1[0].sampleSpacingMeters
        }
        var result = [LMTerrainTilePlan]()
        var childBounds: (west: Double, east: Double, south: Double, north: Double)?
        for (index, group) in groups.enumerated() {
            let sample = group[0], size = sample.sizeMeters
            var west = group.map(\.id.eastIndex).min()!
            var east = group.map(\.id.eastIndex).max()!
            var south = group.map(\.id.northIndex).min()!
            var north = group.map(\.id.northIndex).max()!
            if let childBounds {
                let parentSpacing = index + 1 < groups.count ? groups[index + 1][0].sampleSpacingMeters : sourceSpacingMeters
                let collar = min(size / 4, parentSpacing * 8)
                west = min(west, Int(floor((childBounds.west - collar) / size)))
                east = max(east, Int(ceil((childBounds.east + collar) / size)) - 1)
                south = min(south, Int(floor((childBounds.south - collar) / size)))
                north = max(north, Int(ceil((childBounds.north + collar) / size)) - 1)
            }
            for n in south...north {
                for e in west...east {
                    result.append(.init(id: .init(level: sample.id.level, eastIndex: e, northIndex: n),
                                        centerEastMeters: (Double(e) + 0.5) * size,
                                        centerNorthMeters: (Double(n) + 0.5) * size,
                                        sizeMeters: size, sampleSpacingMeters: sample.sampleSpacingMeters,
                                        containsProceduralSubresolution: sample.containsProceduralSubresolution))
                }
            }
            childBounds = (Double(west) * size, Double(east + 1) * size,
                           Double(south) * size, Double(north + 1) * size)
        }
        return applyingFootprintPerimeter(to: result)
    }

    /// Recomputes edge ownership after the final residency set is known. This
    /// is particularly important for prefetching: the current and projected
    /// footprints may overlap or touch, and their union must have one outer
    /// perimeter rather than two independent fade collars.
    private func applyingFootprintPerimeter(
        to plans: [LMTerrainTilePlan]
    ) -> [LMTerrainTilePlan] {
        let residentIDs = Set(plans.map(\.id))
        return plans.map { plan in
            let id = plan.id
            var edges: LMTerrainTileEdges = []
            if !residentIDs.contains(.init(
                level: id.level,
                eastIndex: id.eastIndex - 1,
                northIndex: id.northIndex
            )) {
                edges.insert(.west)
            }
            if !residentIDs.contains(.init(
                level: id.level,
                eastIndex: id.eastIndex + 1,
                northIndex: id.northIndex
            )) {
                edges.insert(.east)
            }
            if !residentIDs.contains(.init(
                level: id.level,
                eastIndex: id.eastIndex,
                northIndex: id.northIndex - 1
            )) {
                edges.insert(.south)
            }
            if !residentIDs.contains(.init(
                level: id.level,
                eastIndex: id.eastIndex,
                northIndex: id.northIndex + 1
            )) {
                edges.insert(.north)
            }
            return plan.withTransitionEdges(edges)
        }
    }
}

struct LMTerrainSurfaceSample: Equatable, Sendable {
    let measuredElevationMeters: Float
    let renderedElevationMeters: Float
    let presentationElevationMeters: Float
    let sampleSpacingMeters: Double?
    let presentationBlend: Double
}

/// Evaluates the exact hierarchical surface used by progressive terrain meshes.
///
/// Every level contributes only its new spatial band and morphs that band to
/// zero at its own tile edge. Recursing through the actual parent tile makes a
/// child boundary identical to the parent mesh, including where child and
/// parent boundaries coincide. The same evaluator drives cockpit datum and
/// dust placement, so presentation cannot drift from the rendered mesh.
struct LMProgressiveTerrainSurfaceSampler: Sendable {
    private static let spacingToleranceMeters = 1e-6

    let heightField: any LMTerrainHeightField
    let planner: LMProgressiveTerrainPlanner
    let terrainSampler: LMProgressiveTerrainSampler

    init(
        heightField: any LMTerrainHeightField,
        planner: LMProgressiveTerrainPlanner? = nil,
        terrainSampler: LMProgressiveTerrainSampler? = nil
    ) {
        self.heightField = heightField
        self.planner = planner ?? LMProgressiveTerrainPlanner(
            sourceSpacingMeters: heightField.spacingMeters
        )
        self.terrainSampler = terrainSampler
            ?? LMProgressiveTerrainSampler(heightField: heightField)
    }

    /// A sampler that has precomputed the geology over one tile, including the
    /// margin its parent chain and post-anchoring correction reach into.
    func prepared(for plan: LMTerrainTilePlan) -> LMProgressiveTerrainSurfaceSampler {
        let margin = heightField.spacingMeters * 2
        let reach = plan.sizeMeters / 2 + margin
        let eastRange = (plan.centerEastMeters - reach)...(plan.centerEastMeters + reach)
        let northRange = (plan.centerNorthMeters - reach)...(plan.centerNorthMeters + reach)
        return LMProgressiveTerrainSurfaceSampler(
            heightField: heightField,
            planner: planner,
            terrainSampler: terrainSampler.prepared(
                eastMetersRange: eastRange,
                northMetersRange: northRange
            )
        )
    }

    func sample(
        eastMeters: Double,
        northMeters: Double,
        altitudeMeters: Double,
        activePlans: [LMTerrainTilePlan],
        policy: LMTerrainDetailPolicy = .init()
    ) -> LMTerrainSurfaceSample? {
        guard let measured = heightField.relativeElevation(
            eastMeters: eastMeters,
            northMeters: northMeters
        ) else {
            return nil
        }
        guard let finestPlan = activePlans
            .filter({ contains($0, eastMeters: eastMeters, northMeters: northMeters) })
            .min(by: { $0.sampleSpacingMeters < $1.sampleSpacingMeters }) else {
            return LMTerrainSurfaceSample(
                measuredElevationMeters: measured,
                renderedElevationMeters: measured,
                presentationElevationMeters: measured,
                sampleSpacingMeters: nil,
                presentationBlend: 1
            )
        }
        guard let rendered = renderedElevation(
            eastMeters: eastMeters,
            northMeters: northMeters,
            plan: finestPlan,
            activePlans: activePlans
        ) else {
            return nil
        }

        let blend = policy.presentationBlend(
            sampleSpacingMeters: finestPlan.sampleSpacingMeters,
            altitudeMeters: altitudeMeters
        )
        let parent = parentPlan(
            for: finestPlan,
            eastMeters: eastMeters,
            northMeters: northMeters,
            activePlans: activePlans
        ).flatMap {
            renderedElevation(
                eastMeters: eastMeters,
                northMeters: northMeters,
                plan: $0,
                activePlans: activePlans
            )
        } ?? measured
        let presentation = parent + (rendered - parent) * Float(blend)
        return LMTerrainSurfaceSample(
            measuredElevationMeters: measured,
            renderedElevationMeters: rendered,
            presentationElevationMeters: presentation,
            sampleSpacingMeters: finestPlan.sampleSpacingMeters,
            presentationBlend: blend
        )
    }

    func renderedElevation(
        eastMeters: Double,
        northMeters: Double,
        plan: LMTerrainTilePlan,
        activePlans: [LMTerrainTilePlan]? = nil
    ) -> Float? {
        renderedElevationSample(
            eastMeters: eastMeters,
            northMeters: northMeters,
            plan: plan,
            activePlans: activePlans
        )?.elevationMeters
    }

    /// Returns both the complete hierarchical surface and the exact height
    /// band introduced by this plan relative to its live parent. The latter is
    /// sun-independent and is the geometry-side input to radiance-conserving
    /// LOD statistics.
    func renderedElevationSample(
        eastMeters: Double,
        northMeters: Double,
        plan: LMTerrainTilePlan,
        activePlans: [LMTerrainTilePlan]? = nil
    ) -> (elevationMeters: Float, levelContributionMeters: Float, fineElevationMeters: Float)? {
        guard contains(plan, eastMeters: eastMeters, northMeters: northMeters),
              let fine = terrainSampler.sample(
                  eastMeters: eastMeters,
                  northMeters: northMeters,
                  requestedSpacingMeters: plan.sampleSpacingMeters
              ) else {
            return nil
        }

        if heightField.resolvesProceduralSamples {
            guard let parent = heightField.renderedParent(eastMeters: eastMeters, northMeters: northMeters,
                                                          spacingMeters: plan.sampleSpacingMeters) else {
                return (fine.elevationMeters, fine.proceduralResidualMeters, fine.elevationMeters)
            }
            let weight = Self.smoothstep(distanceToEdge(plan, eastMeters: eastMeters, northMeters: northMeters)
                                        / min(plan.sizeMeters / 4, parent.spacing * 8))
            let contribution = (fine.elevationMeters - parent.elevation) * Float(weight)
            return (parent.elevation + contribution, contribution, fine.elevationMeters)
        }

        let parent = parentPlan(
            for: plan,
            eastMeters: eastMeters,
            northMeters: northMeters,
            activePlans: activePlans
        )
        let parentSpacing = parent?.sampleSpacingMeters ?? heightField.spacingMeters
        guard let parentRaw = terrainSampler.sample(
            eastMeters: eastMeters,
            northMeters: northMeters,
            requestedSpacingMeters: parentSpacing
        ) else {
            return nil
        }
        let parentRendered = parent.flatMap {
            renderedElevation(
                eastMeters: eastMeters,
                northMeters: northMeters,
                plan: $0,
                activePlans: activePlans
            )
        } ?? fine.measuredElevationMeters
        // Match the appearance handoff in the outer quarter of a prefetched
        // perimeter tile. Most of the tile stays identical to its same-level
        // neighbors, while the outside edge still reaches the exact parent.
        let morphWidth = min(plan.sizeMeters / 4, parentSpacing * 8)
        let edgeDistance = distanceToEdge(
            plan,
            eastMeters: eastMeters,
            northMeters: northMeters
        )
        let morph = Self.smoothstep(edgeDistance / morphWidth)
        let levelContribution = fine.elevationMeters
            - parentRaw.elevationMeters
        // Covered parent triangles are removed when a finer tile is resident,
        // so the old millimeter-scale anti-z-fighting lift is both unnecessary
        // and harmful here. Adding a constant lift inside every footprint made
        // its morph collar a shallow rectangular ramp under the low mission sun
        // and offset rendered terrain from the shared contact surface.
        let realizedContribution = levelContribution * Float(morph)
        return (
            elevationMeters: parentRendered + realizedContribution,
            levelContributionMeters: realizedContribution,
            fineElevationMeters: fine.elevationMeters
        )
    }

    /// Samples the same or next-coarser resident surface just beyond a tile
    /// boundary. Mesh normals use this only for their perimeter vertices so
    /// two adjacent tiles derive an identical central-difference slope instead
    /// of each clamping to a different one-sided derivative.
    func renderedElevationAround(
        eastMeters: Double,
        northMeters: Double,
        referencePlan: LMTerrainTilePlan,
        activePlans: [LMTerrainTilePlan]
    ) -> Float? {
        let candidate = activePlans
            .filter {
                $0.sampleSpacingMeters
                    >= referencePlan.sampleSpacingMeters - Self.spacingToleranceMeters
                    && contains(
                        $0,
                        eastMeters: eastMeters,
                        northMeters: northMeters
                    )
            }
            .min { $0.sampleSpacingMeters < $1.sampleSpacingMeters }
        if let candidate {
            return renderedElevation(
                eastMeters: eastMeters,
                northMeters: northMeters,
                plan: candidate,
                activePlans: activePlans
            )
        }
        return heightField.relativeElevation(
            eastMeters: eastMeters,
            northMeters: northMeters
        )
    }

    func parentPlan(
        for plan: LMTerrainTilePlan,
        eastMeters: Double,
        northMeters: Double,
        activePlans: [LMTerrainTilePlan]? = nil
    ) -> LMTerrainTilePlan? {
        guard let parent = planner.levels.enumerated()
            .filter({ _, level in
                level.sampleSpacingMeters
                    > plan.sampleSpacingMeters + Self.spacingToleranceMeters
                    && level.sampleSpacingMeters
                    < heightField.spacingMeters - Self.spacingToleranceMeters
            })
            .min(by: { $0.element.sampleSpacingMeters < $1.element.sampleSpacingMeters }) else {
            return nil
        }
        let fallback = tilePlan(
            levelIndex: parent.offset,
            level: parent.element,
            eastMeters: eastMeters,
            northMeters: northMeters
        )
        return activePlans?.first(where: { candidate in
            candidate.id == fallback.id
        }) ?? fallback
    }

    private func tilePlan(
        levelIndex: Int,
        level: LMProgressiveTerrainPlanner.Level,
        eastMeters: Double,
        northMeters: Double
    ) -> LMTerrainTilePlan {
        let eastIndex = Int(floor(eastMeters / level.tileSizeMeters))
        let northIndex = Int(floor(northMeters / level.tileSizeMeters))
        return LMTerrainTilePlan(
            id: .init(level: levelIndex, eastIndex: eastIndex, northIndex: northIndex),
            centerEastMeters: (Double(eastIndex) + 0.5) * level.tileSizeMeters,
            centerNorthMeters: (Double(northIndex) + 0.5) * level.tileSizeMeters,
            sizeMeters: level.tileSizeMeters,
            sampleSpacingMeters: level.sampleSpacingMeters,
            containsProceduralSubresolution: true
        )
    }

    private func contains(
        _ plan: LMTerrainTilePlan,
        eastMeters: Double,
        northMeters: Double
    ) -> Bool {
        let halfSize = plan.sizeMeters / 2
        let tolerance = Self.spacingToleranceMeters
        return eastMeters >= plan.centerEastMeters - halfSize - tolerance
            && eastMeters <= plan.centerEastMeters + halfSize + tolerance
            && northMeters >= plan.centerNorthMeters - halfSize - tolerance
            && northMeters <= plan.centerNorthMeters + halfSize + tolerance
    }

    private func distanceToEdge(
        _ plan: LMTerrainTilePlan,
        eastMeters: Double,
        northMeters: Double
    ) -> Double {
        let halfSize = plan.sizeMeters / 2
        var distances = [Double]()
        distances.reserveCapacity(4)
        if plan.transitionEdges.contains(.west) {
            distances.append(eastMeters - (plan.centerEastMeters - halfSize))
        }
        if plan.transitionEdges.contains(.east) {
            distances.append(plan.centerEastMeters + halfSize - eastMeters)
        }
        if plan.transitionEdges.contains(.south) {
            distances.append(northMeters - (plan.centerNorthMeters - halfSize))
        }
        if plan.transitionEdges.contains(.north) {
            distances.append(plan.centerNorthMeters + halfSize - northMeters)
        }
        return max(0, distances.min() ?? plan.sizeMeters)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
