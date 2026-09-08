import Foundation
import LMCore
import RealityKit
import UIKit
import simd

enum LMLunarRockRegion: String, Equatable, Sendable {
    case sparseLandingVicinity
    case northernBoulderField
}

/// One deterministic visual fragment in the Apollo 11 terrain frame.
///
/// These fragments are deliberately separate from the height field and have no
/// collision component. They can provide silhouettes, parallax, and shadows
/// without silently turning synthesized geology into a landing hazard.
struct LMLunarRockFragment: Equatable, Sendable {
    let region: LMLunarRockRegion
    let eastMeters: Double
    let northMeters: Double
    let dimensionsMeters: SIMD3<Float>
    let yawRadians: Float
    let tiltRadians: Float
    let tiltAzimuthRadians: Float
    let burialFraction: Float
    let archetype: Int
    let reflectanceBucket: Int

    var maximumDimensionMeters: Float {
        max(dimensionsMeters.x, dimensionsMeters.z)
    }
}

/// Source-constrained, but not surveyed, fragment distribution around Eagle.
///
/// NASA SP-214 describes the immediate LM region as relatively free of rocks,
/// while a field several hundred feet north contained boulders a meter or more
/// across. Exact fragment coordinates are synthesized and versioned. The 25 m
/// exclusion zone prevents invented rocks from becoming apparent touchdown
/// hazards in the otherwise rock-poor immediate landing area.
public struct LMLunarRockFieldModel: Equatable, Sendable {
    public static let modelID = "apollo11-source-constrained-rock-field-v1"
    static let apollo11SourceURL =
        "https://ntrs.nasa.gov/api/citations/19700000726/downloads/19700000726.pdf"
    static let immediateRockFreeRadiusMeters = 25.0
    static let sparseFieldOuterRadiusMeters = 105.0
    static let northernFieldMinimumOffsetMeters = 90.0
    static let northernFieldMaximumOffsetMeters = 180.0
    static let sparseFragmentCount = 34
    static let northernBoulderCount = 28
    static let archetypeCount = 6
    static let reflectanceBucketCount = 4

    let seed: UInt64

    @usableFromInline init(seed: UInt64 = 0x41_31_31_52_4F_43_4B) {
        self.seed = seed
    }

    func fragments(relativeTo eagle: LMVector3D) -> [LMLunarRockFragment] {
        sparseFragments(relativeTo: eagle) + northernBoulders(relativeTo: eagle)
    }

    private func sparseFragments(relativeTo eagle: LMVector3D) -> [LMLunarRockFragment] {
        (0..<Self.sparseFragmentCount).map { index in
            let radialDraw = unit(index, property: 0)
            let innerSquared = pow(Self.immediateRockFreeRadiusMeters, 2)
            let outerSquared = pow(Self.sparseFieldOuterRadiusMeters, 2)
            let radius = sqrt(innerSquared + radialDraw * (outerSquared - innerSquared))
            let angle = unit(index, property: 1) * 2 * Double.pi
            let diameter = 0.16 + pow(unit(index, property: 2), 2.4) * 0.66
            let depthScale = 0.72 + unit(index, property: 3) * 0.42
            let heightScale = 0.34 + unit(index, property: 4) * 0.38
            return fragment(
                region: .sparseLandingVicinity,
                eastMeters: eagle.y + sin(angle) * radius,
                northMeters: eagle.x + cos(angle) * radius,
                widthMeters: diameter,
                depthMeters: diameter * depthScale,
                heightMeters: diameter * heightScale,
                index: index,
                propertyOffset: 10
            )
        }
    }

    private func northernBoulders(relativeTo eagle: LMVector3D) -> [LMLunarRockFragment] {
        (0..<Self.northernBoulderCount).map { index in
            let northOffset = Self.northernFieldMinimumOffsetMeters
                + unit(index, property: 40)
                * (Self.northernFieldMaximumOffsetMeters - Self.northernFieldMinimumOffsetMeters)
            // The primary report constrains this as a northerly field but does
            // not survey individual coordinates. Keep the synthesized spread
            // broad and centered on Eagle's north line rather than inventing a
            // precise mapped cluster.
            let eastOffset = (unit(index, property: 41) * 2 - 1) * 68
            let diameter = 1.0 + pow(unit(index, property: 42), 1.7) * 2.1
            let depthScale = 0.65 + unit(index, property: 43) * 0.35
            let heightScale = 0.38 + unit(index, property: 44) * 0.46
            return fragment(
                region: .northernBoulderField,
                eastMeters: eagle.y + eastOffset,
                northMeters: eagle.x + northOffset,
                widthMeters: diameter,
                depthMeters: diameter * depthScale,
                heightMeters: diameter * heightScale,
                index: index,
                propertyOffset: 50
            )
        }
    }

    private func fragment(
        region: LMLunarRockRegion,
        eastMeters: Double,
        northMeters: Double,
        widthMeters: Double,
        depthMeters: Double,
        heightMeters: Double,
        index: Int,
        propertyOffset: UInt64
    ) -> LMLunarRockFragment {
        LMLunarRockFragment(
            region: region,
            eastMeters: eastMeters,
            northMeters: northMeters,
            dimensionsMeters: SIMD3(
                Float(widthMeters),
                Float(heightMeters),
                Float(depthMeters)
            ),
            yawRadians: Float(unit(index, property: propertyOffset) * 2 * .pi),
            tiltRadians: Float((unit(index, property: propertyOffset + 1) - 0.5) * 0.20),
            tiltAzimuthRadians: Float(unit(index, property: propertyOffset + 2) * 2 * .pi),
            burialFraction: Float(0.10 + unit(index, property: propertyOffset + 3) * 0.25),
            archetype: Int(unit(index, property: propertyOffset + 4) * Double(Self.archetypeCount)),
            reflectanceBucket: Int(
                unit(index, property: propertyOffset + 5)
                    * Double(Self.reflectanceBucketCount)
            )
        )
    }

    private func unit(_ index: Int, property: UInt64) -> Double {
        var value = seed
            ^ UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15
            ^ property &* 0xBF58_476D_1CE4_E5B9
        value &+= 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }
}

struct LMLunarRockMeshData: Equatable, Sendable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]
}

/// Coarse screen-detail gate for the static fragment field. Large boulders stay
/// visible throughout P64 while sub-meter fragments arrive progressively as
/// the LM descends, avoiding distant sub-pixel shimmer and unnecessary draws.
public enum LMLunarRockDetailPolicy {
    static let minimumFragmentDiameterMeters: Float = 0.16
    static let maximumCullDiameterMeters: Float = 1.0

    nonisolated static func minimumVisibleDiameterMeters(
        altitudeMeters: Double
    ) -> Float {
        min(
            maximumCullDiameterMeters,
            max(minimumFragmentDiameterMeters, Float(max(altitudeMeters, 0) / 400))
        )
    }

    public nonisolated static func isVisible(
        maximumDimensionMeters: Float,
        altitudeMeters: Double
    ) -> Bool {
        maximumDimensionMeters + 0.0001
            >= minimumVisibleDiameterMeters(altitudeMeters: altitudeMeters)
    }
}

/// Small faceted archetypes shared by every fragment. Reusing six meshes keeps
/// the runtime eligible for renderer batching while scale, burial, and pose
/// provide the site-level variation.
enum LMLunarRockMeshBuilder {
    nonisolated static func makeArchetype(_ archetype: Int) -> LMLunarRockMeshData {
        let sideCount = 8
        let phase = Float(archetype % LMLunarRockFieldModel.archetypeCount) * 0.61
        var base = [SIMD3<Float>]()
        var shoulder = [SIMD3<Float>]()
        var crown = [SIMD3<Float>]()
        for side in 0..<sideCount {
            let angle = Float(side) / Float(sideCount) * 2 * .pi
            let irregularity = 1
                + 0.10 * sin(Float(side * 3) + phase)
                + 0.06 * cos(Float(side * 5) - phase * 1.7)
            let cosine = cos(angle)
            let sine = sin(angle)
            base.append(SIMD3(
                cosine * 0.48 * irregularity,
                0,
                sine * 0.48 * irregularity
            ))
            shoulder.append(SIMD3(
                cosine * 0.50 * irregularity,
                0.47 + 0.05 * sin(Float(side * 2) + phase),
                sine * 0.50 * irregularity
            ))
            crown.append(SIMD3(
                cosine * 0.28 * irregularity,
                0.82 + 0.05 * cos(Float(side * 3) - phase),
                sine * 0.28 * irregularity
            ))
        }
        let summit = SIMD3<Float>(
            0.08 * sin(phase * 1.3),
            1,
            0.07 * cos(phase * 0.9)
        )

        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var indices = [UInt32]()

        func appendTriangle(
            _ first: SIMD3<Float>,
            _ second: SIMD3<Float>,
            _ third: SIMD3<Float>,
            expectedNormal: SIMD3<Float>
        ) {
            var b = second
            var c = third
            var normal = simd_normalize(simd_cross(b - first, c - first))
            if simd_dot(normal, expectedNormal) < 0 {
                swap(&b, &c)
                normal = simd_normalize(simd_cross(b - first, c - first))
            }
            let start = UInt32(positions.count)
            positions.append(contentsOf: [first, b, c])
            normals.append(contentsOf: [normal, normal, normal])
            indices.append(contentsOf: [start, start + 1, start + 2])
        }

        for side in 0..<sideCount {
            let next = (side + 1) % sideCount
            let radial = simd_normalize(SIMD3<Float>(
                cos((Float(side) + 0.5) / Float(sideCount) * 2 * .pi),
                0,
                sin((Float(side) + 0.5) / Float(sideCount) * 2 * .pi)
            ))
            appendTriangle(base[side], shoulder[next], base[next], expectedNormal: radial)
            appendTriangle(base[side], shoulder[side], shoulder[next], expectedNormal: radial)
            appendTriangle(shoulder[side], crown[next], shoulder[next], expectedNormal: radial)
            appendTriangle(shoulder[side], crown[side], crown[next], expectedNormal: radial)
            appendTriangle(crown[side], summit, crown[next], expectedNormal: SIMD3(0, 1, 0))
        }

        return LMLunarRockMeshData(
            positions: positions,
            normals: normals,
            indices: indices
        )
    }
}

public enum LMLunarRockFieldResource {
    @MainActor
    public static func makeEntity(
        heightField: Apollo11TerrainHeightField,
        eagleTerrainPosition: LMVector3D,
        model: LMLunarRockFieldModel = LMLunarRockFieldModel()
    ) throws -> Entity {
        let root = Entity()
        root.name = "Apollo 11 synthesized rock field \(LMLunarRockFieldModel.modelID)"

        let meshes = try (0..<LMLunarRockFieldModel.archetypeCount).map { archetype in
            let data = LMLunarRockMeshBuilder.makeArchetype(archetype)
            var descriptor = MeshDescriptor(name: "Apollo 11 rock archetype \(archetype)")
            descriptor.positions = MeshBuffers.Positions(data.positions)
            descriptor.normals = MeshBuffers.Normals(data.normals)
            descriptor.primitives = .triangles(data.indices)
            return try MeshResource.generate(from: [descriptor])
        }
        let materials = (0..<LMLunarRockFieldModel.reflectanceBucketCount).map { bucket in
            let value = 0.25 + CGFloat(bucket) * 0.025
            return SimpleMaterial(
                color: UIColor(red: value, green: value, blue: value * 0.96, alpha: 1),
                roughness: 0.97,
                isMetallic: false
            )
        }

        for (index, fragment) in model.fragments(relativeTo: eagleTerrainPosition).enumerated() {
            guard let elevation = heightField.relativeElevation(
                eastMeters: fragment.eastMeters,
                northMeters: fragment.northMeters
            ) else { continue }
            let rock = ModelEntity(
                mesh: meshes[fragment.archetype],
                materials: [materials[fragment.reflectanceBucket]]
            )
            rock.name = "Synthesized \(fragment.region.rawValue) rock \(index)"
            rock.position = SIMD3(
                Float(fragment.northMeters),
                elevation - fragment.dimensionsMeters.y * fragment.burialFraction,
                Float(-fragment.eastMeters)
            )
            rock.scale = fragment.dimensionsMeters
            let yaw = simd_quatf(angle: fragment.yawRadians, axis: SIMD3(0, 1, 0))
            let tiltAxis = SIMD3<Float>(
                cos(fragment.tiltAzimuthRadians),
                0,
                sin(fragment.tiltAzimuthRadians)
            )
            rock.orientation = yaw * simd_quatf(
                angle: fragment.tiltRadians,
                axis: tiltAxis
            )
            rock.components.set(DynamicLightShadowComponent(castsShadow: true))
            root.addChild(rock)
        }
        return root
    }
}
