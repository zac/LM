@testable import LunarMapExplorer
@testable import LunarMap
import Foundation
import CryptoKit
import CoreGraphics
import ImageIO
import RealityKit
import Testing
import simd
import LMCore

@Suite("Terrain detail textures")
struct TerrainDetailTextureTests {
    @Test func jointMicrotextureSamplingMatchesIndependentChannels() {
        let microtexture = LMRegolithMicrotextureModel()
        let craterlets = microtexture.craterletField(
            eastMetersRange: -2...3,
            northMetersRange: -3...2
        )
        let samples = [
            SIMD2<Double>(-1.75, -2.25),
            SIMD2<Double>(-0.13, 0.27),
            SIMD2<Double>(0, 0),
            SIMD2<Double>(1.43, -1.17),
            SIMD2<Double>(2.81, 1.64),
        ]

        for sampleSpacing in [0, 0.03125, 0.125, 0.5] {
            for sample in samples {
                let combined = microtexture.appearanceSample(
                    eastMeters: sample.x,
                    northMeters: sample.y,
                    sampleSpacingMeters: sampleSpacing,
                    craterlets: craterlets
                )
                let relief = microtexture.reliefMeters(
                    eastMeters: sample.x,
                    northMeters: sample.y,
                    sampleSpacingMeters: sampleSpacing,
                    craterlets: craterlets
                )
                let reflectance = microtexture.reflectanceModulation(
                    eastMeters: sample.x,
                    northMeters: sample.y,
                    sampleSpacingMeters: sampleSpacing,
                    craterlets: craterlets
                )
                #expect(combined.reliefMeters == relief)
                #expect(combined.reflectanceModulation == reflectance)
            }
        }
    }

    @Test func microtextureSuppressesFeaturesBelowTheTexelFootprint() {
        let microtexture = LMRegolithMicrotextureModel()
        var fineReliefEnergy = 0.0
        var coarseReliefEnergy = 0.0
        var fineReflectanceEnergy = 0.0
        var coarseReflectanceEnergy = 0.0

        for northIndex in 0..<24 {
            for eastIndex in 0..<24 {
                let east = 1.25 + Double(eastIndex) * 0.037
                let north = -2.5 + Double(northIndex) * 0.041
                let fine = microtexture.appearanceSample(
                    eastMeters: east,
                    northMeters: north,
                    sampleSpacingMeters: 0.03125
                )
                let coarse = microtexture.appearanceSample(
                    eastMeters: east,
                    northMeters: north,
                    sampleSpacingMeters: 0.5
                )
                fineReliefEnergy += fine.reliefMeters * fine.reliefMeters
                coarseReliefEnergy += coarse.reliefMeters * coarse.reliefMeters
                let fineReflectance = fine.reflectanceModulation - 1
                let coarseReflectance = coarse.reflectanceModulation - 1
                fineReflectanceEnergy += fineReflectance * fineReflectance
                coarseReflectanceEnergy += coarseReflectance * coarseReflectance
            }
        }

        #expect(fineReliefEnergy > 0)
        #expect(fineReflectanceEnergy > 0)
        #expect(coarseReliefEnergy < fineReliefEnergy * 0.01)
        #expect(coarseReflectanceEnergy < fineReflectanceEnergy * 0.01)
    }

    private func landingPlan() throws -> LMTerrainTilePlan {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let frame = try LMTerrainFrameAlignment(manifest: LMTerrainManifest.load())
        let eagle = frame.terrainReferenceTouchdown
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: field.spacingMeters
        ).focusedPlans(
            focusEastMeters: eagle.y,
            focusNorthMeters: eagle.x,
            altitudeMeters: 20
        )
        return try #require(plans.min { $0.sampleSpacingMeters < $1.sampleSpacingMeters })
    }

    @Test func measuredAlbedoIsLoadedAtHalfMeterResolution() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let albedo = try LMMeasuredAlbedoField.load(tile: field.tile)
        #expect(albedo.width == 4_097)
        #expect(albedo.height == 4_097)
        let reflectance = try #require(albedo.reflectance(eastMeters: 0, northMeters: 0))
        #expect(reflectance > 0)
        #expect(reflectance < 1)
        #expect(albedo.reflectance(eastMeters: 5_000, northMeters: 0) == nil)
    }

    @Test func bakedDetailIsFinerThanBothTheMeshAndTheSourceTexture() throws {
        let plan = try landingPlan()
        let texelSpacing = plan.sizeMeters
            / Double(LMTerrainTileDetailBaker.resolution - 1)
        // Finer than the 0.125 m triangles and far finer than 0.5 m NAC texels.
        #expect(texelSpacing < plan.sampleSpacingMeters)
        #expect(texelSpacing < 0.5)
    }

    @Test func appearanceHandoffTargetsTheRenderedParentFrequency() {
        let landing = LMTerrainTilePlan(
            id: .init(level: 1, eastIndex: 0, northIndex: 0),
            centerEastMeters: 8,
            centerNorthMeters: 8,
            sizeMeters: 16,
            sampleSpacingMeters: 0.125,
            containsProceduralSubresolution: true
        )
        let terminal = LMTerrainTilePlan(
            id: .init(level: 0, eastIndex: 0, northIndex: 0),
            centerEastMeters: 32,
            centerNorthMeters: 32,
            sizeMeters: 64,
            sampleSpacingMeters: 0.5,
            containsProceduralSubresolution: true
        )
        let landingTexelSpacing = landing.sizeMeters
            / Double(LMTerrainTileDetailBaker.resolution - 1)
        let terminalTexelSpacing = terminal.sizeMeters
            / Double(LMTerrainTileDetailBaker.resolution - 1)

        #expect(abs(
            LMTerrainTileDetailBaker.parentAppearanceSampleSpacingMeters(
                plan: landing,
                texelSpacingMeters: landingTexelSpacing
            )! - terminalTexelSpacing
        ) < 1e-12)
        #expect(LMTerrainTileDetailBaker.parentAppearanceSampleSpacingMeters(
            plan: terminal,
            texelSpacingMeters: terminalTexelSpacing
        ) == nil)
    }

    @Test func bakedNormalDistributionCanBeReusedForAnySunDirection() throws {
        #expect(LMTerrainTileDetailBaker.modelID == "regolith-microtexture-v2")
        #expect(LMTerrainTileDetailBaker.normalReliefScale == 0.30)
        let detail = try LMTerrainTileDetailBaker.bake(
            plan: landingPlan(),
            albedoField: nil,
            resolution: 64
        )
        let distribution = detail.normalDistribution
        let overhead = distribution.meanLambertianResponse(
            sunDirectionTangentSpace: SIMD3<Float>(0, 0, 1)
        )
        let grazingEast = distribution.meanLambertianResponse(
            sunDirectionTangentSpace: simd_normalize(SIMD3<Float>(1, 0, 0.2))
        )

        #expect(distribution.sampleCount == 64 * 64)
        #expect(distribution.counts.reduce(0) { $0 + Int($1) } == 64 * 64)
        #expect(overhead > 0.9)
        #expect(grazingEast > 0)
        #expect(grazingEast < overhead)
    }

    @Test func touchdownReliefStatisticsDoNotRequireAnLODGain() throws {
        let plan = try landingPlan()
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let mesh = try #require(
            try Apollo11TerrainResource.makeProgressiveTileMeshData(
                heightField: field,
                plan: plan,
                activePlans: [plan]
            )
        )
        let detail = try LMTerrainTileDetailBaker.bake(
            plan: plan,
            albedoField: nil,
            resolution: LMTerrainTileDetailBaker.resolution
        )
        let manifest = try LMTerrainManifest.load()
        let elevation = Float(manifest.sun.elevationDegrees * .pi / 180)
        let azimuth = Float(
            manifest.sun.azimuthDegreesClockwiseFromNorth * .pi / 180
        )
        let horizontal = cos(elevation)
        let tangentSun = simd_normalize(SIMD3<Float>(
            horizontal * sin(azimuth),
            -horizontal * cos(azimuth),
            sin(elevation)
        ))
        let flatResponse = tangentSun.z
        let detailResponse = detail.normalDistribution
            .meanLambertianResponse(sunDirectionTangentSpace: tangentSun)
        let meshResponse = mesh.addedReliefNormalDistribution
            .meanLambertianResponse(sunDirectionTangentSpace: tangentSun)
        let combinedRatio = (detailResponse / flatResponse)
            * (meshResponse / flatResponse)

        // The old B1 hypothesis predicted a 5-6% mean loss. The current,
        // hierarchy-corrected tile is neutral to 0.03%, so a material gain
        // would manufacture a new LOD step instead of removing one.
        #expect(abs(combinedRatio - 1) < 0.005)
    }

    @Test func renderingGutterKeepsSamplingInsideRepeatedBoundaryTexels() {
        let resolution = LMTerrainTileDetailBaker.resolution
        var albedo = [UInt8](repeating: 0, count: resolution * resolution * 4)
        var normal = [UInt8](repeating: 0, count: resolution * resolution * 4)

        func setPixel(
            _ bytes: inout [UInt8],
            column: Int,
            row: Int,
            value: (UInt8, UInt8, UInt8, UInt8)
        ) {
            let offset = (row * resolution + column) * 4
            bytes[offset] = value.0
            bytes[offset + 1] = value.1
            bytes[offset + 2] = value.2
            bytes[offset + 3] = value.3
        }

        setPixel(&albedo, column: 0, row: 0, value: (11, 12, 13, 14))
        setPixel(
            &albedo,
            column: resolution - 1,
            row: resolution - 1,
            value: (21, 22, 23, 24)
        )
        setPixel(&normal, column: 0, row: 0, value: (31, 32, 33, 34))
        setPixel(
            &normal,
            column: resolution - 1,
            row: resolution - 1,
            value: (41, 42, 43, 44)
        )

        let padded = LMTerrainTileDetailBaker.addingSamplingGutter(
            to: LMTerrainTileDetailTextures(
                resolution: resolution,
                albedo: albedo,
                normal: normal
            )
        )
        let gutter = LMTerrainTileDetailBaker.samplingGutterTexels
        let renderingResolution = LMTerrainTileDetailBaker.renderingResolution

        func pixel(_ bytes: [UInt8], column: Int, row: Int) -> [UInt8] {
            let offset = (row * renderingResolution + column) * 4
            return Array(bytes[offset..<(offset + 4)])
        }

        #expect(padded.resolution == renderingResolution)
        #expect(padded.normalDistribution == .flat)
        #expect(pixel(padded.albedo, column: 0, row: 0) == [11, 12, 13, 14])
        #expect(pixel(padded.albedo, column: gutter, row: gutter) == [11, 12, 13, 14])
        #expect(pixel(padded.normal, column: 0, row: 0) == [31, 32, 33, 34])
        #expect(pixel(padded.normal, column: gutter, row: gutter) == [31, 32, 33, 34])
        #expect(pixel(
            padded.albedo,
            column: renderingResolution - 1,
            row: renderingResolution - 1
        ) == [21, 22, 23, 24])
        #expect(pixel(
            padded.normal,
            column: renderingResolution - 1,
            row: renderingResolution - 1
        ) == [41, 42, 43, 44])

        let minimumUV = LMTerrainTileDetailBaker.renderingTextureCoordinate(
            contentFraction: 0
        )
        let maximumUV = LMTerrainTileDetailBaker.renderingTextureCoordinate(
            contentFraction: 1
        )
        #expect(minimumUV > 0)
        #expect(maximumUV < 1)
        #expect(abs(
            minimumUV * Float(renderingResolution - 1) - Float(gutter)
        ) < 0.0001)
        #expect(abs(
            maximumUV * Float(renderingResolution - 1)
                - Float(gutter + resolution - 1)
        ) < 0.0001)
    }

    @Test func bakedNormalsAreUnitLengthAndFadeFlatAtTheTileEdge() throws {
        let plan = try landingPlan()
        // Bake near the shipping density: at 0.25 m texels the centimetre-scale
        // microtexture aliases away and the test would measure nothing.
        let resolution = 256
        let detail = try LMTerrainTileDetailBaker.bake(
            plan: plan,
            albedoField: nil,
            resolution: resolution
        )
        #expect(detail.resolution == resolution)
        #expect(detail.normal.count == resolution * resolution * 4)

        func normal(column: Int, row: Int) -> SIMD3<Float> {
            let offset = (row * resolution + column) * 4
            return SIMD3(
                Float(detail.normal[offset]) / 255 * 2 - 1,
                Float(detail.normal[offset + 1]) / 255 * 2 - 1,
                Float(detail.normal[offset + 2]) / 255 * 2 - 1
            )
        }

        for row in stride(from: 0, to: resolution, by: 7) {
            for column in stride(from: 0, to: resolution, by: 7) {
                let length = simd_length(normal(column: column, row: row))
                #expect(abs(length - 1) < 0.02)
            }
        }

        // The outer collar hands off to the coarser parent surface, so the
        // baked detail has to vanish there rather than end on a hard seam.
        let corner = normal(column: 0, row: 0)
        #expect(abs(corner.x) < 0.01)
        #expect(abs(corner.y) < 0.01)
        #expect(corner.z > 0.99)

        let interior = (0..<resolution).flatMap { row in
            (0..<resolution).map { column in
                simd_length(SIMD2(normal(column: column, row: row).x,
                                  normal(column: column, row: row).y))
            }
        }.max() ?? 0
        // The restrained v2 realization still has a materially non-flat
        // interior; its screen-space strength is intentionally below v1.
        #expect(interior > 0.04)
    }

    @Test func adjacentProceduralTexturesMatchExactlyAtTheirSharedWorldEdge() throws {
        let resolution = 64
        let west = LMTerrainTilePlan(
            id: .init(level: 1, eastIndex: 0, northIndex: 0),
            centerEastMeters: 8,
            centerNorthMeters: 8,
            sizeMeters: 16,
            sampleSpacingMeters: 0.125,
            containsProceduralSubresolution: true,
            transitionEdges: [.west, .south, .north]
        )
        let east = LMTerrainTilePlan(
            id: .init(level: 1, eastIndex: 1, northIndex: 0),
            centerEastMeters: 24,
            centerNorthMeters: 8,
            sizeMeters: 16,
            sampleSpacingMeters: 0.125,
            containsProceduralSubresolution: true,
            transitionEdges: [.east, .south, .north]
        )
        let westDetail = try LMTerrainTileDetailBaker.bake(
            plan: west,
            albedoField: nil,
            resolution: resolution
        )
        let eastDetail = try LMTerrainTileDetailBaker.bake(
            plan: east,
            albedoField: nil,
            resolution: resolution
        )

        for row in 0..<resolution {
            let westOffset = (row * resolution + resolution - 1) * 4
            let eastOffset = row * resolution * 4
            #expect(westDetail.albedo[westOffset..<(westOffset + 4)]
                .elementsEqual(eastDetail.albedo[eastOffset..<(eastOffset + 4)]))
            #expect(westDetail.normal[westOffset..<(westOffset + 4)]
                .elementsEqual(eastDetail.normal[eastOffset..<(eastOffset + 4)]))
        }
    }

    @Test func adjacentMeasuredAlbedoNarrowBandsRemainContinuous() throws {
        let resolution = 128
        let west = try landingPlan().withTransitionEdges([])
        let east = LMTerrainTilePlan(
            id: .init(
                level: west.id.level,
                eastIndex: west.id.eastIndex + 1,
                northIndex: west.id.northIndex
            ),
            centerEastMeters: west.centerEastMeters + west.sizeMeters,
            centerNorthMeters: west.centerNorthMeters,
            sizeMeters: west.sizeMeters,
            sampleSpacingMeters: west.sampleSpacingMeters,
            containsProceduralSubresolution: true,
            transitionEdges: []
        )
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let measured = try LMMeasuredAlbedoField.load(tile: field.tile)
        let westDetail = try LMTerrainTileDetailBaker.bake(
            plan: west,
            albedoField: measured,
            resolution: resolution
        )
        let eastDetail = try LMTerrainTileDetailBaker.bake(
            plan: east,
            albedoField: measured,
            resolution: resolution
        )
        let south = LMTerrainTilePlan(
            id: .init(
                level: west.id.level,
                eastIndex: west.id.eastIndex,
                northIndex: west.id.northIndex - 1
            ),
            centerEastMeters: west.centerEastMeters,
            centerNorthMeters: west.centerNorthMeters - west.sizeMeters,
            sizeMeters: west.sizeMeters,
            sampleSpacingMeters: west.sampleSpacingMeters,
            containsProceduralSubresolution: true,
            transitionEdges: []
        )
        let southDetail = try LMTerrainTileDetailBaker.bake(
            plan: south,
            albedoField: measured,
            resolution: resolution
        )
        func mean(_ detail: LMTerrainTileDetailTextures, columns: Range<Int>) -> Double {
            var total = 0.0
            var count = 0
            for row in 0..<resolution {
                for column in columns {
                    total += Double(detail.albedo[(row * resolution + column) * 4]) / 255
                    count += 1
                }
            }
            return total / Double(count)
        }
        let westBand = mean(
            westDetail,
            columns: (resolution - 8)..<resolution
        )
        let eastBand = mean(eastDetail, columns: 0..<8)
        #expect(abs(eastBand - westBand) / westBand < 0.005)

        func mean(_ detail: LMTerrainTileDetailTextures, rows: Range<Int>) -> Double {
            var total = 0.0
            var count = 0
            for row in rows {
                for column in 0..<resolution {
                    total += Double(detail.albedo[(row * resolution + column) * 4]) / 255
                    count += 1
                }
            }
            return total / Double(count)
        }
        let northSouthBand = mean(
            westDetail,
            rows: (resolution - 8)..<resolution
        )
        let southNorthBand = mean(southDetail, rows: 0..<8)
        #expect(abs(southNorthBand - northSouthBand) / northSouthBand < 0.01)
        for column in 0..<resolution {
            let northOffset = ((resolution - 1) * resolution + column) * 4
            let southOffset = column * 4
            #expect(westDetail.albedo[northOffset..<(northOffset + 4)]
                .elementsEqual(southDetail.albedo[southOffset..<(southOffset + 4)]))
        }
    }

    @Test func progressiveTileUVsMapNorthImageRowsToTextureTop() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let plan = try landingPlan()
        let mesh = try #require(
            try Apollo11TerrainResource.makeProgressiveTileMeshData(
                heightField: field,
                plan: plan
            )
        )
        let sampleCount = Int(plan.sizeMeters / plan.sampleSpacingMeters) + 1
        let northWest = mesh.textureCoordinates[0]
        let southWest = mesh.textureCoordinates[(sampleCount - 1) * sampleCount]
        #expect(northWest.y > southWest.y)
        #expect(abs(northWest.x - southWest.x) < 1e-6)
    }

    @Test func bakedAlbedoTracksMeasuredReflectanceWithBoundedContrast() throws {
        let plan = try landingPlan()
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let albedoField = try LMMeasuredAlbedoField.load(tile: field.tile)
        let detail = try LMTerrainTileDetailBaker.bake(
            plan: plan,
            albedoField: albedoField,
            resolution: 64
        )

        let measured = try #require(albedoField.reflectance(
            eastMeters: plan.centerEastMeters,
            northMeters: plan.centerNorthMeters
        ))
        var minimum = 1.0
        var maximum = 0.0
        for index in stride(from: 0, to: detail.albedo.count, by: 4) {
            let value = Double(detail.albedo[index]) / 255
            minimum = min(minimum, value)
            maximum = max(maximum, value)
        }
        // Procedural contrast modulates the measured reflectance; it never
        // replaces it, so the baked range brackets the source value.
        #expect(minimum < Double(measured))
        #expect(maximum > Double(measured))
        #expect(minimum > Double(measured) * 0.7)
        // Byte quantization plus sampling the exact tile boundary can exceed
        // the nominal 1.35 modulation by one output step.
        #expect(maximum < Double(measured) * 1.4)
    }

    @Test func microtextureNeverReachesTheGeometryOrContactSurface() throws {
        let microtexture = LMRegolithMicrotextureModel()
        var maximumRelief = 0.0
        for north in stride(from: 0.0, through: 4.0, by: 0.03) {
            for east in stride(from: 0.0, through: 4.0, by: 0.03) {
                maximumRelief = max(
                    maximumRelief,
                    abs(microtexture.reliefMeters(eastMeters: east, northMeters: north))
                )
            }
        }
        #expect(maximumRelief > 0.001)
        #expect(maximumRelief <= LMRegolithMicrotextureModel.maximumReliefMeters + 1e-9)

        // The height field the gear touches is built from the geology model
        // alone, so appearance micro-relief can never move a footpad.
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sampler = LMProgressiveTerrainSurfaceSampler(heightField: field)
        let sample = try #require(sampler.sample(
            eastMeters: 3,
            northMeters: 3,
            altitudeMeters: 20,
            activePlans: []
        ))
        #expect(sample.renderedElevationMeters == sample.measuredElevationMeters)
    }

    @Test func craterFieldMemoizationDoesNotChangeTheSurface() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let plan = try landingPlan()
        let plain = LMProgressiveTerrainSurfaceSampler(heightField: field)
        let prepared = plain.prepared(for: plan)
        let step = plan.sizeMeters / 32

        for row in 0...32 {
            let north = plan.centerNorthMeters - plan.sizeMeters / 2 + Double(row) * step
            for column in 0...32 {
                let east = plan.centerEastMeters - plan.sizeMeters / 2 + Double(column) * step
                let a = plain.renderedElevation(
                    eastMeters: east,
                    northMeters: north,
                    plan: plan
                )
                let b = prepared.renderedElevation(
                    eastMeters: east,
                    northMeters: north,
                    plan: plan
                )
                #expect(a == b)
            }
        }
    }
}
