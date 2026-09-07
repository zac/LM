import Foundation
import simd

/// Immutable source ownership and procedural version for one resident region.
/// Re-anchoring the presentation never changes this value or its lunar samples.
public struct LMLunarResolvedTerrain: Sendable {
    static let generatorVersion = "lunar-source-anchored-octaves-v2"
    public let base: LMLunarElevationGrid
    /// Increasing resolution; overlapping strips from one product share posts.
    let refinements: [LMLunarElevationGrid]
    private let postRelief = LMLunarPostReliefCache()
    private let parentPPDs: [Double]

    init(base: LMLunarElevationGrid, refinements: [LMLunarElevationGrid]) {
        self.base = base
        self.refinements = refinements
        // Immutable source metadata, formerly filtered/copied per vertex.
        self.parentPPDs = refinements.map { grid in
            refinements.filter { $0.pixelsPerDegree < grid.pixelsPerDegree }
                .map(\.pixelsPerDegree).max() ?? base.pixelsPerDegree
        }
    }

    struct Sample: Sendable {
        let measuredMeters: Double
        let residualMeters: Double
        let capMeters: Double
        let sourceSpacingMeters: Double
        let sourceID: String
        var elevationMeters: Double { measuredMeters + residualMeters }
    }

    func sample(at coordinate: LMSelenographicCoordinate, spacingMeters: Double) -> Sample? {
        guard spacingMeters.isFinite, spacingMeters > 0 else { return nil }
        // Search ownership without copying grids/Data into a temporary array
        // for every sample. The last fully owned source still wins.
        var ownedIndex: Int?
        for index in refinements.indices.reversed() {
            if influence(of: refinements[index], parentPPD: parentPPDs[index], at: coordinate) == 1 {
                ownedIndex = index
                break
            }
        }
        let owner = ownedIndex.map { refinements[$0] } ?? base
        guard var result = resolved(grid: owner, coordinate: coordinate, spacing: spacingMeters) else { return nil }
        for index in (ownedIndex.map { $0 + 1 } ?? 0)..<refinements.count {
            let grid = refinements[index]
            guard grid.pixelsPerDegree > owner.pixelsPerDegree else { continue }
            let weight = influence(of: grid, parentPPD: parentPPDs[index], at: coordinate)
            guard weight > 0 else { continue }
            let clamped = clampedCoordinate(coordinate, to: grid)
            guard let finer = resolved(grid: grid, coordinate: clamped, spacing: spacingMeters) else { continue }
            result = Sample(
                measuredMeters: result.measuredMeters + (finer.measuredMeters - result.measuredMeters) * weight,
                residualMeters: result.residualMeters + (finer.residualMeters - result.residualMeters) * weight,
                capMeters: result.capMeters + (finer.capMeters - result.capMeters) * weight,
                sourceSpacingMeters: max(result.sourceSpacingMeters, finer.sourceSpacingMeters),
                sourceID: result.sourceID + "+" + finer.sourceID
            )
        }
        return result
    }

    private func resolved(grid: LMLunarElevationGrid, coordinate: LMSelenographicCoordinate,
                          spacing: Double) -> Sample? {
        guard let measured = grid.elevation(at: coordinate) else { return nil }
        let cap = grid.spacingMeters * grid.residualCapFraction
        let residual: Double
        if spacing >= grid.spacingMeters || cap == 0 {
            residual = 0
        } else {
            let anchored = anchoredRelief(grid: grid, coordinate: coordinate, spacing: spacing)
            residual = cap * tanh(anchored * (1 - spacing / grid.spacingMeters) / cap)
        }
        return Sample(measuredMeters: measured, residualMeters: residual, capMeters: cap,
                      sourceSpacingMeters: grid.spacingMeters, sourceID: grid.sourceID)
    }

    private func anchoredRelief(grid: LMLunarElevationGrid, coordinate: LMSelenographicCoordinate,
                                spacing: Double) -> Double {
        let point = grid.fractionalPost(at: coordinate)
        let x = grid.wrapsLongitude ? point.x : min(max(point.x, 0), Double(grid.width - 1))
        let y = min(max(point.y, 0), Double(grid.height - 1))
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let tx = x - Double(x0), ty = y - Double(y0)
        // A measured post is a contract, not a tolerance around sin(pi*n).
        if tx == 0, ty == 0, point.y == y { return 0 }
        let x1 = grid.wrapsLongitude ? (x0 + 1) % grid.width : min(x0 + 1, grid.width - 1)
        let y1 = min(y0 + 1, grid.height - 1)
        func raw(_ coordinate: LMSelenographicCoordinate) -> Double {
            LMLunarGlobalGeology.relief(at: coordinate, spacingMeters: spacing,
                                       sourceSpacingMeters: grid.spacingMeters)
        }
        func post(_ row: Int, _ column: Int) -> Double {
            postRelief.value(source: grid.sourceID, row: row, column: column, spacing: spacing) {
                raw(grid.coordinate(row: row, column: column))
            }
        }
        let nw = post(y0, x0)
        let ne = post(y0, x1)
        let sw = post(y1, x0)
        let se = post(y1, x1)
        let north = nw + (ne - nw) * tx
        let south = sw + (se - sw) * tx
        let anchor = north + (south - north) * ty
        // Longitude degenerates at a pole. Fade only the unsampled half-post
        // cap to zero; the last measured row retains its exact anchored field.
        let polarWeight = min(1, max(0, (90 - abs(coordinate.latitudeDegrees)) * grid.pixelsPerDegree * 2))
        return (raw(coordinate) - anchor) * polarWeight
    }

    /// Extend a finer edge only as far as the next coarser measured post.
    /// Interior fine posts stay exact, and exterior coarse posts stay exact.
    /// This gives C0 source joins without biasing either owned measurement.
    func influence(of grid: LMLunarElevationGrid, at coordinate: LMSelenographicCoordinate) -> Double {
        let parentPPD = refinements.filter { $0.pixelsPerDegree < grid.pixelsPerDegree }
            .map(\.pixelsPerDegree).max() ?? base.pixelsPerDegree
        return influence(of: grid, parentPPD: parentPPD, at: coordinate)
    }

    private func influence(of grid: LMLunarElevationGrid, parentPPD: Double,
                           at coordinate: LMSelenographicCoordinate) -> Double {
        func ramp(_ value: Double, low: Double, high: Double, origin: Double) -> Double {
            if value >= low, value <= high { return 1 }
            if value < low {
                let outside = origin + (floor((low - origin) * parentPPD - 0.5) + 0.5) / parentPPD
                return smoothstep((value - outside) / max(low - outside, 1e-12))
            }
            let outside = origin + (ceil((high - origin) * parentPPD - 0.5) + 0.5) / parentPPD
            return smoothstep((outside - value) / max(outside - high, 1e-12))
        }
        // Latitude posts have the same half-post registration as longitude.
        let latitudeWeight = ramp(coordinate.latitudeDegrees,
                                  low: grid.southernCoverageLatitude, high: grid.northernCoverageLatitude,
                                  origin: -90)
        if grid.wrapsLongitude { return latitudeWeight }
        var longitude = coordinate.longitudeDegrees
        longitude += 360 * ((0.5 * (grid.westernPostLongitude + grid.easternPostLongitude) - longitude) / 360).rounded()
        return latitudeWeight * ramp(longitude, low: grid.westernPostLongitude,
                                     high: grid.easternPostLongitude, origin: 0)
    }

    private func clampedCoordinate(_ coordinate: LMSelenographicCoordinate,
                                   to grid: LMLunarElevationGrid) -> LMSelenographicCoordinate {
        var longitude = coordinate.longitudeDegrees
        if !grid.wrapsLongitude {
            longitude += 360 * ((0.5 * (grid.westernPostLongitude + grid.easternPostLongitude) - longitude) / 360).rounded()
            longitude = min(max(longitude, grid.westernPostLongitude), grid.easternPostLongitude)
        }
        return .init(latitudeDegrees: min(max(coordinate.latitudeDegrees, grid.southernCoverageLatitude),
                                           grid.northernCoverageLatitude),
                     longitudeDegrees: longitude)
    }

    private func smoothstep(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Bounded memoization only: eviction and concurrent duplicate computation
/// cannot change a value. Each immutable resolved region owns its own cache.
private final class LMLunarPostReliefCache: @unchecked Sendable {
    private struct Key: Hashable {
        let source: String
        let row: Int
        let column: Int
        let spacing: Double
    }
    private let lock = NSLock()
    private var values = [Key: Double]()
    func value(source: String, row: Int, column: Int, spacing: Double, compute: () -> Double) -> Double {
        let key = Key(source: source, row: row, column: column, spacing: spacing)
        lock.lock()
        let cached = values[key]
        lock.unlock()
        if let cached { return cached }
        let result = compute()
        lock.lock()
        if values.count >= 16_384 { values.removeAll(keepingCapacity: true) }
        values[key] = result
        lock.unlock()
        return result
    }
}

/// A spherical extension of the existing versioned crater morphology.
/// Fixed Moon-centered projections avoid seams at longitude +/-180 and poles.
/// Opposite hemispheres have independent seeds; projection weights vanish at
/// their seed boundary. Scaled populations preserve the model's -2 size slope.
/// The largest population is 14.08...76.8 m, within the small-crater regime
/// discussed by Soderblom 1970 / USGS and the 1980 small-crater review.
enum LMLunarGlobalGeology {
    static let scales = [1.0, 4, 16, 64]
    static let sourceURL = "https://ntrs.nasa.gov/citations/19800068354"

    static func relief(at coordinate: LMSelenographicCoordinate, spacingMeters: Double,
                       sourceSpacingMeters: Double) -> Double {
        let system = LMSelenographicCoordinateSystem()
        var point = system.moonCenteredPosition(for: .init(
            latitudeDegrees: coordinate.latitudeDegrees, longitudeDegrees: coordinate.longitudeDegrees
        )).vector
        if abs(coordinate.latitudeDegrees) == 90 { point.x = 0; point.y = 0 }
        let unit = simd_normalize(point)
        let powers = SIMD3(pow(unit.x, 8), pow(unit.y, 8), pow(unit.z, 8))
        let weights = powers / (powers.x + powers.y + powers.z)
        var total = 0.0
        for (octave, scale) in scales.enumerated()
            where scale * LMLunarGeologyModel.maximumCraterDiameterMeters < sourceSpacingMeters
                && spacingMeters / scale < LMLunarGeologyModel.maximumCraterDiameterMeters / 2 {
            for axis in 0..<3 where weights[axis] > 1e-12 {
                let sign = point[axis] >= 0 ? 0 : 1
                let seed = UInt64(0x4C_55_4E_41_52) &+ UInt64(octave * 6 + axis * 2 + sign) &* 0x9E3779B97F4A7C15
                let model = LMLunarGeologyModel(seed: seed)
                let uv: SIMD2<Double>
                switch axis {
                case 0: uv = SIMD2(point.y, point.z) / scale
                case 1: uv = SIMD2(point.x, point.z) / scale
                default: uv = SIMD2(point.x, point.y) / scale
                }
                total += weights[axis] * scale * model.visualReliefMeters(
                    eastMeters: uv.x, northMeters: uv.y,
                    requestedSpacingMeters: spacingMeters / scale
                )
            }
        }
        return total
    }
}

/// Exact-input memoization of the four-iteration spherical graph solve.
/// FIFO eviction only changes computation cost. Each instance belongs to one
/// immutable field and one preparation; coordinates and requested spacing are
/// keyed by their Double bits, with no quantization or interpolation.
final class LMLunarLocalSampleCache: @unchecked Sendable {
    private struct Key: Hashable {
        let east: UInt64, north: UInt64, spacing: UInt64
    }
    private let lock = NSLock()
    private let capacity = 16_384
    private var values = [Key: (measured: Double, rendered: Double)]()
    private var keys = [Key]()
    private var cursor = 0

    func value(east: Double, north: Double, spacing: Double,
               compute: () -> (measured: Double, rendered: Double)?)
        -> (measured: Double, rendered: Double)? {
        let key = Key(east: east.bitPattern, north: north.bitPattern, spacing: spacing.bitPattern)
        if let found = lock.withLock({ values[key] }) { return found }
        guard let result = compute() else { return nil }
        lock.withLock {
            if values[key] != nil { return }
            if keys.count == capacity {
                values.removeValue(forKey: keys[cursor])
                keys[cursor] = key
                cursor = (cursor + 1) % capacity
            } else { keys.append(key) }
            values[key] = result
        }
        return result
    }
}

/// Projects the immutable lunar source into one local graph for the existing
/// clipmap builder. Solve radius along the local up line, preserving requested
/// north/east coordinates and lunar curvature. No tangent-plane flattening.
struct LMLunarTerrainHeightField: LMTerrainHeightField {
    let terrain: LMLunarResolvedTerrain
    let frame: LMSelenographicLocalFrame
    var parents = LMLunarTerrainMeshSnapshot(tiles: [])
    private var sampleCache: LMLunarLocalSampleCache?

    init(terrain: LMLunarResolvedTerrain, frame: LMSelenographicLocalFrame) {
        self.terrain = terrain
        self.frame = frame
    }

    func prepared(eastMetersRange: ClosedRange<Double>,
                  northMetersRange: ClosedRange<Double>) -> any LMTerrainHeightField {
        var prepared = self
        // One bounded cache per mesh preparation. It is never retained by the
        // terrain snapshot, rendered entities or contact sampler.
        prepared.sampleCache = LMLunarLocalSampleCache()
        return prepared
    }

    var spacingMeters: Double { terrain.base.spacingMeters }
    var width: Int { 1_025 }
    var height: Int { 1_025 }
    var craterCatalog: LMLunarCraterCatalog? { nil }
    var resolvesProceduralSamples: Bool { true }

    func renderedParent(eastMeters: Double, northMeters: Double,
                        spacingMeters: Double) -> LMLunarTerrainMeshTile.Sample? {
        parents.sample(east: eastMeters, north: northMeters, coarserThan: spacingMeters)
    }

    func relativeElevation(eastMeters: Double, northMeters: Double) -> Float? {
        localSample(east: eastMeters, north: northMeters, spacing: .greatestFiniteMagnitude).map { Float($0.measured) }
    }

    func resolvedSample(eastMeters: Double, northMeters: Double,
                        requestedSpacingMeters: Double) -> LMResolvedTerrainSample? {
        guard let sample = localSample(east: eastMeters, north: northMeters, spacing: requestedSpacingMeters) else { return nil }
        let measured = Float(sample.measured)
        let residual = Float(sample.rendered - sample.measured)
        return LMResolvedTerrainSample(measuredElevationMeters: measured,
                                       proceduralResidualMeters: residual,
                                       elevationMeters: measured + residual,
                                       provenance: residual == 0 ? .measuredInterpolated : .measuredWithProceduralSubresolution)
    }

    private func localSample(east: Double, north: Double, spacing: Double) -> (measured: Double, rendered: Double)? {
        guard east.isFinite, north.isFinite else { return nil }
        if let sampleCache {
            return sampleCache.value(east: east, north: north, spacing: spacing) {
                uncachedLocalSample(east: east, north: north, spacing: spacing)
            }
        }
        return uncachedLocalSample(east: east, north: north, spacing: spacing)
    }

    private func uncachedLocalSample(east: Double, north: Double, spacing: Double) -> (measured: Double, rendered: Double)? {
        let anchorRadius = frame.coordinateSystem.datumRadiusMeters + frame.anchor.heightMeters
        let horizontalSquared = east * east + north * north
        var up = 0.0
        var measured = 0.0
        // Fixed iteration count is deterministic. A region is far smaller than
        // the Moon; curvature and terrain slopes make this contraction rapid.
        for _ in 0..<4 {
            let coordinate = frame.coordinate(for: .init(northMeters: north, eastMeters: east, upMeters: up))
            guard let sample = terrain.sample(at: coordinate, spacingMeters: spacing) else { return nil }
            let measuredRadius = frame.coordinateSystem.datumRadiusMeters + sample.measuredMeters
            let radius = frame.coordinateSystem.datumRadiusMeters + sample.elevationMeters
            guard radius * radius > horizontalSquared, measuredRadius * measuredRadius > horizontalSquared else { return nil }
            measured = sqrt(measuredRadius * measuredRadius - horizontalSquared) - anchorRadius
            up = sqrt(radius * radius - horizontalSquared) - anchorRadius
        }
        return (measured, up)
    }

    func interpolatedSurfaceNormal(eastMeters: Double, northMeters: Double) -> SIMD3<Float>? {
        let coordinate = frame.coordinate(for: .init(northMeters: northMeters, eastMeters: eastMeters, upMeters: 0))
        let step = terrain.sample(at: coordinate, spacingMeters: .greatestFiniteMagnitude)?.sourceSpacingMeters
            ?? terrain.base.spacingMeters
        guard let west = relativeElevation(eastMeters: eastMeters - step, northMeters: northMeters),
              let east = relativeElevation(eastMeters: eastMeters + step, northMeters: northMeters),
              let north = relativeElevation(eastMeters: eastMeters, northMeters: northMeters + step),
              let south = relativeElevation(eastMeters: eastMeters, northMeters: northMeters - step) else { return nil }
        return simd_normalize(SIMD3(-(north - south) / Float(2 * step), 1, (east - west) / Float(2 * step)))
    }
}
