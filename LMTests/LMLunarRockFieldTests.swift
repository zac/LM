import Foundation
import LMCore
import RealityKit
import Testing
import simd
@testable import LM

@Suite("Apollo 11 source-constrained rock field")
struct LMLunarRockFieldTests {
    private let eagle = LMVector3D(x: 19.619, y: -4.336, z: 0)

    @Test func distributionIsDeterministicAndVersioned() {
        let model = LMLunarRockFieldModel()
        let first = model.fragments(relativeTo: eagle)
        let second = model.fragments(relativeTo: eagle)

        #expect(first == second)
        #expect(first.count == LMLunarRockFieldModel.sparseFragmentCount
            + LMLunarRockFieldModel.northernBoulderCount)
        #expect(LMLunarRockFieldModel.modelID.contains("apollo11"))
        #expect(LMLunarRockFieldModel.apollo11SourceURL.contains("19700000726"))
    }

    @Test func immediateTouchdownZoneRemainsFreeOfInventedRocks() {
        let fragments = LMLunarRockFieldModel().fragments(relativeTo: eagle)
        let sparse = fragments.filter { $0.region == .sparseLandingVicinity }

        #expect(sparse.count == LMLunarRockFieldModel.sparseFragmentCount)
        for fragment in sparse {
            let distance = hypot(
                fragment.eastMeters - eagle.y,
                fragment.northMeters - eagle.x
            )
            #expect(distance >= LMLunarRockFieldModel.immediateRockFreeRadiusMeters)
            #expect(distance <= LMLunarRockFieldModel.sparseFieldOuterRadiusMeters)
            #expect(fragment.maximumDimensionMeters < 1)
        }
    }

    @Test func northernFieldContainsOnlyMeterClassBouldersInTheSourceConstrainedBand() {
        let fragments = LMLunarRockFieldModel().fragments(relativeTo: eagle)
        let boulders = fragments.filter { $0.region == .northernBoulderField }

        #expect(boulders.count == LMLunarRockFieldModel.northernBoulderCount)
        for boulder in boulders {
            let northOffset = boulder.northMeters - eagle.x
            #expect(northOffset >= LMLunarRockFieldModel.northernFieldMinimumOffsetMeters)
            #expect(northOffset <= LMLunarRockFieldModel.northernFieldMaximumOffsetMeters)
            #expect(boulder.maximumDimensionMeters >= 1)
            #expect(boulder.maximumDimensionMeters <= 3.1)
            #expect(abs(boulder.eastMeters - eagle.y) <= 68)
        }
    }

    @Test func everyFragmentHasBoundedPoseBurialAndSharedArchetypeIndices() {
        let fragments = LMLunarRockFieldModel().fragments(relativeTo: eagle)

        for fragment in fragments {
            #expect((0..<LMLunarRockFieldModel.archetypeCount).contains(fragment.archetype))
            #expect(
                (0..<LMLunarRockFieldModel.reflectanceBucketCount)
                    .contains(fragment.reflectanceBucket)
            )
            #expect((0.10...0.35).contains(fragment.burialFraction))
            #expect(abs(fragment.tiltRadians) <= 0.1)
            #expect(fragment.dimensionsMeters.y > 0)
        }
    }

    @Test func facetedArchetypesHaveOutwardWindingAndUnitNormals() {
        for archetype in 0..<LMLunarRockFieldModel.archetypeCount {
            let mesh = LMLunarRockMeshBuilder.makeArchetype(archetype)
            #expect(!mesh.positions.isEmpty)
            #expect(mesh.positions.count == mesh.normals.count)
            #expect(mesh.indices.count.isMultiple(of: 3))
            #expect(mesh.positions.map(\.y).min() == 0)
            #expect(mesh.positions.map(\.y).max() == 1)

            for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = mesh.positions[Int(mesh.indices[triangle])]
                let b = mesh.positions[Int(mesh.indices[triangle + 1])]
                let c = mesh.positions[Int(mesh.indices[triangle + 2])]
                let geometric = simd_normalize(simd_cross(b - a, c - a))
                let stored = mesh.normals[Int(mesh.indices[triangle])]
                #expect(simd_dot(geometric, stored) > 0.9999)
                #expect(abs(simd_length(stored) - 1) < 0.0001)
            }
        }
    }

    @Test func subMeterFragmentsArriveProgressivelyWhileBouldersRemainVisible() {
        #expect(LMLunarRockDetailPolicy.minimumVisibleDiameterMeters(
            altitudeMeters: 500
        ) == 1)
        #expect(abs(LMLunarRockDetailPolicy.minimumVisibleDiameterMeters(
            altitudeMeters: 100
        ) - 0.25) < 0.0001)
        #expect(LMLunarRockDetailPolicy.minimumVisibleDiameterMeters(
            altitudeMeters: 0
        ) == 0.16)
        #expect(!LMLunarRockDetailPolicy.isVisible(
            maximumDimensionMeters: 0.4,
            altitudeMeters: 500
        ))
        #expect(LMLunarRockDetailPolicy.isVisible(
            maximumDimensionMeters: 1,
            altitudeMeters: 500
        ))
        #expect(LMLunarRockDetailPolicy.isVisible(
            maximumDimensionMeters: 0.4,
            altitudeMeters: 100
        ))
    }

    @Test @MainActor func renderedRocksUseMeasuredElevationButNeverCollisionPhysics() throws {
        let manifest = try LMTerrainManifest.load()
        let alignment = try LMTerrainFrameAlignment(manifest: manifest)
        let heightField = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let model = LMLunarRockFieldModel()
        let fragments = model.fragments(relativeTo: alignment.terrainReferenceTouchdown)
        let entity = try LMLunarRockFieldResource.makeEntity(
            heightField: heightField,
            eagleTerrainPosition: alignment.terrainReferenceTouchdown,
            model: model
        )

        #expect(entity.children.count == LMLunarRockFieldModel.sparseFragmentCount
            + LMLunarRockFieldModel.northernBoulderCount)
        for (child, fragment) in zip(entity.children, fragments) {
            let elevation = try #require(heightField.relativeElevation(
                eastMeters: fragment.eastMeters,
                northMeters: fragment.northMeters
            ))
            #expect(abs(child.position.x - Float(fragment.northMeters)) < 0.0001)
            #expect(abs(child.position.z + Float(fragment.eastMeters)) < 0.0001)
            #expect(abs(
                child.position.y
                    - (elevation - fragment.dimensionsMeters.y * fragment.burialFraction)
            ) < 0.0001)
            #expect(child.components[CollisionComponent.self] == nil)
            #expect(child.components[DynamicLightShadowComponent.self]?.castsShadow == true)
        }
    }
}
