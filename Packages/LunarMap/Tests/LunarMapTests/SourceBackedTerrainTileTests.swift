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

@Suite("Source-backed terrain tiles")
struct SourceBackedTerrainTileTests {
    @Test func ownershipPreparationRetainsExactUncoveredTriangles() throws {
        let grid = LMTerrainMeshBuilder.VertexData(
            positions: [SIMD3(0, 0, 0), SIMD3(0, 0, -2),
                        SIMD3(2, 0, 0), SIMD3(2, 0, -2)],
            normals: Array(repeating: SIMD3(0, 1, 0), count: 4),
            texCoords: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)],
            triangles: [0, 1, 2, 1, 3, 2])
        let owner = LMTerrainTilePlan(
            id: .init(level: 0, eastIndex: 0, northIndex: 0),
            centerEastMeters: 0, centerNorthMeters: 0, sizeMeters: 2,
            sampleSpacingMeters: 0.5, containsProceduralSubresolution: true)
        let masked = try LMTerrainMeshBuilder.excludingProgressiveFootprints(
            from: grid, plans: [owner])
        #expect(masked.triangles == [1, 3, 2])
        #expect(masked.positions == grid.positions)
        #expect(masked.normals == grid.normals)
        #expect(masked.texCoords == grid.texCoords)
        let restored = try LMTerrainMeshBuilder.excludingProgressiveFootprints(
            from: grid, plans: [])
        #expect(restored.triangles == grid.triangles)
    }

    @Test func cancelledOwnershipPreparationDoesNotImportAMesh() async {
        let grid = LMTerrainMeshBuilder.VertexData(
            positions: [], normals: [], texCoords: [], triangles: [])
        await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) {
                try LMTerrainMeshBuilder.excludingProgressiveFootprints(from: grid, plans: [])
            }
            do {
                _ = try await LMTerrainMeshBuilder.meshAsync(from: grid)
                Issue.record("Cancelled preparation imported an invalid mesh")
            } catch {
                #expect(error is CancellationError)
            }
        }.value
    }

    @Test func cancelledBasePreparationStopsBeforeReadingResources() async throws {
        let manifest = try LMTerrainManifest.load()
        await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            // Foundation has no terrain assets. Cancellation must win over
            // attempting their decode and throwing a missing-resource error.
            #expect(throws: CancellationError.self) {
                try LMTerrainWorld.prepareBaseBands(
                    manifest: manifest, bundle: Bundle(for: NSObject.self))
            }
        }.value
    }

    @Test @MainActor func terrainSamplingMinifiesDenseBandsWithoutAliasing() {
        let colorOptions = LMTerrainWorld.terrainTextureCreateOptions(
            semantic: .color
        )
        #expect(colorOptions.semantic == .color)
        #expect(colorOptions.mipmapsMode == .allocateAndGenerateAll)

        let sampler = LMTerrainWorld.terrainTextureSampler()
        sampler.access { descriptor in
            #expect(descriptor.minFilter == .linear)
            #expect(descriptor.magFilter == .linear)
            #expect(descriptor.mipFilter == .linear)
            #expect(descriptor.maxAnisotropy == 8)
            #expect(descriptor.sAddressMode == .clampToEdge)
            #expect(descriptor.tAddressMode == .clampToEdge)
        }
    }

    @Test func missionSunDirectionAndExposureFloorPreserveLowSunRelief() throws {
        let manifest = try LMTerrainManifest.load()
        let illuminationDirection = LMFullDescentMapper
            .sunLightOrientation(from: manifest)
            .act(SIMD3<Float>(0, 0, -1))
        let expectedDirection = -LMFullDescentMapper.sunDirection(from: manifest)

        #expect(simd_dot(illuminationDirection, expectedDirection) > 0.999_99)
        #expect(illuminationDirection.y < 0)
        #expect(LMTerrainWorld.missionSunIlluminanceLux == 25_000)
        #expect(LMTerrainWorld.missionShadowMinimumDistanceMeters == 12)
        #expect(LMTerrainWorld.missionShadowMaximumDistanceMeters == 45)
        #expect(LMTerrainWorld.missionShadowDistance(altitudeMeters: 0) == 12)
        #expect(LMTerrainWorld.missionShadowDistance(altitudeMeters: 20) == 35)
        #expect(LMTerrainWorld.missionShadowDistance(altitudeMeters: 100) == 45)
        #expect(LMTerrainWorld.regolithExposureFloor > 0)
        #expect(LMTerrainWorld.regolithExposureFloor < 1)
    }

    @Test func missionSunMeanGeometryShadingDoesNotNeedGlobalLODGain() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sun = LMFullDescentMapper.sunDirection(from: try LMTerrainManifest.load())
        let centers: [(east: Double, north: Double)] = [
            (-4.336, 19.619),
            (-20, 4),
            (12, 36),
            (28, 12),
        ]

        func meanShading(spacing: Double, level: Int) throws -> Double {
            var total = Double.zero
            var count = 0
            for center in centers {
                let plan = LMTerrainTilePlan(
                    id: .init(level: level, eastIndex: 0, northIndex: 0),
                    centerEastMeters: center.east,
                    centerNorthMeters: center.north,
                    sizeMeters: 16,
                    sampleSpacingMeters: spacing,
                    containsProceduralSubresolution: spacing < field.spacingMeters,
                    transitionEdges: []
                )
                let generated = try Apollo11TerrainResource.makeProgressiveTileMeshData(
                    heightField: field,
                    plan: plan,
                    activePlans: [plan]
                )
                let mesh = try #require(generated)
                let posts = Int(plan.sizeMeters / spacing) + 1
                for row in 1..<(posts - 1) {
                    for column in 1..<(posts - 1) {
                        let normal = mesh.normals[row * posts + column]
                        total += Double(max(simd_dot(normal, sun), 0))
                        count += 1
                    }
                }
            }
            return total / Double(count)
        }

        let measured = try meanShading(spacing: 2, level: 2)
        let terminal = try meanShading(spacing: 0.5, level: 0)
        let landing = try meanShading(spacing: 0.125, level: 1)
        #expect(measured > 0)
        #expect(terminal > 0)
        #expect(landing > 0)
        #expect(abs(measured / terminal - 1) < 0.005)
        #expect(abs(measured / landing - 1) < 0.005)
    }

    @Test func progressiveMeshCarriesItsSunIndependentAddedReliefDistribution() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let plan = LMTerrainTilePlan(
            id: .init(level: 1, eastIndex: 0, northIndex: 0),
            centerEastMeters: -4.336,
            centerNorthMeters: 19.619,
            sizeMeters: 16,
            sampleSpacingMeters: 0.125,
            containsProceduralSubresolution: true,
            transitionEdges: []
        )
        let generated = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: plan,
            activePlans: [plan]
        )
        let mesh = try #require(generated)
        let posts = Int(plan.sizeMeters / plan.sampleSpacingMeters) + 1
        let distribution = mesh.addedReliefNormalDistribution

        #expect(distribution.sampleCount == posts * posts)
        #expect(distribution.counts.reduce(0, +) == UInt32(posts * posts))
        #expect(distribution != .flat)
        let overhead = distribution.meanLambertianResponse(
            sunDirectionTangentSpace: SIMD3(0, 0, 1)
        )
        let grazing = distribution.meanLambertianResponse(
            sunDirectionTangentSpace: simd_normalize(SIMD3(0.8, 0, 0.6))
        )
        #expect(overhead > 0.9)
        #expect(grazing > 0)
        #expect(grazing < overhead)
    }

    @Test @MainActor func explorerLandingTileMissionSunShadingVariationNeedsNoPerTileGain() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: field.spacingMeters)
        let focusEast = -4.336
        let focusNorth = 19.619
        // The production Surface view has a continuous 48 m forward / 32 m
        // rear corridor. The former velocity-prefetch fixture left gaps.
        let forward = planner.viewCorridorPlans(
            focusEastMeters: focusEast,
            focusNorthMeters: focusNorth,
            headingDegrees: 0,
            forwardDistanceMeters: 48,
            altitudeMeters: 2
        )
        let rear = planner.viewCorridorPlans(
            focusEastMeters: focusEast,
            focusNorthMeters: focusNorth,
            headingDegrees: 180,
            forwardDistanceMeters: 32,
            altitudeMeters: 2
        )
        let plans = planner.mergedPlans(forward + rear)
        let surface = LMProgressiveTerrainSurfaceSampler(heightField: field, planner: planner)
        let manifest = try LMTerrainManifest.load()
        let sun = LMFullDescentMapper.sunDirection(from: LMLunarEphemeris.sunAngles(
            at: LunarExplorerSession.apollo11TouchdownUTC,
            site: manifest.landingOriginCoordinate
        ))
        var meshes = [LMTerrainTileID: LMProgressiveTerrainMeshData]()

        func shading(east: Double, north: Double, plan: LMTerrainTilePlan) throws -> Double {
            let mesh: LMProgressiveTerrainMeshData
            if let cached = meshes[plan.id] {
                mesh = cached
            } else {
                let generated = try Apollo11TerrainResource.makeProgressiveTileMeshData(
                    heightField: field, plan: plan, activePlans: plans
                )
                mesh = try #require(generated)
                meshes[plan.id] = mesh
            }
            let posts = Int(plan.sizeMeters / plan.sampleSpacingMeters) + 1
            let column = (east - plan.centerEastMeters + plan.sizeMeters / 2) / plan.sampleSpacingMeters
            let row = (plan.centerNorthMeters + plan.sizeMeters / 2 - north) / plan.sampleSpacingMeters
            let x = min(Int(column.rounded(.down)), posts - 2)
            let y = min(Int(row.rounded(.down)), posts - 2)
            let tx = Float(column - Double(x))
            let ty = Float(row - Double(y))
            let nw = mesh.normals[y * posts + x]
            let ne = mesh.normals[y * posts + x + 1]
            let sw = mesh.normals[(y + 1) * posts + x]
            let se = mesh.normals[(y + 1) * posts + x + 1]
            // Interpolate the actual NW/NE/SW and NE/SE/SW mesh triangles,
            // including the normalization performed by the fragment shader.
            let normal = tx + ty <= 1
                ? nw * (1 - tx - ty) + ne * tx + sw * ty
                : ne * (1 - ty) + se * (tx + ty - 1) + sw * (1 - tx)
            return Double(max(simd_dot(simd_normalize(normal), sun), 0))
        }

        var ratios = [Double]()
        var largestSamplingDelta = 0.0
        for child in plans where child.sampleSpacingMeters == 0.125 {
            let parent = try #require(surface.parentPlan(
                for: child, eastMeters: child.centerEastMeters,
                northMeters: child.centerNorthMeters, activePlans: plans
            ))
            var childTotal = Double.zero
            var parentTotal = Double.zero
            var coarseChildTotal = Double.zero
            var coarseParentTotal = Double.zero
            // Integrate the complete 16 m tile at its rendered post spacing.
            // The former 49-point, 6 m central window could overrepresent one
            // crater and was not a measurement of mean tile radiance.
            let intervals = Int(child.sizeMeters / child.sampleSpacingMeters)
            for row in 0...intervals {
                for column in 0...intervals {
                    let east = child.centerEastMeters - child.sizeMeters / 2
                        + Double(column) * child.sampleSpacingMeters
                    let north = child.centerNorthMeters + child.sizeMeters / 2
                        - Double(row) * child.sampleSpacingMeters
                    let edgeWeight = (row == 0 || row == intervals ? 0.5 : 1)
                        * (column == 0 || column == intervals ? 0.5 : 1)
                    let childShade = try shading(east: east, north: north, plan: child) * edgeWeight
                    let parentShade = try shading(east: east, north: north, plan: parent) * edgeWeight
                    childTotal += childShade
                    parentTotal += parentShade
                    if row.isMultiple(of: 2), column.isMultiple(of: 2) {
                        coarseChildTotal += childShade
                        coarseParentTotal += parentShade
                    }
                }
            }
            #expect(childTotal > 0)
            let ratio = parentTotal / childTotal
            largestSamplingDelta = max(largestSamplingDelta, abs(ratio - coarseParentTotal / coarseChildTotal))
            ratios.append(ratio)
        }
        // Halving integration spacing must change the ratio by less than
        // 0.1 percentage point, well below the unchanged 2% tile limit.
        #expect(largestSamplingDelta < 0.001)
        #expect(ratios.count == 24)
        #expect(ratios.allSatisfy { abs($0 - 1) < 0.02 }, "Per-tile parent/child shading ratios: \(ratios)")
        let meanRatio = ratios.reduce(0, +) / Double(ratios.count)
        #expect(abs(meanRatio - 1) < 0.005)
        print("Explorer realized-normal shading ratios: count=\(ratios.count) min=\(ratios.min() ?? 0) max=\(ratios.max() ?? 0) mean=\(meanRatio) samplingDelta=\(largestSamplingDelta)")
    }

    @Test func apollo11TerrainAssetsRemainByteIdenticalToStage1() throws {
        let expectedSHA256 = [
            "near-field-height.png": "8d35110db46f21e3fb62a8de8dced3700cf8bcf79c449493583bf53f23e56027",
            "medium-field-height.png": "7baf81ee1c182159c9e308ff922d6f543dc23606819a82d0e79e97babef8c06d",
            "far-field-height.png": "9e1c571eeb02b4b50b980ecdf60cd5bcd3cdcd0511ea9fcfa53bba1c0f903802",
            "near-field-albedo.png": "5cc754af24b02b2bd3fae183cccf3adc0e5bbb4c386a2357debd13d2fe6d3fff",
            "medium-field-albedo.png": "2631b675920293aecc7cb37f7a4b93b67079f0bdba53174dbb672a3b7637311e",
            "far-field-albedo.png": "9e48c12b48f80fa61ac6184172a9254351ea248b95b6a7b07ce2a7d00d7065c0",
        ]
        let terrainDirectory = try #require(LunarMap.resources.resourceURL)
            .appendingPathComponent("Terrain", isDirectory: true)

        for (file, expectedDigest) in expectedSHA256 {
            let data = try Data(
                contentsOf: terrainDirectory.appendingPathComponent(file),
                options: .mappedIfSafe
            )
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            #expect(digest == expectedDigest, "\(file) changed from the accepted Stage 1 bytes")
        }
    }

    @Test func nestedAlbedoBandsAreNonFlatAndShareBoundaryReflectance() throws {
        let manifest = try LMTerrainManifest.load()
        let nearTile = try #require(manifest.tile(id: LMTerrainWorld.nearFieldTileID))
        let mediumTile = try #require(manifest.tile(id: LMTerrainWorld.mediumFieldTileID))
        let farTile = try #require(manifest.tile(id: LMTerrainWorld.farFieldTileID))
        let near = try albedoImage(for: nearTile)
        let medium = try albedoImage(for: mediumTile)
        let far = try albedoImage(for: farTile)

        #expect(near.width == 4_097 && near.height == 4_097)
        #expect(medium.width == 513 && medium.height == 513)
        #expect(far.width == 513 && far.height == 513)
        #expect(Int(near.pixels.max() ?? 0) - Int(near.pixels.min() ?? 0) > 20)
        #expect(Int(medium.pixels.max() ?? 0) - Int(medium.pixels.min() ?? 0) > 10)
        #expect(Int(far.pixels.max() ?? 0) - Int(far.pixels.min() ?? 0) > 70)

        // The 2,048 m near texture boundary lands on medium indices 224...288.
        for index in 0...64 {
            let nearIndex = index * 64
            let mediumIndex = 224 + index
            expectSameAlbedo(near, 0, nearIndex, medium, 224, mediumIndex)
            expectSameAlbedo(near, 4_096, nearIndex, medium, 288, mediumIndex)
            expectSameAlbedo(near, nearIndex, 0, medium, mediumIndex, 224)
            expectSameAlbedo(near, nearIndex, 4_096, medium, mediumIndex, 288)
        }

        // The 16,384 m medium texture boundary lands on far indices 240...272.
        for index in 0...32 {
            let mediumIndex = index * 16
            let farIndex = 240 + index
            expectSameAlbedo(medium, 0, mediumIndex, far, 240, farIndex)
            expectSameAlbedo(medium, 512, mediumIndex, far, 272, farIndex)
            expectSameAlbedo(medium, mediumIndex, 0, far, farIndex, 240)
            expectSameAlbedo(medium, mediumIndex, 512, far, farIndex, 272)
        }
    }

    @Test func nearAlbedoKeepsLandingDetailWithoutExposingSquareCrop() throws {
        let manifest = try LMTerrainManifest.load()
        let nearTile = try #require(manifest.tile(id: LMTerrainWorld.nearFieldTileID))
        let mediumTile = try #require(manifest.tile(id: LMTerrainWorld.mediumFieldTileID))
        let near = try albedoImage(for: nearTile)
        let medium = try albedoImage(for: mediumTile)

        // At the landing-site origin the 0.5 m NAC residual remains plainly
        // present over the WAC parent value.
        let centerResidual = abs(Int(near[2_048, 2_048]) - Int(medium[256, 256]))
        #expect(centerResidual >= 8)

        // At equal-radius samples near the first tile edge, and outside the
        // inscribed radial footprint, the result has returned to the WAC
        // parent. A square edge-distance mask would retain detail at the
        // diagonal sample and make the crop visible in regional views.
        let handoffSamples = [
            (nearRow: 2_048, nearColumn: 3_968, mediumRow: 256, mediumColumn: 286),
            (nearRow: 2_048, nearColumn: 128, mediumRow: 256, mediumColumn: 226),
            (nearRow: 128, nearColumn: 2_048, mediumRow: 226, mediumColumn: 256),
            (nearRow: 3_968, nearColumn: 2_048, mediumRow: 286, mediumColumn: 256),
            (nearRow: 512, nearColumn: 512, mediumRow: 232, mediumColumn: 232),
        ]
        for sample in handoffSamples {
            expectSameAlbedo(
                near,
                sample.nearRow,
                sample.nearColumn,
                medium,
                sample.mediumRow,
                sample.mediumColumn
            )
        }
    }

    @Test func nativeNearFieldDrivesTheProductionSampler() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        #expect(field.width == 1_025)
        #expect(field.height == 1_025)
        #expect(abs(field.spacingMeters - 2) < 1e-9)
        #expect(field.heights.count == 1_025 * 1_025)
        #expect(field.heights.allSatisfy { $0.isFinite })

        let origin = try #require(field.relativeElevation(eastMeters: 0, northMeters: 0))
        #expect(abs(origin) < 5)
        #expect(field.relativeElevation(eastMeters: 757, northMeters: -540) != nil)
    }

    @Test func nestedTerrainBandsShareQuantizedBoundaryHeights() throws {
        let manifest = try LMTerrainManifest.load()
        let near = try #require(manifest.tile(id: LMTerrainWorld.nearFieldTileID))
        let medium = try #require(manifest.tile(id: LMTerrainWorld.mediumFieldTileID))
        let far = try #require(manifest.tile(id: LMTerrainWorld.farFieldTileID))
        let nearMap = try heightMap(for: near)
        let mediumMap = try heightMap(for: medium)
        let farMap = try heightMap(for: far)

        // The 2,048 m NAC boundary lands on medium indices 224...288.
        for index in 0...64 {
            let nearIndex = index * 16
            let mediumIndex = 224 + index
            try expectSameHeight(nearMap, near, 0, nearIndex, mediumMap, medium, 224, mediumIndex, 0.02)
            try expectSameHeight(nearMap, near, 1_024, nearIndex, mediumMap, medium, 288, mediumIndex, 0.02)
            try expectSameHeight(nearMap, near, nearIndex, 0, mediumMap, medium, mediumIndex, 224, 0.02)
            try expectSameHeight(nearMap, near, nearIndex, 1_024, mediumMap, medium, mediumIndex, 288, 0.02)
        }

        // The 16,384 m medium boundary lands on far indices 240...272.
        for index in 0...32 {
            let mediumIndex = index * 16
            let farIndex = 240 + index
            try expectSameHeight(mediumMap, medium, 0, mediumIndex, farMap, far, 240, farIndex, 0.27)
            try expectSameHeight(mediumMap, medium, 512, mediumIndex, farMap, far, 272, farIndex, 0.27)
            try expectSameHeight(mediumMap, medium, mediumIndex, 0, farMap, far, farIndex, 240, 0.27)
            try expectSameHeight(mediumMap, medium, mediumIndex, 512, farMap, far, farIndex, 272, 0.27)
        }
    }

    @Test func nestedMeshHolesEndOnSharedGridLines() throws {
        let manifest = try LMTerrainManifest.load()
        let medium = try #require(manifest.tile(id: LMTerrainWorld.mediumFieldTileID))
        let far = try #require(manifest.tile(id: LMTerrainWorld.farFieldTileID))
        let mediumGrid = try LMTerrainMeshBuilder.grid(
            tile: medium,
            heightMap: heightMap(for: medium),
            holeHalfExtentMeters: 1_024
        )
        let farGrid = try LMTerrainMeshBuilder.grid(
            tile: far,
            heightMap: heightMap(for: far),
            holeHalfExtentMeters: 8_192
        )
        #expect(mediumGrid.triangles.count == (512 * 512 - 64 * 64) * 6)
        #expect(farGrid.triangles.count == (512 * 512 - 32 * 32) * 6)
    }

    @Test func measuredTerrainTriangleWindingFacesUpward() throws {
        let manifest = try LMTerrainManifest.load()
        let near = try #require(manifest.tile(id: LMTerrainWorld.nearFieldTileID))
        let grid = try LMTerrainMeshBuilder.grid(
            tile: near,
            heightMap: heightMap(for: near)
        )
        let i0 = Int(grid.triangles[0])
        let i1 = Int(grid.triangles[1])
        let i2 = Int(grid.triangles[2])
        let geometricNormal = simd_normalize(simd_cross(
            grid.positions[i1] - grid.positions[i0],
            grid.positions[i2] - grid.positions[i0]
        ))

        #expect(geometricNormal.y > 0.9)
        #expect(simd_dot(geometricNormal, grid.normals[i0]) > 0.9)
    }

    @Test func measuredMeshUsesNorthUpAndEastBackCoordinates() throws {
        let posts = 8
        let spacing = 2.0
        let tile = LMTerrainManifest.Tile(
            id: "test",
            postsPerSide: posts,
            postSpacingMeters: spacing,
            extentMeters: Double(posts - 1) * spacing,
            zeroPointMeters: 0,
            minimumHeightMeters: 0,
            maximumHeightMeters: 10,
            curvatureCorrected: false,
            edgeHandling: nil,
            sourceIDs: nil,
            nativeSourceSpacingMeters: nil,
            transitionWidthMeters: nil,
            heightFile: "test-height.png",
            albedoFile: "test-albedo.png",
            heightEncoding: .init(format: "PNG_GRAYSCALE_16LE", centimetersPerCount: 1, detail: ""),
            albedoEncoding: .init(format: "PNG_RGB_8", detail: ""),
            detail: nil
        )
        var counts = [UInt16](repeating: 0, count: posts * posts)
        for column in 0..<posts { counts[column] = 1_000 }
        let map = LMTerrainHeightMap(width: posts, height: posts, counts: counts)
        let grid = try LMTerrainMeshBuilder.grid(tile: tile, heightMap: map)

        let halfSpan = Float(Double(posts - 1) / 2 * spacing)
        let northeast = grid.positions[posts - 1]
        #expect(abs(northeast.x - halfSpan) < 1e-4)
        #expect(abs(northeast.z + halfSpan) < 1e-4)
        #expect(abs(northeast.y - 10) < 0.02)
        #expect(grid.normals[(posts - 1) * posts + posts - 1].y > 0.95)
    }

    @Test func measuredMeshNormalsFollowNorthAndEastSlopes() throws {
        let posts = 8
        let spacing = 2.0
        let tile = LMTerrainManifest.Tile(
            id: "slope-test",
            postsPerSide: posts,
            postSpacingMeters: spacing,
            extentMeters: Double(posts - 1) * spacing,
            zeroPointMeters: 0,
            minimumHeightMeters: 0,
            maximumHeightMeters: 100,
            curvatureCorrected: false,
            edgeHandling: nil,
            sourceIDs: nil,
            nativeSourceSpacingMeters: nil,
            transitionWidthMeters: nil,
            heightFile: "test-height.png",
            albedoFile: "test-albedo.png",
            heightEncoding: .init(format: "PNG_GRAYSCALE_16LE", centimetersPerCount: 1, detail: ""),
            albedoEncoding: .init(format: "PNG_RGB_8", detail: ""),
            detail: nil
        )
        let halfSpan = Double(posts - 1) * spacing / 2
        var counts = [UInt16](repeating: 0, count: posts * posts)
        for row in 0..<posts {
            let north = halfSpan - Double(row) * spacing
            for column in 0..<posts {
                let east = Double(column) * spacing - halfSpan
                let heightMeters = 50 + 0.5 * north + 0.25 * east
                counts[row * posts + column] = UInt16((heightMeters * 100).rounded())
            }
        }
        let map = LMTerrainHeightMap(width: posts, height: posts, counts: counts)
        let grid = try LMTerrainMeshBuilder.grid(tile: tile, heightMap: map)
        let normal = grid.normals[3 * posts + 3]
        let expected = simd_normalize(SIMD3<Float>(-0.5, 1, 0.25))

        #expect(simd_distance(normal, expected) < 1e-5)
    }

    @Test func measuredGeometryAndNormalLODHandOffRadiallyToParent() throws {
        func tile(id: String, posts: Int, spacing: Double) -> LMTerrainManifest.Tile {
            LMTerrainManifest.Tile(
                id: id,
                postsPerSide: posts,
                postSpacingMeters: spacing,
                extentMeters: Double(posts - 1) * spacing,
                zeroPointMeters: 0,
                minimumHeightMeters: 0,
                maximumHeightMeters: 100,
                curvatureCorrected: false,
                edgeHandling: nil,
                sourceIDs: nil,
                nativeSourceSpacingMeters: nil,
                transitionWidthMeters: nil,
                heightFile: "test-height.png",
                albedoFile: "test-albedo.png",
                heightEncoding: .init(
                    format: "PNG_GRAYSCALE_16LE",
                    centimetersPerCount: 1,
                    detail: ""
                ),
                albedoEncoding: .init(format: "PNG_RGB_8", detail: ""),
                detail: nil
            )
        }
        func heightMap(
            tile: LMTerrainManifest.Tile,
            northSlope: Double,
            eastSlope: Double
        ) -> LMTerrainHeightMap {
            let posts = tile.postsPerSide
            let spacing = tile.postSpacingMeters
            let halfExtent = tile.extentMeters / 2
            var counts = [UInt16](repeating: 0, count: posts * posts)
            for row in 0..<posts {
                let north = halfExtent - Double(row) * spacing
                for column in 0..<posts {
                    let east = Double(column) * spacing - halfExtent
                    let height = 50 + northSlope * north + eastSlope * east
                    counts[row * posts + column] = UInt16((height * 100).rounded())
                }
            }
            return LMTerrainHeightMap(width: posts, height: posts, counts: counts)
        }

        let parentTile = tile(id: "parent", posts: 5, spacing: 2)
        let childTile = tile(id: "child", posts: 5, spacing: 1)
        let parent = try LMTerrainMeshBuilder.grid(
            tile: parentTile,
            heightMap: heightMap(tile: parentTile, northSlope: 0.2, eastSlope: 0.1)
        )
        let child = try LMTerrainMeshBuilder.grid(
            tile: childTile,
            heightMap: heightMap(tile: childTile, northSlope: 0.8, eastSlope: -0.3)
        )
        let morphed = try LMTerrainMeshBuilder.morphToParent(
            child: child,
            parent: parent,
            parentTile: parentTile,
            childHalfExtentMeters: childTile.extentMeters / 2
        )

        #expect(morphed.triangles == child.triangles)
        let parentNormal = simd_normalize(SIMD3<Float>(-0.2, 1, 0.1))
        let childNormal = simd_normalize(SIMD3<Float>(-0.8, 1, -0.3))
        let northEdge = 2
        let halfRadius = 1 * childTile.postsPerSide + 2
        let center = 2 * childTile.postsPerSide + 2
        #expect(abs(morphed.positions[northEdge].y - 50.4) < 1e-5)
        #expect(morphed.positions[center] == child.positions[center])
        #expect(abs(morphed.positions[halfRadius].y - 50.5) < 1e-5)
        #expect(simd_distance(morphed.normals[northEdge], parentNormal) < 1e-5)
        #expect(simd_distance(morphed.normals[center], childNormal) < 1e-5)
        let halfwayNormal = simd_normalize(parentNormal + (childNormal - parentNormal) * 0.5)
        #expect(simd_distance(morphed.normals[halfRadius], halfwayNormal) < 1e-5)
    }
    private func heightMap(for tile: LMTerrainManifest.Tile) throws -> LMTerrainHeightMap {
        let name = (tile.heightFile as NSString).deletingPathExtension
        let ext = (tile.heightFile as NSString).pathExtension
        let url = try #require(
            LunarMap.resources.url(forResource: name, withExtension: ext, subdirectory: "Terrain")
                ?? LunarMap.resources.url(forResource: name, withExtension: ext)
        )
        return try LMTerrainHeightMap.load(contentsOf: url)
    }

    private struct AlbedoImage {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        subscript(row: Int, column: Int) -> UInt8 {
            pixels[row * width + column]
        }
    }

    private func albedoImage(for tile: LMTerrainManifest.Tile) throws -> AlbedoImage {
        let name = (tile.albedoFile as NSString).deletingPathExtension
        let ext = (tile.albedoFile as NSString).pathExtension
        let url = try #require(
            LunarMap.resources.url(forResource: name, withExtension: ext, subdirectory: "Terrain")
                ?? LunarMap.resources.url(forResource: name, withExtension: ext)
        )
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height)
        let context = try #require(CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return AlbedoImage(width: image.width, height: image.height, pixels: pixels)
    }

    private func expectSameAlbedo(
        _ first: AlbedoImage,
        _ firstRow: Int,
        _ firstColumn: Int,
        _ second: AlbedoImage,
        _ secondRow: Int,
        _ secondColumn: Int
    ) {
        #expect(abs(Int(first[firstRow, firstColumn]) - Int(second[secondRow, secondColumn])) <= 1)
    }

    private func expectSameHeight(
        _ firstMap: LMTerrainHeightMap,
        _ firstTile: LMTerrainManifest.Tile,
        _ firstRow: Int,
        _ firstColumn: Int,
        _ secondMap: LMTerrainHeightMap,
        _ secondTile: LMTerrainManifest.Tile,
        _ secondRow: Int,
        _ secondColumn: Int,
        _ tolerance: Double
    ) throws {
        let first = firstMap.heightMeters(
            atPost: firstRow,
            column: firstColumn,
            zeroPointMeters: firstTile.zeroPointMeters,
            centimetersPerCount: firstTile.heightEncoding.centimetersPerCount
        )
        let second = secondMap.heightMeters(
            atPost: secondRow,
            column: secondColumn,
            zeroPointMeters: secondTile.zeroPointMeters,
            centimetersPerCount: secondTile.heightEncoding.centimetersPerCount
        )
        #expect(abs(first - second) <= tolerance)
    }


}
