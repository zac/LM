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
    let heightField: Apollo11TerrainHeightField
    let geology: LMLunarGeologyModel
    let maximumResidualMeters: Float

    init(
        heightField: Apollo11TerrainHeightField,
        seed: UInt64 = 0x4C_52_4F_43_41_31_31,
        maximumResidualMeters: Float = 0.24
    ) {
        self.heightField = heightField
        geology = LMLunarGeologyModel(seed: seed)
        self.maximumResidualMeters = maximumResidualMeters
    }

    func sample(
        eastMeters: Double,
        northMeters: Double,
        requestedSpacingMeters: Double
    ) -> LMResolvedTerrainSample? {
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
                requestedSpacingMeters: requestedSpacingMeters
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
    static let modelID = "surveyor-steady-state-microcraters-v1"
    static let cumulativeCraterDiameterExponent = -2.0
    static let minimumCraterDiameterMeters = 0.22
    static let maximumCraterDiameterMeters = 1.8
    static let surveyorSourceURL =
        "https://www.usgs.gov/publications/physical-characteristics-lunar-regolith-determined-surveyor-television-observations"
    static let apollo11SourceURL =
        "https://ntrs.nasa.gov/api/citations/19700000726/downloads/19700000726.pdf"

    let seed: UInt64
    let cellSizeMeters = 2.0
    let candidatesPerCell = 2
    let candidateAcceptance = 0.82

    func visualReliefMeters(
        eastMeters: Double,
        northMeters: Double,
        requestedSpacingMeters: Double
    ) -> Double {
        let minimumRenderableDiameter = max(
            Self.minimumCraterDiameterMeters,
            requestedSpacingMeters * 2
        )
        let eastCell = Int64(floor(eastMeters / cellSizeMeters))
        let northCell = Int64(floor(northMeters / cellSizeMeters))
        var relief = 0.0

        for northOffset in -1...1 {
            for eastOffset in -1...1 {
                let cellEast = eastCell + Int64(eastOffset)
                let cellNorth = northCell + Int64(northOffset)
                for candidate in 0..<candidatesPerCell {
                    guard let crater = crater(
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
            sharpness: 0.20 + unit(cellEast, cellNorth, candidate, 6) * 0.80,
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
        let depth = crater.diameterMeters * (0.035 + crater.sharpness * 0.085)
        let rimHeight = crater.diameterMeters * (0.010 + crater.sharpness * 0.024)
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
            relief += crater.diameterMeters * 0.008 * crater.sharpness
                * ejectaEnvelope * rays
        }
        return relief
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

struct LMTerrainTileID: Hashable, Sendable {
    let level: Int
    let eastIndex: Int
    let northIndex: Int
}

struct LMTerrainTilePlan: Equatable, Sendable {
    let id: LMTerrainTileID
    let centerEastMeters: Double
    let centerNorthMeters: Double
    let sizeMeters: Double
    let sampleSpacingMeters: Double
    let containsProceduralSubresolution: Bool
}

/// Selects only the sub-resolution detail that can contribute at the current
/// flight altitude. Measured source geometry remains present at every altitude.
struct LMTerrainDetailPolicy: Equatable, Sendable {
    let approachAltitudeMeters: Double
    let terminalAltitudeMeters: Double
    let landingAltitudeMeters: Double
    let approachSpacingMeters: Double
    let terminalSpacingMeters: Double
    let landingSpacingMeters: Double

    init(
        approachAltitudeMeters: Double = 2_500,
        terminalAltitudeMeters: Double = 250,
        landingAltitudeMeters: Double = 40,
        approachSpacingMeters: Double = 2,
        terminalSpacingMeters: Double = 0.5,
        landingSpacingMeters: Double = 0.125
    ) {
        self.approachAltitudeMeters = approachAltitudeMeters
        self.terminalAltitudeMeters = terminalAltitudeMeters
        self.landingAltitudeMeters = landingAltitudeMeters
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
        return nil
    }
}

/// Stable clipmap planning around the vehicle. The plan is renderer-independent so
/// tiles can later be generated by RealityKit meshes, Metal tessellation, or streamed USD.
struct LMProgressiveTerrainPlanner: Sendable {
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
        levels.enumerated().flatMap { levelIndex, level in
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
    }

    /// One nested tile per useful detail level. These plans are cheap enough to
    /// regenerate as the vehicle crosses a tile boundary while the measured
    /// regional mesh remains the immutable coverage underneath.
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

        return levels.enumerated().compactMap { levelIndex, level in
            guard level.sampleSpacingMeters >= finestSpacing,
                  level.sampleSpacingMeters
                    < sourceSpacingMeters - Self.spacingToleranceMeters else {
                return nil
            }
            let eastIndex = Int(floor(focusEastMeters / level.tileSizeMeters))
            let northIndex = Int(floor(focusNorthMeters / level.tileSizeMeters))
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
                containsProceduralSubresolution: true
            )
        }
    }

    /// Keeps the tile under the vehicle and the tile at a short predicted
    /// position resident. Terminal horizontal rates are low enough that this
    /// normally adds only one 0.125 m tile, but it removes the parent-only gap
    /// observed when generation began after a 16 m boundary crossing.
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
        var seen = Set<LMTerrainTileID>()
        return (current + predicted).filter { seen.insert($0.id).inserted }
    }
}
