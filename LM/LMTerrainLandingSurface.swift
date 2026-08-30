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
/// The gear solver queries this thousands of times per frame across its contact
/// substeps, which the recursive clipmap evaluator cannot sustain. So the
/// evaluator is run once, off the main actor, over a patch around the vehicle,
/// at the finest rendered sample spacing. Interpolating that patch reproduces
/// the rendered mesh rather than approximating it, because the mesh is itself a
/// linear interpolation of samples on the same grid.
///
/// Heights are referenced to the terrain elevation under Eagle rather than to
/// the raw terrain datum, so a nominal descent still touches down at guidance
/// altitude zero and the bundled trajectories are not shifted vertically. Local
/// relief around that point is preserved exactly.
struct LMTerrainContactSurface: LMLandingSurfaceModel {
    /// Terrain-frame position of the grid's north-west corner.
    let cornerEastMeters: Double
    let cornerNorthMeters: Double
    let spacingMeters: Double
    let columns: Int
    let rows: Int
    /// Rendered elevation minus the Eagle datum, row 0 north, column 0 west.
    let heights: [Float]

    /// Measured fallback for queries outside the patch. Contact happens well
    /// inside it; this only keeps the far field finite and continuous-ish.
    let heightField: Apollo11TerrainHeightField
    let alignment: LMTerrainFrameAlignment?
    let referenceElevationMeters: Float

    /// Terrain-frame center of the patch, used to decide when it must be rebuilt.
    var centerEastMeters: Double {
        cornerEastMeters + Double(columns - 1) * spacingMeters / 2
    }

    var centerNorthMeters: Double {
        cornerNorthMeters - Double(rows - 1) * spacingMeters / 2
    }

    func surfaceHeightMeters(northMeters: Double, eastMeters: Double) -> Double {
        let guidance = LMVector3D(x: northMeters, y: eastMeters, z: 0)
        let terrain = alignment?.terrainPosition(from: guidance) ?? guidance
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
        let top = value(x0, y0) + (value(x1, y0) - value(x0, y0)) * tx
        let bottom = value(x0, y1) + (value(x1, y1) - value(x0, y1)) * tx
        return Double(top + (bottom - top) * ty)
    }
}

/// Builds the contact patch from the same evaluator that generates tile meshes.
enum LMTerrainContactSurfaceBuilder {
    /// Comfortably larger than the 9.4 m gear spread, so ordinary terminal
    /// drift does not push a footpad off the patch between rebuilds.
    static let extentMeters = 40.0
    /// Rebuild once the vehicle has drifted this far from the patch center.
    static let rebuildDriftMeters = 8.0
    /// Below this altitude the gear can reach the ground within a few seconds,
    /// so the patch is kept warm from here down.
    static let buildAltitudeMeters = 60.0

    nonisolated static func build(
        heightField: Apollo11TerrainHeightField,
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
        let side = max(2, Int((extentMeters / spacing).rounded(.up)) + 1)
        let half = Double(side - 1) * spacing / 2
        let cornerEast = centerTerrainEastMeters - half
        let cornerNorth = centerTerrainNorthMeters + half

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

        var heights = [Float](repeating: 0, count: side * side)
        for row in 0..<side {
            try Task.checkCancellation()
            let north = cornerNorth - Double(row) * spacing
            for column in 0..<side {
                let east = cornerEast + Double(column) * spacing
                let elevation = sampler.sample(
                    eastMeters: east,
                    northMeters: north,
                    altitudeMeters: altitudeMeters,
                    activePlans: activePlans
                )?.renderedElevationMeters
                    ?? heightField.relativeElevation(
                        eastMeters: east,
                        northMeters: north
                    )
                    ?? reference
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
