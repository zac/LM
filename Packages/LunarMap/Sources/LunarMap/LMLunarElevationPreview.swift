import Foundation
import RealityKit
import UIKit
import simd

/// The first streamed-elevation consumer. This is an explicit capture diagnostic:
/// a constant-reflectance, measured-only patch. It exercises source resolution,
/// decoding, curved geometry, and persistent offline reuse before amplification
/// and normal Explorer navigation adopt the resolver in the following items.
@MainActor
package enum LMLunarElevationPreview {
    static let generatorVersion = "measured-spherical-elevation-preview-v1"

    package struct Assembly {
        package let root: Entity
        package let sun: DirectionalLight
        package let frame: LMSelenographicLocalFrame
        package let sourceID: String
        package let sourceSpacingMeters: Double
        package let loadMilliseconds: Int
        package let fallbackReason: String?
    }

    struct MeshData: Sendable {
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let indices: [UInt32]
        let frame: LMSelenographicLocalFrame
    }

    enum PreviewError: Error {
        case missingBase
        case outsideCoverage
    }

    private static var persistentStore: LMLunarElevationStore?

    package static func load(coordinate: LMSelenographicCoordinate, offline: Bool,
                     manifest: LMTerrainManifest, bundle: Bundle = LunarMap.resources) async throws -> Assembly {
        let start = ContinuousClock.now
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LunarElevation-v1", isDirectory: true)
        if persistentStore == nil {
            persistentStore = try LMLunarElevationStore(directory: directory)
        }
        guard let store = persistentStore else { throw PreviewError.missingBase }
        let base = manifest.sources.first { $0.id == "lola-ldem-16ppd-global" }
        guard let base, let baseFile = base.bundledFile,
              let baseURL = bundle.url(forResource: baseFile, withExtension: nil, subdirectory: "Terrain") ?? bundle.url(forResource: baseFile, withExtension: nil),
              let labelFile = base.bundledLabelFile,
              let labelURL = bundle.url(forResource: labelFile, withExtension: nil, subdirectory: "Terrain") ?? bundle.url(forResource: labelFile, withExtension: nil),
              let labelDigest = base.labelSHA256,
              LMLunarElevationGrid.digest(try Data(contentsOf: labelURL)) == labelDigest else {
            throw PreviewError.missingBase
        }
        var sourceID = base.id
        var spacing = base.postSpacingMeters ?? 1_895.2094015093
        var fallbackReason: String?
        var mesh: MeshData?
        if let source = manifest.sources.first(where: {
            $0.productId == "SLDEM2015_512_00N_30N_000_045_FLOAT"
                && $0.coverage.contains(latitudeDegrees: coordinate.latitudeDegrees,
                                       longitudeDegrees: coordinate.longitudeDegrees)
        }) {
            do {
                let data = try await store.data(for: source, offline: offline)
                mesh = try await Task.detached(priority: .userInitiated) {
                    let grid = try LMLunarElevationGrid(data: data, source: source)
                    return try makeMesh(grid: grid, coordinate: coordinate)
                }.value
                sourceID = source.id
                spacing = source.postSpacingMeters ?? spacing
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                fallbackReason = String(describing: error)
            }
        }
        if mesh == nil {
            mesh = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: baseURL, options: .mappedIfSafe)
                let grid = try LMLunarElevationGrid(data: data, source: base)
                return try makeMesh(grid: grid, coordinate: coordinate)
            }.value
        }
        guard let mesh else { throw PreviewError.outsideCoverage }
        var descriptor = MeshDescriptor(name: generatorVersion)
        descriptor.positions = MeshBuffers.Positions(mesh.positions)
        descriptor.normals = MeshBuffers.Normals(mesh.normals)
        descriptor.primitives = .triangles(mesh.indices)
        let resource = try MeshResource.generate(from: [descriptor])
        let material = SimpleMaterial(color: UIColor(white: 0.25, alpha: 1),
                                      roughness: 1, isMetallic: false)
        let entity = ModelEntity(mesh: resource, materials: [material])
        entity.name = "Measured elevation diagnostic: " + sourceID
        let root = Entity()
        root.addChild(entity)
        let sun = DirectionalLight()
        sun.light.intensity = LMTerrainWorld.missionSunIlluminanceLux
        sun.shadow = LMTerrainWorld.missionShadow(altitudeMeters: 2_000)
        root.addChild(sun)
        let elapsed = start.duration(to: .now).components
        return Assembly(root: root, sun: sun, frame: mesh.frame,
                        sourceID: sourceID, sourceSpacingMeters: spacing,
                        loadMilliseconds: Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000),
                        fallbackReason: fallbackReason)
    }

    nonisolated static func makeMesh(grid: LMLunarElevationGrid,
                                    coordinate: LMSelenographicCoordinate) throws -> MeshData {
        guard let centerHeight = grid.elevation(at: coordinate) else { throw PreviewError.outsideCoverage }
        let system = LMSelenographicCoordinateSystem()
        let frame = system.localFrame(at: .init(latitudeDegrees: coordinate.latitudeDegrees,
                                               longitudeDegrees: coordinate.longitudeDegrees,
                                               heightMeters: centerHeight))
        let posts = 129
        let step = 128.0
        var positions = [SIMD3<Float>]()
        positions.reserveCapacity(posts * posts)
        for row in 0..<posts {
            try Task.checkCancellation()
            for column in 0..<posts {
                // Use the exact tangent frame to pick a ray, then put its
                // measured radius back onto the sphere. Never flatten sag.
                let offset = LMSiteENUPosition(northMeters: Double(64 - row) * step,
                                               eastMeters: Double(column - 64) * step,
                                               upMeters: 0)
                let ray = frame.coordinate(for: offset)
                guard let height = grid.elevation(at: ray) else { throw PreviewError.outsideCoverage }
                let local = frame.position(for: LMSelenographicCoordinate(
                    latitudeDegrees: ray.latitudeDegrees, longitudeDegrees: ray.longitudeDegrees,
                    heightMeters: height))
                positions.append(SIMD3<Float>(LMLunarFrameTransform.renderVector(local.vector)))
            }
        }
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var indices = [UInt32]()
        for row in 0..<(posts - 1) {
            for column in 0..<(posts - 1) {
                let a = row * posts + column
                for tri in [(a, a + 1, a + posts), (a + 1, a + posts + 1, a + posts)] {
                    let normal = simd_cross(positions[tri.1] - positions[tri.0],
                                            positions[tri.2] - positions[tri.0])
                    normals[tri.0] += normal
                    normals[tri.1] += normal
                    normals[tri.2] += normal
                    indices.append(contentsOf: [UInt32(tri.0), UInt32(tri.1), UInt32(tri.2)])
                }
            }
        }
        normals = normals.map { simd_normalize($0) }
        return MeshData(positions: positions, normals: normals, indices: indices, frame: frame)
    }
}
