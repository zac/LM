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
/// bounded, and exactly zero at every measured grid post. A future 2 m or 0.5 m DTM can
/// therefore replace the current 8 m source without changing the renderer contract.
struct LMProgressiveTerrainSampler: Sendable {
    let heightField: Apollo11TerrainHeightField
    let seed: UInt64
    let maximumResidualMeters: Float

    init(
        heightField: Apollo11TerrainHeightField,
        seed: UInt64 = 0x4C_52_4F_43_41_31_31,
        maximumResidualMeters: Float = 0.24
    ) {
        self.heightField = heightField
        self.seed = seed
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

        let sourceSpacing = heightField.manifest.meshSpacingMeters
        guard requestedSpacingMeters < sourceSpacing else {
            return LMResolvedTerrainSample(
                measuredElevationMeters: measured,
                proceduralResidualMeters: 0,
                elevationMeters: measured,
                provenance: .measuredInterpolated
            )
        }

        let detailFraction = Float(1 - requestedSpacingMeters / sourceSpacing)
        let residual = anchoredResidual(
            eastMeters: eastMeters,
            northMeters: northMeters
        ) * maximumResidualMeters * detailFraction
        return LMResolvedTerrainSample(
            measuredElevationMeters: measured,
            proceduralResidualMeters: residual,
            elevationMeters: measured + residual,
            provenance: .measuredWithProceduralSubresolution
        )
    }

    private func anchoredResidual(eastMeters: Double, northMeters: Double) -> Float {
        let spacing = heightField.manifest.meshSpacingMeters
        let halfWidth = Double(heightField.manifest.meshWidth - 1) * spacing / 2
        let halfDepth = Double(heightField.manifest.meshHeight - 1) * spacing / 2
        let column = (eastMeters + halfWidth) / spacing
        let row = (halfDepth - northMeters) / spacing
        let columnFraction = column - floor(column)
        let rowFraction = row - floor(row)

        // This envelope preserves every LROC post exactly and smoothly fades the
        // invented residual to zero at the measured cell boundaries.
        let anchorEnvelope = sin(.pi * columnFraction) * sin(.pi * rowFraction)
        guard abs(anchorEnvelope) > 1e-12 else { return 0 }

        let octaveScales = [spacing / 2, spacing / 4, spacing / 8, spacing / 16]
        let octaveWeights = [0.56, 0.26, 0.12, 0.06]
        var total = 0.0
        for (scale, weight) in zip(octaveScales, octaveWeights) {
            total += valueNoise(
                eastMeters / scale,
                northMeters / scale
            ) * weight
        }
        return Float(total * anchorEnvelope)
    }

    private func valueNoise(_ x: Double, _ y: Double) -> Double {
        let x0 = Int64(floor(x))
        let y0 = Int64(floor(y))
        let tx = smoothstep(x - floor(x))
        let ty = smoothstep(y - floor(y))
        let north = mix(hash(x0, y0), hash(x0 + 1, y0), tx)
        let south = mix(hash(x0, y0 + 1), hash(x0 + 1, y0 + 1), tx)
        return mix(north, south, ty)
    }

    private func hash(_ x: Int64, _ y: Int64) -> Double {
        var value = UInt64(bitPattern: x) &* 0x9E37_79B9_7F4A_7C15
        value ^= UInt64(bitPattern: y) &* 0xBF58_476D_1CE4_E5B9
        value ^= seed
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value & 0x00FF_FFFF) / Double(0x007F_FFFF) - 1
    }

    private func smoothstep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }

    private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
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

/// Stable clipmap planning around the vehicle. The plan is renderer-independent so
/// tiles can later be generated by RealityKit meshes, Metal tessellation, or streamed USD.
struct LMProgressiveTerrainPlanner: Sendable {
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
                        containsProceduralSubresolution: level.sampleSpacingMeters < sourceSpacingMeters
                    )
                }
            }
        }
    }
}
