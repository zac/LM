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

@Suite("Terrain-relative landing")
struct TerrainRelativeLandingTests {
    private func heightField() throws -> Apollo11TerrainHeightField {
        try Apollo11TerrainResource.loadSourceBackedHeightField()
    }

    private func alignment() throws -> LMTerrainFrameAlignment {
        try LMTerrainFrameAlignment(manifest: LMTerrainManifest.load())
    }

    private func contactSurface(
        activePlans: [LMTerrainTilePlan] = [],
        altitudeMeters: Double = 20
    ) throws -> LMTerrainContactSurface {
        let field = try heightField()
        let frame = try alignment()
        return try LMTerrainContactSurfaceBuilder.build(
            heightField: field,
            alignment: frame,
            activePlans: activePlans,
            altitudeMeters: altitudeMeters,
            centerTerrainEastMeters: frame.terrainReferenceTouchdown.y,
            centerTerrainNorthMeters: frame.terrainReferenceTouchdown.x
        )
    }

    @Test func contactSurfaceIsZeroAtTheNominalTouchdownPoint() throws {
        let frame = try alignment()
        let surface = try contactSurface()
        let nominal = LMTerrainFrameAlignment.nominalP66GuidanceTouchdown
        let height = surface.surfaceHeightMeters(
            northMeters: nominal.x,
            eastMeters: nominal.y
        )
        // Referencing heights to the terrain under Eagle is what keeps the
        // bundled trajectories landing at guidance altitude zero.
        #expect(abs(height) < 0.02)
        #expect(surface.referenceElevationMeters != 0)
        _ = frame
    }

    @Test func contactSurfaceReproducesMeasuredReliefAwayFromTheDatum() throws {
        let field = try heightField()
        let frame = try alignment()
        let surface = try contactSurface()
        let nominal = LMTerrainFrameAlignment.nominalP66GuidanceTouchdown

        // Sample a few meters away and compare against the measured height
        // field read directly, in terrain coordinates.
        for offset in [-12.0, -5.0, 5.0, 12.0] {
            let north = nominal.x + offset
            let terrain = frame.terrainPosition(
                from: LMVector3D(x: north, y: nominal.y, z: 0)
            )
            let measured = try #require(field.relativeElevation(
                eastMeters: terrain.y,
                northMeters: terrain.x
            ))
            let expected = Double(measured - surface.referenceElevationMeters)
            let actual = surface.surfaceHeightMeters(
                northMeters: north,
                eastMeters: nominal.y
            )
            // With no procedural plans active the patch is pure measured relief.
            #expect(abs(actual - expected) < 0.02)
        }
    }

    @Test func proceduralCraterReliefReachesTheContactSurface() throws {
        let field = try heightField()
        let frame = try alignment()
        let eagle = frame.terrainReferenceTouchdown
        let landingPlan = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: field.spacingMeters
        ).focusedPlans(
            focusEastMeters: eagle.y,
            focusNorthMeters: eagle.x,
            altitudeMeters: 20
        )
        #expect(!landingPlan.isEmpty)

        let measuredOnly = try contactSurface()
        let withProcedural = try contactSurface(activePlans: landingPlan)
        let nominal = LMTerrainFrameAlignment.nominalP66GuidanceTouchdown

        var maximumDifference = 0.0
        for northOffset in stride(from: -6.0, through: 6.0, by: 0.25) {
            for eastOffset in stride(from: -6.0, through: 6.0, by: 0.25) {
                let north = nominal.x + northOffset
                let east = nominal.y + eastOffset
                let difference = abs(
                    withProcedural.surfaceHeightMeters(northMeters: north, eastMeters: east)
                        - measuredOnly.surfaceHeightMeters(northMeters: north, eastMeters: east)
                )
                maximumDifference = max(maximumDifference, difference)
            }
        }
        // Sub-resolution morphology is visible to the gear but stays inside the
        // bounded residual the geology model is allowed to add.
        #expect(maximumDifference > 0.01)
        #expect(maximumDifference < 0.30)
    }

    @Test func contactSurfaceSlopeIsRealisticForTheMareSite() throws {
        let surface = try contactSurface()
        let nominal = LMTerrainFrameAlignment.nominalP66GuidanceTouchdown
        let normal = surface.surfaceNormal(
            northMeters: nominal.x,
            eastMeters: nominal.y
        )
        let slopeDegrees = acos(min(max(normal.z, -1), 1)) * 180 / .pi
        #expect(slopeDegrees >= 0)
        #expect(slopeDegrees < LMLandingGearGeometry.criticalTiltRadians * 180 / .pi)
    }

    @Test func gearSettlesOnRealTerrainWithoutFloatingOrSinking() throws {
        let surface = try contactSurface()
        let nominal = LMTerrainFrameAlignment.nominalP66GuidanceTouchdown
        let mass = LMLandingGearGeometry.designTouchdownMassKilograms
        let gravity = LMVehicleConfiguration.sourceBackedDefault
            .lunarGravityMetersPerSecondSquared.value
        let inertia = LMInertiaMap.diagonalInertiaKilogramMetersSquared(massKilograms: mass)

        // The reference point is the uncompressed footpad plane, so this is a
        // vehicle a few centimeters above the ground at a nominal descent rate.
        var position = LMVector3D(x: nominal.x, y: nominal.y, z: 0.05)
        var velocity = LMVector3D(z: -0.5)
        var attitude = LMQuaternion.identity
        var angularVelocity = LMVector3D.zero
        var gear = LMLandingGearState()
        var settled = false

        for _ in 0..<1_800 {
            let result = LMLandingGearDynamics.integrate(
                positionMeters: position,
                velocityMetersPerSecond: velocity,
                attitude: attitude,
                angularVelocityRadiansPerSecond: angularVelocity,
                massKilograms: mass,
                inertiaKilogramMetersSquared: inertia,
                accelerationMetersPerSecondSquared: LMVector3D(z: -gravity),
                angularAccelerationRadiansPerSecondSquared: .zero,
                gear: gear,
                surface: surface,
                deltaTime: 1.0 / 60.0
            )
            position = result.positionMeters
            velocity = result.velocityMetersPerSecond
            attitude = result.attitude
            angularVelocity = result.angularVelocityRadiansPerSecond
            gear = result.gear
            if result.isSettled { settled = true; break }
        }

        #expect(settled)
        #expect(gear.failure == nil)

        // Real LROC relief across the 9.4 m gear span means the vehicle does not
        // arrive on a plane. Some pads carry it, others end up clear of the
        // ground, and none of them passes through the surface.
        var loaded = 0
        var clear = 0
        for leg in LMLandingGearLeg.allCases {
            let snapshot = try #require(gear.snapshot(leg))
            let pad = LMLandingGearGeometry.footpadBody(
                leg,
                strokeMeters: snapshot.strokeMeters
            )
            let world = position + attitude.rotated(pad)
            let ground = surface.surfaceHeightMeters(
                northMeters: world.x,
                eastMeters: world.y
            )
            let clearance = world.z - ground
            if snapshot.isInContact {
                loaded += 1
                // A loaded pad is sitting in the print it pushed into the soil.
                #expect(clearance < 0)
                #expect(
                    clearance
                        >= -(snapshot.regolithPenetrationMeters
                            + LMLandingGearDynamics.regolithBearingLoadNewtons
                            / LMLandingGearDynamics.padStiffnessNewtonsPerMeter
                            + 0.01)
                )
            } else {
                clear += 1
            }
            // Nothing hangs implausibly far off the ground it landed on.
            #expect(clearance < 0.5)
        }
        #expect(loaded >= 2)
        #expect(loaded + clear == LMLandingGearLeg.allCases.count)

        // Resting attitude follows the terrain instead of staying artificially
        // level, but the mare under Eagle is nowhere near the tip-over limit.
        let localUp = surface.surfaceNormal(
            northMeters: position.x,
            eastMeters: position.y
        )
        let tilt = LMLandingGearDynamics.tiltRadians(attitude: attitude, localUp: localUp)
        #expect(tilt < LMLandingGearGeometry.criticalTiltRadians / 2)

        let levelTilt = LMLandingGearDynamics.tiltRadians(
            attitude: .identity,
            localUp: LMVector3D(z: 1)
        )
        let settledTilt = LMLandingGearDynamics.tiltRadians(
            attitude: attitude,
            localUp: LMVector3D(z: 1)
        )
        #expect(settledTilt > levelTilt)
    }
}
