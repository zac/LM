import Foundation
import simd

/// The geometry pipeline depends on a surface, not on an Apollo asset layout.
/// Existing Apollo calls retain their original implementation and arithmetic.
protocol LMTerrainHeightField: Sendable {
    var spacingMeters: Double { get }
    var width: Int { get }
    var height: Int { get }
    var craterCatalog: LMLunarCraterCatalog? { get }
    func relativeElevation(eastMeters: Double, northMeters: Double) -> Float?
    func interpolatedSurfaceNormal(eastMeters: Double, northMeters: Double) -> SIMD3<Float>?
    func resolvedSample(eastMeters: Double, northMeters: Double,
                        requestedSpacingMeters: Double) -> LMResolvedTerrainSample?
    var resolvesProceduralSamples: Bool { get }
    func renderedParent(eastMeters: Double, northMeters: Double,
                        spacingMeters: Double) -> LMLunarTerrainMeshTile.Sample?
    func prepared(eastMetersRange: ClosedRange<Double>,
                  northMetersRange: ClosedRange<Double>) -> any LMTerrainHeightField
}

extension LMTerrainHeightField {
    var resolvesProceduralSamples: Bool { false }
    func renderedParent(eastMeters: Double, northMeters: Double,
                        spacingMeters: Double) -> LMLunarTerrainMeshTile.Sample? { nil }
    func resolvedSample(eastMeters: Double, northMeters: Double,
                        requestedSpacingMeters: Double) -> LMResolvedTerrainSample? { nil }
    func prepared(eastMetersRange: ClosedRange<Double>,
                  northMetersRange: ClosedRange<Double>) -> any LMTerrainHeightField { self }
}

extension Apollo11TerrainHeightField: LMTerrainHeightField {}
