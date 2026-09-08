import Foundation
import LMCore

/// The terrain the landing gear touches, expressed in the AGC's guidance frame.
///
/// This is the bridge that stops the vehicle from landing on a mathematical
/// sphere. It is built by evaluating exactly the surface the renderer draws —
/// the same nested clipmap plans, the same edge morphs, the same bounded
/// procedural crater relief — so a footpad cannot rest above or below the
/// ground the crew is looking at, and a craterlet rim under one leg produces a
/// real tilt.
///
/// Global contact retains the submitted triangle snapshot without resampling.
/// The Apollo path prepares an aligned patch off the main actor and uses the
/// same triangle diagonal as the renderer. Both avoid evaluating procedural
/// relief inside the gear solver's repeated contact substeps.
///
/// Heights are referenced to the terrain elevation under Eagle rather than to
/// the raw terrain datum, so a nominal descent still touches down at guidance
/// altitude zero and the bundled trajectories are not shifted vertically. Local
/// relief around that point is preserved exactly.
public struct LMTerrainContactSurface: LMLandingSurfaceModel {
    /// Terrain-frame position of the grid's north-west corner.
    let cornerEastMeters: Double
    let cornerNorthMeters: Double
    public let spacingMeters: Double
    public let columns: Int
    public let rows: Int
    /// Rendered elevation minus the Eagle datum, row 0 north, column 0 west.
    let heights: [Float]

    /// Measured fallback for queries outside the patch. Contact happens well
    /// inside it; this only keeps the far field finite and continuous-ish.
    let heightField: any LMTerrainHeightField
    let alignment: LMTerrainFrameAlignment?
    public let referenceElevationMeters: Float
    var renderedSnapshot: LMLunarTerrainMeshSnapshot? = nil

    /// Terrain-frame center of the patch, used to decide when it must be rebuilt.
    public var centerEastMeters: Double {
        columns > 0 ? cornerEastMeters + Double(columns - 1) * spacingMeters / 2 : cornerEastMeters
    }

    public var centerNorthMeters: Double {
        rows > 0 ? cornerNorthMeters - Double(rows - 1) * spacingMeters / 2 : cornerNorthMeters
    }

    public func surfaceHeightMeters(northMeters: Double, eastMeters: Double) -> Double {
        let guidance = LMVector3D(x: northMeters, y: eastMeters, z: 0)
        let terrain = alignment?.terrainPosition(from: guidance) ?? guidance
        if let renderedSnapshot {
            let height = renderedSnapshot.sample(east: terrain.y, north: terrain.x)?.elevation
                ?? heightField.relativeElevation(eastMeters: terrain.y, northMeters: terrain.x)
                ?? referenceElevationMeters
            return Double(height - referenceElevationMeters)
        }
        let column = (terrain.y - cornerEastMeters) / spacingMeters
        let row = (cornerNorthMeters - terrain.x) / spacingMeters
        guard column >= 0, row >= 0,
              column <= Double(columns - 1),
              row <= Double(rows - 1) else {
            let measured = heightField.relativeElevation(
                eastMeters: terrain.y,
                northMeters: terrain.x
            ) ?? referenceElevationMeters
            return Double(measured - referenceElevationMeters)
        }

        let x0 = Int(column.rounded(.down))
        let y0 = Int(row.rounded(.down))
        let x1 = min(x0 + 1, columns - 1)
        let y1 = min(y0 + 1, rows - 1)
        let tx = Float(column - Double(x0))
        let ty = Float(row - Double(y0))
        func value(_ x: Int, _ y: Int) -> Float { heights[y * columns + x] }
        // Match the mesh's diagonal. Bilinear interpolation invents a curved
        // saddle between four posts whose rendered surface is two triangles.
        if tx + ty <= 1 {
            return Double(value(x0, y0) * (1 - tx - ty) + value(x1, y0) * tx + value(x0, y1) * ty)
        }
        return Double(value(x1, y0) * (1 - ty) + value(x1, y1) * (tx + ty - 1) + value(x0, y1) * (1 - tx))
    }
}

/// Builds the contact patch from the same evaluator that generates tile meshes.
public enum LMTerrainContactSurfaceBuilder {
    /// No resampling: retain the exact immutable mesh generation that became
    /// visible. Queries outside its coverage use the same measured fallback.
    public static func build(region: LMLunarTerrainRegion, snapshot: LMLunarTerrainMeshSnapshot,
                      alignment: LMTerrainFrameAlignment? = nil) -> LMTerrainContactSurface {
        let spacing = snapshot.tiles.map { $0.plan.sampleSpacingMeters }.min() ?? region.terrain.base.spacingMeters
        return .init(cornerEastMeters: 0, cornerNorthMeters: 0, spacingMeters: spacing,
                     columns: 0, rows: 0, heights: [],
                     heightField: LMLunarTerrainHeightField(terrain: region.terrain, frame: region.frame),
                     alignment: alignment, referenceElevationMeters: 0, renderedSnapshot: snapshot)
    }
    /// Comfortably larger than the 9.4 m gear spread, so ordinary terminal
    /// drift does not push a footpad off the patch between rebuilds.
    @usableFromInline static let extentMeters = 40.0
    /// Rebuild once the vehicle has drifted this far from the patch center.
    public static let rebuildDriftMeters = 8.0
    /// Below this altitude the gear can reach the ground within a few seconds,
    /// so the patch is kept warm from here down.
    public static let buildAltitudeMeters = 60.0

    public nonisolated static func build(
        heightField: any LMTerrainHeightField,
        alignment: LMTerrainFrameAlignment?,
        activePlans: [LMTerrainTilePlan],
        altitudeMeters: Double,
        centerTerrainEastMeters: Double,
        centerTerrainNorthMeters: Double,
        extentMeters: Double = extentMeters
    ) throws -> LMTerrainContactSurface {
        // Match the finest rendered spacing so interpolating the patch and
        // interpolating the mesh give the same surface.
        let spacing = activePlans.map(\.sampleSpacingMeters).min()
            ?? heightField.spacingMeters
        let side = max(2, Int((extentMeters / spacing).rounded(.up)) + 3)
        let half = Double(side - 1) * spacing / 2
        let cornerEast = floor((centerTerrainEastMeters - half) / spacing) * spacing
        let cornerNorth = ceil((centerTerrainNorthMeters + half) / spacing) * spacing

        let eagle = alignment?.terrainReferenceTouchdown ?? .zero
        let reference = heightField.relativeElevation(
            eastMeters: eagle.y,
            northMeters: eagle.x
        ) ?? 0

        let plan = LMTerrainTilePlan(
            id: .init(level: -1, eastIndex: 0, northIndex: 0),
            centerEastMeters: centerTerrainEastMeters,
            centerNorthMeters: centerTerrainNorthMeters,
            sizeMeters: extentMeters,
            sampleSpacingMeters: spacing,
            containsProceduralSubresolution: true
        )
        let sampler = LMProgressiveTerrainSurfaceSampler(
            heightField: heightField
        ).prepared(for: plan)

        struct Vertex: Hashable {
            let east: Double
            let north: Double
            let spacing: Double
        }
        var vertices = [Vertex: Float]()
        let owners = activePlans.sorted { $0.sampleSpacingMeters < $1.sampleSpacingMeters }
        func renderedTriangle(east: Double, north: Double) -> Float {
            let owner = owners.first {
                abs(east - $0.centerEastMeters) <= $0.sizeMeters / 2
                    && abs(north - $0.centerNorthMeters) <= $0.sizeMeters / 2
            }
            let step = owner?.sampleSpacingMeters ?? heightField.spacingMeters
            let west = floor(east / step) * step
            let top = ceil(north / step) * step
            let tx = Float((east - west) / step), ty = Float((top - north) / step)
            func vertex(_ e: Double, _ n: Double) -> Float {
                let key = Vertex(east: e, north: n, spacing: step)
                if let cached = vertices[key] { return cached }
                let value = owner.flatMap {
                    sampler.renderedElevation(eastMeters: e, northMeters: n, plan: $0, activePlans: activePlans)
                } ?? heightField.relativeElevation(eastMeters: e, northMeters: n) ?? reference
                vertices[key] = value
                return value
            }
            if tx == 0 && ty == 0 { return vertex(west, top) }
            if tx + ty <= 1 {
                return vertex(west, top) * (1 - tx - ty) + vertex(west + step, top) * tx + vertex(west, top - step) * ty
            }
            return vertex(west + step, top) * (1 - ty) + vertex(west + step, top - step) * (tx + ty - 1)
                + vertex(west, top - step) * (1 - tx)
        }

        var heights = [Float](repeating: 0, count: side * side)
        for row in 0..<side {
            try Task.checkCancellation()
            let north = cornerNorth - Double(row) * spacing
            for column in 0..<side {
                let east = cornerEast + Double(column) * spacing
                let elevation = renderedTriangle(east: east, north: north)
                heights[row * side + column] = elevation - reference
            }
        }

        return LMTerrainContactSurface(
            cornerEastMeters: cornerEast,
            cornerNorthMeters: cornerNorth,
            spacingMeters: spacing,
            columns: side,
            rows: side,
            heights: heights,
            heightField: heightField,
            alignment: alignment,
            referenceElevationMeters: reference
        )
    }
}
