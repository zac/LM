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

@Suite("Progressive lunar terrain")
struct ProgressiveLunarTerrainTests {
    @Test func measuredPostsRemainExactAndProceduralDetailIsBounded() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sampler = LMProgressiveTerrainSampler(heightField: field)

        let measuredPost = try #require(sampler.sample(
            eastMeters: 0,
            northMeters: 0,
            requestedSpacingMeters: 0.5
        ))
        #expect(abs(measuredPost.proceduralResidualMeters) < 1e-7)
        #expect(measuredPost.elevationMeters == measuredPost.measuredElevationMeters)
        #expect(measuredPost.provenance == .measuredWithProceduralSubresolution)

        let subPost = try #require(stride(from: -7.75, through: 7.75, by: 0.25)
            .lazy
            .flatMap { north in
                stride(from: -7.75, through: 7.75, by: 0.25).lazy.map { east in
                    sampler.sample(
                        eastMeters: east,
                        northMeters: north,
                        requestedSpacingMeters: 0.125
                    )
                }
            }
            .compactMap { $0 }
            .first { abs($0.proceduralResidualMeters) > 1e-5 })
        #expect(abs(subPost.proceduralResidualMeters) <= sampler.maximumResidualMeters)
        #expect(abs(subPost.proceduralResidualMeters) > 1e-5)
        #expect(abs(
            subPost.elevationMeters
                - subPost.measuredElevationMeters
                - subPost.proceduralResidualMeters
        ) < 1e-6)
    }

    @Test func geologyModelPinsSurveyorDistributionAndProducesCraterMorphology() throws {
        #expect(LMLunarGeologyModel.modelID == "surveyor-degraded-microrelief-v3")
        #expect(LMLunarGeologyModel.cumulativeCraterDiameterExponent == -2)
        #expect(LMLunarGeologyModel.minimumCraterDiameterMeters >= 0.13)
        #expect(LMLunarGeologyModel.maximumCraterDiameterMeters <= 3)
        #expect(LMLunarGeologyModel.surveyorSourceURL.contains("usgs.gov"))
        #expect(LMLunarGeologyModel.apollo11SourceURL.contains("nasa.gov"))
        #expect(LMLunarGeologyModel(seed: 0).candidateAcceptance < 0.25)

        let crater = LMLunarGeologyModel.Crater(
            eastMeters: 0,
            northMeters: 0,
            diameterMeters: 1,
            aspectRatio: 1,
            rotationRadians: 0,
            sharpness: 0.8,
            rimPhase: 0,
            rimLobes: 5,
            ejectaPhase: 0
        )
        let center = LMLunarGeologyModel.craterReliefMeters(
            eastMeters: 0,
            northMeters: 0,
            crater: crater
        )
        let rim = LMLunarGeologyModel.craterReliefMeters(
            eastMeters: 0.5,
            northMeters: 0,
            crater: crater
        )
        let outside = LMLunarGeologyModel.craterReliefMeters(
            eastMeters: 1,
            northMeters: 0,
            crater: crater
        )
        #expect(center < -0.06)
        #expect(rim > 0.008)
        #expect(outside == 0)
    }

    @Test func postAnchoringIsContinuousAcrossMeasuredCellBoundaries() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sampler = LMProgressiveTerrainSampler(heightField: field)
        let epsilon = 1e-6
        let west = try #require(sampler.sample(
            eastMeters: -epsilon,
            northMeters: 1.13,
            requestedSpacingMeters: 0.125
        ))
        let east = try #require(sampler.sample(
            eastMeters: epsilon,
            northMeters: 1.13,
            requestedSpacingMeters: 0.125
        ))
        #expect(abs(west.proceduralResidualMeters - east.proceduralResidualMeters) < 1e-4)
    }

    /// Procedural relief now reaches the landing-gear contact surface, but it
    /// still has to stay separable: the measured LROC value must remain
    /// readable on its own so a regenerated DTM can replace it.
    @Test func synthesizedReliefStaysSeparableFromTheMeasuredElevation() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sampler = LMProgressiveTerrainSampler(heightField: field)
        let measured = try #require(field.relativeElevation(
            eastMeters: 0.75,
            northMeters: -0.75
        ))
        let visual = try #require(sampler.sample(
            eastMeters: 0.75,
            northMeters: -0.75,
            requestedSpacingMeters: 0.125
        ))
        #expect(visual.measuredElevationMeters == measured)
        #expect(visual.proceduralResidualMeters != 0)
        #expect(
            visual.elevationMeters
                == visual.measuredElevationMeters + visual.proceduralResidualMeters
        )
        #expect(abs(visual.elevationMeters - measured) <= sampler.maximumResidualMeters)
    }

    @Test func proceduralResidualIsDeterministicAndNeverFillsUnknownCoverage() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let first = LMProgressiveTerrainSampler(heightField: field)
        let second = LMProgressiveTerrainSampler(heightField: field)

        #expect(first.sample(
            eastMeters: 103.5,
            northMeters: -47.25,
            requestedSpacingMeters: 1
        ) == second.sample(
            eastMeters: 103.5,
            northMeters: -47.25,
            requestedSpacingMeters: 1
        ))
        #expect(first.sample(
            eastMeters: 50_000,
            northMeters: 50_000,
            requestedSpacingMeters: 0.5
        ) == nil)
    }

    @Test func coarseRequestsReturnOnlyMeasuredInterpolation() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sample = try #require(LMProgressiveTerrainSampler(heightField: field).sample(
            eastMeters: 11,
            northMeters: 17,
            requestedSpacingMeters: field.spacingMeters
        ))

        #expect(sample.provenance == .measuredInterpolated)
        #expect(sample.proceduralResidualMeters == 0)
    }

    @Test func tileIDsStayStableUntilTheFocusCrossesATileBoundary() throws {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)
        let first = planner.plan(focusEastMeters: -547, focusNorthMeters: 732)
        let sameTile = planner.plan(focusEastMeters: -546.5, focusNorthMeters: 732.5)
        let crossed = planner.plan(focusEastMeters: -511.5, focusNorthMeters: 732.5)

        #expect(first.map(\.id) == sameTile.map(\.id))
        #expect(first.map(\.id) != crossed.map(\.id))
        #expect(first.contains { $0.containsProceduralSubresolution })
        #expect(first.contains { !$0.containsProceduralSubresolution })
        #expect(Set(first.map(\.id)).count == first.count)
    }

    @Test func altitudePolicyStreamsOnlyUsefulNestedDetail() throws {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)

        #expect(planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 15_000
        ).isEmpty)

        let approach = planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 2_000
        )
        #expect(approach.isEmpty)

        let terminal = planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 100
        )
        #expect(terminal.map(\.sampleSpacingMeters) == [0.5])
        #expect(terminal.allSatisfy { $0.containsProceduralSubresolution })

        let landingPreload = planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 50
        )
        #expect(landingPreload.contains { $0.sampleSpacingMeters == 0.5 })
        // The 16 m landing safety radius intentionally covers a bounded 3x3
        // working set around this off-center focus.
        #expect(landingPreload.filter { $0.sampleSpacingMeters == 0.125 }.count == 9)

        let aboveLandingPreload = planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 61
        )
        #expect(aboveLandingPreload.map(\.sampleSpacingMeters) == [0.5])

        let landing = planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 20
        )
        #expect(Set(landing.map(\.sampleSpacingMeters)) == Set([0.5, 0.125]))
        #expect(Set(landing.map(\.sizeMeters)) == Set([64, 16]))

        let manifestSpacing = 2.000_000_000_000_6
        let manifestPlanner = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: manifestSpacing
        )
        #expect(manifestPlanner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 100
        ).map(\.sampleSpacingMeters) == [0.5])
        let measuredScalePlan = try #require(manifestPlanner.plan(
            focusEastMeters: -547,
            focusNorthMeters: 732
        ).first { $0.sampleSpacingMeters == 2 })
        #expect(!measuredScalePlan.containsProceduralSubresolution)
    }

    @Test func finerLandingTileMorphsExactlyToTheRenderedParentAtEveryBoundary() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: field.spacingMeters
        ).focusedPlans(
            focusEastMeters: 2,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let parentPlan = try #require(plans.first { $0.sampleSpacingMeters == 0.5 })
        let finePlan = try #require(plans.first { $0.sampleSpacingMeters == 0.125 })
        let generatedParentMesh = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: parentPlan
        )
        let generatedFineMesh = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: finePlan
        )
        let parentMesh = try #require(generatedParentMesh)
        let fineMesh = try #require(generatedFineMesh)
        let samples = 129
        #expect(parentMesh.positions.count == samples * samples)
        #expect(fineMesh.positions.count == samples * samples)
        #expect(fineMesh.indices.count == (samples - 1) * (samples - 1) * 6)
        let i0 = Int(fineMesh.indices[0])
        let i1 = Int(fineMesh.indices[1])
        let i2 = Int(fineMesh.indices[2])
        let geometricNormal = simd_normalize(simd_cross(
            fineMesh.positions[i1] - fineMesh.positions[i0],
            fineMesh.positions[i2] - fineMesh.positions[i0]
        ))
        #expect(geometricNormal.y > 0.9)
        #expect(simd_dot(geometricNormal, fineMesh.normals[i0]) > 0.9)

        func parentHeight(eastMeters: Double, northMeters: Double) -> Float {
            let halfSize = parentPlan.sizeMeters / 2
            let column = Int((
                (eastMeters - (parentPlan.centerEastMeters - halfSize))
                    / parentPlan.sampleSpacingMeters
            ).rounded())
            let row = Int((
                (parentPlan.centerNorthMeters + halfSize - northMeters)
                    / parentPlan.sampleSpacingMeters
            ).rounded())
            return parentMesh.positions[row * samples + column].y
        }

        let fineHalfSize = finePlan.sizeMeters / 2
        for index in stride(from: 0, through: samples - 1, by: 4) {
            let east = finePlan.centerEastMeters - fineHalfSize
                + Double(index) * finePlan.sampleSpacingMeters
            let north = finePlan.centerNorthMeters + fineHalfSize
                - Double(index) * finePlan.sampleSpacingMeters
            let northEdge = fineMesh.positions[index].y
            let southEdge = fineMesh.positions[(samples - 1) * samples + index].y
            let westEdge = fineMesh.positions[index * samples].y
            let eastEdge = fineMesh.positions[index * samples + samples - 1].y
            #expect(abs(northEdge - parentHeight(
                eastMeters: east,
                northMeters: finePlan.centerNorthMeters + fineHalfSize
            )) < 1e-6)
            #expect(abs(southEdge - parentHeight(
                eastMeters: east,
                northMeters: finePlan.centerNorthMeters - fineHalfSize
            )) < 1e-6)
            #expect(abs(westEdge - parentHeight(
                eastMeters: finePlan.centerEastMeters - fineHalfSize,
                northMeters: north
            )) < 1e-6)
            #expect(abs(eastEdge - parentHeight(
                eastMeters: finePlan.centerEastMeters + fineHalfSize,
                northMeters: north
            )) < 1e-6)
        }
    }

    @Test func landingPerimeterNormalsMatchRenderedParent() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: field.spacingMeters)
        let plans = planner.focusedPlans(
            focusEastMeters: 2,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let sampler = LMProgressiveTerrainSurfaceSampler(
            heightField: field,
            planner: planner
        )
        let finePlan = try #require(plans.first {
            $0.sampleSpacingMeters == 0.125 && !$0.transitionEdges.isEmpty
        })
        let parentPlan = try #require(sampler.parentPlan(
            for: finePlan,
            eastMeters: finePlan.centerEastMeters,
            northMeters: finePlan.centerNorthMeters,
            activePlans: plans
        ))
        let generatedFine = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: finePlan,
            activePlans: plans
        )
        let generatedParent = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: parentPlan,
            activePlans: plans
        )
        let fine = try #require(generatedFine)
        let parent = try #require(generatedParent)

        func normal(
            plan: LMTerrainTilePlan,
            mesh: LMProgressiveTerrainMeshData,
            east: Double,
            north: Double
        ) -> SIMD3<Float> {
            let samples = Int(plan.sizeMeters / plan.sampleSpacingMeters) + 1
            let halfSize = plan.sizeMeters / 2
            let column = Int(((east - (plan.centerEastMeters - halfSize))
                / plan.sampleSpacingMeters).rounded())
            let row = Int(((plan.centerNorthMeters + halfSize - north)
                / plan.sampleSpacingMeters).rounded())
            return mesh.normals[row * samples + column]
        }

        let halfSize = finePlan.sizeMeters / 2
        let samples = Int(finePlan.sizeMeters / finePlan.sampleSpacingMeters) + 1
        var dots = [Float]()
        for index in stride(from: 0, through: samples - 1, by: 4) {
            let east = finePlan.centerEastMeters - halfSize
                + Double(index) * finePlan.sampleSpacingMeters
            let north = finePlan.centerNorthMeters + halfSize
                - Double(index) * finePlan.sampleSpacingMeters
            if finePlan.transitionEdges.contains(.north) {
                dots.append(simd_dot(
                    normal(plan: finePlan, mesh: fine, east: east,
                           north: finePlan.centerNorthMeters + halfSize),
                    normal(plan: parentPlan, mesh: parent, east: east,
                           north: finePlan.centerNorthMeters + halfSize)
                ))
            }
            if finePlan.transitionEdges.contains(.south) {
                dots.append(simd_dot(
                    normal(plan: finePlan, mesh: fine, east: east,
                           north: finePlan.centerNorthMeters - halfSize),
                    normal(plan: parentPlan, mesh: parent, east: east,
                           north: finePlan.centerNorthMeters - halfSize)
                ))
            }
            if finePlan.transitionEdges.contains(.west) {
                dots.append(simd_dot(
                    normal(plan: finePlan, mesh: fine,
                           east: finePlan.centerEastMeters - halfSize, north: north),
                    normal(plan: parentPlan, mesh: parent,
                           east: finePlan.centerEastMeters - halfSize, north: north)
                ))
            }
            if finePlan.transitionEdges.contains(.east) {
                dots.append(simd_dot(
                    normal(plan: finePlan, mesh: fine,
                           east: finePlan.centerEastMeters + halfSize, north: north),
                    normal(plan: parentPlan, mesh: parent,
                           east: finePlan.centerEastMeters + halfSize, north: north)
                ))
            }
        }

        #expect(!dots.isEmpty)
        #expect(dots.allSatisfy { $0 > 0.999_9 })
    }

    @Test func adjacentFineTilesKeepFullDetailAcrossTheirSharedEdge() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: field.spacingMeters)
        let plans = planner.focusedPlans(
            focusEastMeters: 12,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let fine = plans.filter { $0.sampleSpacingMeters == 0.125 }
        let west = try #require(fine.first { candidate in
            fine.contains {
                $0.id.level == candidate.id.level
                    && $0.id.eastIndex == candidate.id.eastIndex + 1
                    && $0.id.northIndex == candidate.id.northIndex
            }
        })
        let east = try #require(fine.first {
            $0.id.level == west.id.level
                && $0.id.eastIndex == west.id.eastIndex + 1
                && $0.id.northIndex == west.id.northIndex
        })
        let sharedEast = west.centerEastMeters + west.sizeMeters / 2
        // Sample the shared edge away from a measured post. Tile boundaries and
        // centers both land on even metres, which are exactly 2 m LROC posts,
        // and the anchoring contract forces the procedural residual to zero
        // there at every level. On a post the fine surface therefore equals its
        // parent by construction, so the detail assertion below would hold no
        // matter how much detail the level actually contributes.
        let sharedNorth = west.centerNorthMeters + 1
        let sampler = LMProgressiveTerrainSurfaceSampler(
            heightField: field,
            planner: planner
        )
        let westHeight = try #require(sampler.renderedElevation(
            eastMeters: sharedEast,
            northMeters: sharedNorth,
            plan: west,
            activePlans: plans
        ))
        let eastHeight = try #require(sampler.renderedElevation(
            eastMeters: sharedEast,
            northMeters: sharedNorth,
            plan: east,
            activePlans: plans
        ))
        let parent = try #require(sampler.parentPlan(
            for: west,
            eastMeters: sharedEast,
            northMeters: sharedNorth,
            activePlans: plans
        ))
        let parentHeight = try #require(sampler.renderedElevation(
            eastMeters: sharedEast,
            northMeters: sharedNorth,
            plan: parent,
            activePlans: plans
        ))

        #expect(!west.transitionEdges.contains(.east))
        #expect(!east.transitionEdges.contains(.west))
        #expect(abs(westHeight - eastHeight) < 1e-6)
        #expect(abs(westHeight - parentHeight) > 1e-5)

        let generatedWestMesh = try Apollo11TerrainResource
            .makeProgressiveTileMeshData(
            heightField: field,
            plan: west,
            activePlans: plans
        )
        let generatedEastMesh = try Apollo11TerrainResource
            .makeProgressiveTileMeshData(
            heightField: field,
            plan: east,
            activePlans: plans
        )
        let westMesh = try #require(generatedWestMesh)
        let eastMesh = try #require(generatedEastMesh)
        let sampleCount = Int(west.sizeMeters / west.sampleSpacingMeters) + 1
        let midpointRow = sampleCount / 2
        let westIndex = midpointRow * sampleCount + sampleCount - 1
        let eastIndex = midpointRow * sampleCount
        #expect(abs(
            westMesh.positions[westIndex].y - eastMesh.positions[eastIndex].y
        ) < 1e-6)
        #expect(simd_dot(
            westMesh.normals[westIndex],
            eastMesh.normals[eastIndex]
        ) > 0.999_99)
    }

    @Test func everyEagleLandingTileEdgeIsGeometricallyContinuous() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: field.spacingMeters)
        let plans = planner.focusedPlans(
            focusEastMeters: -4.335939305713085,
            focusNorthMeters: 19.61920772442715,
            altitudeMeters: 2
        )
        let finePlans = plans.filter { $0.sampleSpacingMeters == 0.125 }
        let meshes = try Dictionary(uniqueKeysWithValues: finePlans.map { plan in
            let generated = try Apollo11TerrainResource.makeProgressiveTileMeshData(
                heightField: field,
                plan: plan,
                activePlans: plans
            )
            return (plan.id, try #require(generated))
        })
        let sampleCount = 129

        for plan in finePlans {
            let mesh = try #require(meshes[plan.id])
            let eastID = LMTerrainTileID(
                level: plan.id.level,
                eastIndex: plan.id.eastIndex + 1,
                northIndex: plan.id.northIndex
            )
            if let east = meshes[eastID] {
                for row in 0..<sampleCount {
                    let westIndex = row * sampleCount + sampleCount - 1
                    let eastIndex = row * sampleCount
                    #expect(abs(mesh.positions[westIndex].y - east.positions[eastIndex].y) < 1e-6)
                    #expect(simd_dot(mesh.normals[westIndex], east.normals[eastIndex]) > 0.999_99)
                }
            }

            let northID = LMTerrainTileID(
                level: plan.id.level,
                eastIndex: plan.id.eastIndex,
                northIndex: plan.id.northIndex + 1
            )
            if let north = meshes[northID] {
                for column in 0..<sampleCount {
                    let southIndex = column
                    let northIndex = (sampleCount - 1) * sampleCount + column
                    #expect(abs(mesh.positions[southIndex].y - north.positions[northIndex].y) < 1e-6)
                    #expect(simd_dot(mesh.normals[southIndex], north.normals[northIndex]) > 0.999_99)
                }
            }
        }
    }

    @Test func progressiveMeasuredNormalsStaySmoothAcrossSourceGridLines() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let north = 19.61920772442715
        let west = try #require(field.interpolatedSurfaceNormal(
            eastMeters: -0.001,
            northMeters: north
        ))
        let east = try #require(field.interpolatedSurfaceNormal(
            eastMeters: 0.001,
            northMeters: north
        ))
        #expect(simd_dot(west, east) > 0.999_99)

        let center = try #require(field.interpolatedSurfaceNormal(
            eastMeters: 0,
            northMeters: 20
        ))
        let spacing = field.spacingMeters
        let expectedNorthSlope = (
            try #require(field.relativeElevation(eastMeters: 0, northMeters: 20 + spacing))
                - (try #require(field.relativeElevation(
                    eastMeters: 0,
                    northMeters: 20 - spacing
                )))
        ) / Float(2 * spacing)
        let expectedEastSlope = (
            try #require(field.relativeElevation(eastMeters: spacing, northMeters: 20))
                - (try #require(field.relativeElevation(
                    eastMeters: -spacing,
                    northMeters: 20
                )))
        ) / Float(2 * spacing)
        let expected = simd_normalize(SIMD3<Float>(
            -expectedNorthSlope,
            1,
            expectedEastSlope
        ))
        #expect(simd_dot(center, expected) > 0.999_99)
    }

    @Test func landingPerimeterNormalsMatchTheTerminalParent() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: field.spacingMeters)
        let plans = planner.focusedPlans(
            focusEastMeters: -4.335939305713085,
            focusNorthMeters: 19.61920772442715,
            altitudeMeters: 2
        )
        let meshes = try Dictionary(uniqueKeysWithValues: plans.map { plan in
            let mesh = try Apollo11TerrainResource.makeProgressiveTileMeshData(
                heightField: field,
                plan: plan,
                activePlans: plans
            )
            return (plan.id, try #require(mesh))
        })
        struct PositionKey: Hashable {
            let northMillimeters: Int
            let eastMillimeters: Int
        }
        let terminalPlans = plans.filter { $0.sampleSpacingMeters == 0.5 }
        var terminalNormals = [PositionKey: SIMD3<Float>]()
        for plan in terminalPlans {
            let mesh = try #require(meshes[plan.id])
            for (position, normal) in zip(mesh.positions, mesh.normals) {
                terminalNormals[PositionKey(
                    northMillimeters: Int((position.x * 1_000).rounded()),
                    eastMillimeters: Int((-position.z * 1_000).rounded())
                )] = normal
            }
        }

        var edgeDots = [Float]()
        for plan in plans where plan.sampleSpacingMeters == 0.125 {
            let mesh = try #require(meshes[plan.id])
            let sampleCount = Int(plan.sizeMeters / plan.sampleSpacingMeters) + 1
            for row in 0..<sampleCount {
                for column in 0..<sampleCount {
                    let isEdge = (column == 0 && plan.transitionEdges.contains(.west))
                        || (column == sampleCount - 1 && plan.transitionEdges.contains(.east))
                        || (row == 0 && plan.transitionEdges.contains(.north))
                        || (row == sampleCount - 1 && plan.transitionEdges.contains(.south))
                    guard isEdge, row.isMultiple(of: 4), column.isMultiple(of: 4) else {
                        continue
                    }
                    let index = row * sampleCount + column
                    let position = mesh.positions[index]
                    let key = PositionKey(
                        northMillimeters: Int((position.x * 1_000).rounded()),
                        eastMillimeters: Int((-position.z * 1_000).rounded())
                    )
                    if let parent = terminalNormals[key] {
                        edgeDots.append(simd_dot(mesh.normals[index], parent))
                    }
                }
            }
        }
        #expect(!edgeDots.isEmpty)
        #expect(edgeDots.min() ?? 0 > 0.999_9)
    }

    @Test func finerResidentTilesReplaceCoveredParentTriangles() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: field.spacingMeters
        ).focusedPlans(
            focusEastMeters: 2,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let finePlans = plans.filter { $0.sampleSpacingMeters == 0.125 }
        let parentPlan = try #require(plans.first { candidate in
            guard candidate.sampleSpacingMeters == 0.5 else { return false }
            let halfSize = candidate.sizeMeters / 2
            return finePlans.contains {
                $0.centerEastMeters > candidate.centerEastMeters - halfSize
                    && $0.centerEastMeters < candidate.centerEastMeters + halfSize
                    && $0.centerNorthMeters > candidate.centerNorthMeters - halfSize
                    && $0.centerNorthMeters < candidate.centerNorthMeters + halfSize
            }
        })
        let generated = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: parentPlan,
            activePlans: plans
        )
        let mesh = try #require(generated)
        let sampleCount = Int(parentPlan.sizeMeters / parentPlan.sampleSpacingMeters) + 1
        let completeIndexCount = (sampleCount - 1) * (sampleCount - 1) * 6

        #expect(mesh.indices.count < completeIndexCount)
        for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
            let first = mesh.positions[Int(mesh.indices[triangle])]
            let second = mesh.positions[Int(mesh.indices[triangle + 1])]
            let third = mesh.positions[Int(mesh.indices[triangle + 2])]
            let center = (first + second + third) / 3
            let east = -Double(center.z)
            let north = Double(center.x)
            #expect(!finePlans.contains { fine in
                let halfSize = fine.sizeMeters / 2
                return east > fine.centerEastMeters - halfSize
                    && east < fine.centerEastMeters + halfSize
                    && north > fine.centerNorthMeters - halfSize
                    && north < fine.centerNorthMeters + halfSize
            })
        }
    }

    @Test func transparentFineTilesDoNotRemoveParentTriangles() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: field.spacingMeters
        ).focusedPlans(
            focusEastMeters: 2,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let parentPlan = try #require(plans.first {
            $0.sampleSpacingMeters == 0.5
        })
        let generated = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: parentPlan,
            activePlans: plans,
            geometryReplacementPlans: plans.filter {
                $0.sampleSpacingMeters >= parentPlan.sampleSpacingMeters
            }
        )
        let mesh = try #require(generated)
        let sampleCount = Int(parentPlan.sizeMeters / parentPlan.sampleSpacingMeters) + 1
        #expect(mesh.indices.count == (sampleCount - 1) * (sampleCount - 1) * 6)
    }

    @Test func presentationPreloadsFineGeometryThenBlendsToExactRenderedTouchdown() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: field.spacingMeters)
        let plans = planner.focusedPlans(
            focusEastMeters: 2,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let parentPlan = try #require(plans.first { $0.sampleSpacingMeters == 0.5 })
        let finePlan = try #require(plans.first { $0.sampleSpacingMeters == 0.125 })
        let sampler = LMProgressiveTerrainSurfaceSampler(
            heightField: field,
            planner: planner
        )
        let east = finePlan.centerEastMeters
        let north = finePlan.centerNorthMeters
        let parent = try #require(sampler.renderedElevation(
            eastMeters: east,
            northMeters: north,
            plan: parentPlan,
            activePlans: plans
        ))
        let fine = try #require(sampler.renderedElevation(
            eastMeters: east,
            northMeters: north,
            plan: finePlan,
            activePlans: plans
        ))
        let preloaded = try #require(sampler.sample(
            eastMeters: east,
            northMeters: north,
            altitudeMeters: 50,
            activePlans: plans
        ))
        let halfway = try #require(sampler.sample(
            eastMeters: east,
            northMeters: north,
            altitudeMeters: 32.5,
            activePlans: plans
        ))
        let touchdown = try #require(sampler.sample(
            eastMeters: east,
            northMeters: north,
            altitudeMeters: 0,
            activePlans: plans
        ))

        #expect(preloaded.sampleSpacingMeters == 0.125)
        #expect(preloaded.presentationBlend == 0)
        #expect(abs(preloaded.presentationElevationMeters - parent) < 1e-6)
        #expect(abs(halfway.presentationBlend - 0.5) < 1e-9)
        #expect(abs(
            halfway.presentationElevationMeters - (parent + (fine - parent) * 0.5)
        ) < 1e-6)
        #expect(touchdown.presentationBlend == 1)
        #expect(abs(touchdown.presentationElevationMeters - fine) < 1e-6)
        #expect(abs(touchdown.renderedElevationMeters - fine) < 1e-6)
    }

    @Test func terminalVelocityPrefetchesBeyondTheCurrentSafetyFootprint() {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)
        let stationary = planner.prefetchedPlans(
            focusEastMeters: 12,
            focusNorthMeters: 2,
            velocityEastMetersPerSecond: 0,
            velocityNorthMetersPerSecond: 0,
            altitudeMeters: 20
        )
        let moving = planner.prefetchedPlans(
            focusEastMeters: 12,
            focusNorthMeters: 2,
            velocityEastMetersPerSecond: 4,
            velocityNorthMetersPerSecond: 0,
            altitudeMeters: 20
        )
        let stationaryFine = stationary.filter { $0.sampleSpacingMeters == 0.125 }
        let movingFine = moving.filter { $0.sampleSpacingMeters == 0.125 }

        #expect(stationaryFine.count == 9)
        #expect(movingFine.count == 15)
        #expect(Set(moving.map(\.id)).count == moving.count)
        #expect(movingFine.first?.id.eastIndex == -1)
        #expect(movingFine.last?.id.eastIndex == 3)

        let movingByID = Dictionary(
            uniqueKeysWithValues: movingFine.map { ($0.id, $0) }
        )
        for plan in movingFine {
            let eastNeighborID = LMTerrainTileID(
                level: plan.id.level,
                eastIndex: plan.id.eastIndex + 1,
                northIndex: plan.id.northIndex
            )
            if let eastNeighbor = movingByID[eastNeighborID] {
                #expect(!plan.transitionEdges.contains(.east))
                #expect(!eastNeighbor.transitionEdges.contains(.west))
            } else {
                #expect(plan.transitionEdges.contains(.east))
            }
        }
    }

    @Test func explorerViewProjectionKeepsAContiguousLandingViewCorridor() {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)
        let plans = planner.viewCorridorPlans(
            focusEastMeters: -4.336,
            focusNorthMeters: 19.619,
            headingDegrees: 0,
            forwardDistanceMeters: 48,
            altitudeMeters: 2
        )
        let rear = planner.viewCorridorPlans(
            focusEastMeters: -4.336,
            focusNorthMeters: 19.619,
            headingDegrees: 180,
            forwardDistanceMeters: 32,
            altitudeMeters: 2
        )
        let complete = planner.mergedPlans(plans + rear).filter {
            $0.sampleSpacingMeters == 0.125
        }
        #expect(complete.count == 24)
        #expect(Set(complete.map(\.id.eastIndex)) == Set(-4...3))
        #expect(Set(complete.map(\.id.northIndex)) == Set(0...2))
        let byID = Dictionary(uniqueKeysWithValues: complete.map { ($0.id, $0) })
        for plan in complete where plan.id.eastIndex < 3 {
            let east = LMTerrainTileID(
                level: plan.id.level,
                eastIndex: plan.id.eastIndex + 1,
                northIndex: plan.id.northIndex
            )
            #expect(!plan.transitionEdges.contains(.east))
            #expect(!byID[east]!.transitionEdges.contains(.west))
        }
    }

    @Test func coarserResidencyEnclosesFinerFootprintByItsOwnMorphCollar() {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)
        // The terminal level's outer morph collar hands off to the measured
        // source over this width; the landing footprint must never reach it.
        let terminalCollarMeters = min(64.0 / 4, 2.0 * 8)
        // Foci deliberately include positions right at and just across 64 m
        // tile boundaries, where equal per-level radii used to leave the two
        // footprints ending on the same line.
        let foci: [(east: Double, north: Double)] = [
            (-4.336, 19.619),
            (0.5, 63.5),
            (-64.0, 128.0),
            (31.9, -0.1),
            (-547, 732),
        ]
        for focus in foci {
            let plans = planner.prefetchedPlans(
                focusEastMeters: focus.east,
                focusNorthMeters: focus.north,
                velocityEastMetersPerSecond: 48.0 / 6.0,
                velocityNorthMetersPerSecond: 0,
                altitudeMeters: 2
            )
            let terminal = plans.filter { $0.sampleSpacingMeters == 0.5 }
            func terminalCovers(east: Double, north: Double) -> Bool {
                terminal.contains { plan in
                    abs(east - plan.centerEastMeters) <= plan.sizeMeters / 2
                        && abs(north - plan.centerNorthMeters) <= plan.sizeMeters / 2
                }
            }
            for plan in plans where plan.sampleSpacingMeters == 0.125 {
                let reach = plan.sizeMeters / 2 + terminalCollarMeters
                for (east, north) in [
                    (plan.centerEastMeters - reach, plan.centerNorthMeters - reach),
                    (plan.centerEastMeters - reach, plan.centerNorthMeters + reach),
                    (plan.centerEastMeters + reach, plan.centerNorthMeters - reach),
                    (plan.centerEastMeters + reach, plan.centerNorthMeters + reach),
                    (plan.centerEastMeters - reach, plan.centerNorthMeters),
                    (plan.centerEastMeters + reach, plan.centerNorthMeters),
                    (plan.centerEastMeters, plan.centerNorthMeters - reach),
                    (plan.centerEastMeters, plan.centerNorthMeters + reach),
                ] {
                    #expect(
                        terminalCovers(east: east, north: north),
                        "landing tile \(plan.id) collar point (\(east), \(north)) has no terminal parent at focus \(focus)"
                    )
                }
            }
        }
    }

    @Test func focusedTilesMorphOnlyAtTheResidencyFootprintPerimeter() {
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: 2
        ).focusedPlans(
            focusEastMeters: 12,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let byID = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })

        for plan in plans {
            let neighbors: [(LMTerrainTileEdges, LMTerrainTileID)] = [
                (.west, .init(
                    level: plan.id.level,
                    eastIndex: plan.id.eastIndex - 1,
                    northIndex: plan.id.northIndex
                )),
                (.east, .init(
                    level: plan.id.level,
                    eastIndex: plan.id.eastIndex + 1,
                    northIndex: plan.id.northIndex
                )),
                (.south, .init(
                    level: plan.id.level,
                    eastIndex: plan.id.eastIndex,
                    northIndex: plan.id.northIndex - 1
                )),
                (.north, .init(
                    level: plan.id.level,
                    eastIndex: plan.id.eastIndex,
                    northIndex: plan.id.northIndex + 1
                )),
            ]
            for (edge, neighborID) in neighbors {
                #expect(plan.transitionEdges.contains(edge) == (byID[neighborID] == nil))
            }
        }
    }

    @Test func focusedFootprintChangesOnlyWhenItsSafetyBoundaryIsCrossed() {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)
        let first = planner.focusedPlans(
            focusEastMeters: 31,
            focusNorthMeters: 31,
            altitudeMeters: 100
        )
        let same = planner.focusedPlans(
            focusEastMeters: 40,
            focusNorthMeters: 40,
            altitudeMeters: 100
        )
        let crossed = planner.focusedPlans(
            focusEastMeters: 49,
            focusNorthMeters: 49,
            altitudeMeters: 100
        )

        #expect(first.count == 1)
        #expect(first.map(\.id) == same.map(\.id))
        #expect(crossed.count == 4)
        #expect(Set(first.map(\.id)) != Set(crossed.map(\.id)))
    }

    @Test func eagleLandingFootprintStaysInsideResidentFineTiles() throws {
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
        let terminal = plans.filter { $0.sampleSpacingMeters == 0.5 }
        let landing = plans.filter { $0.sampleSpacingMeters == 0.125 }

        // Four terminal tiles: the parent level now encloses the landing
        // footprint by its own 16 m morph collar instead of ending on
        // whatever 64 m line quantization happened to pick. The landing
        // level keeps the same bounded 3x3 safety set as every other
        // off-center 16 m focus.
        #expect(terminal.count == 4)
        #expect(landing.count == 9)
        for northOffset in [-7.0, 0, 7.0] {
            for eastOffset in [-7.0, 0, 7.0] {
                #expect(landing.contains {
                    let half = $0.sizeMeters / 2
                    return eagle.y + eastOffset >= $0.centerEastMeters - half
                        && eagle.y + eastOffset <= $0.centerEastMeters + half
                        && eagle.x + northOffset >= $0.centerNorthMeters - half
                        && eagle.x + northOffset <= $0.centerNorthMeters + half
                })
            }
        }
    }
}
