import Foundation
import RealityKit
import UIKit
import simd

struct Apollo11TerrainManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let productID: String
    let sourceDTMURL: String
    let sourceHillshadeURL: String
    let sourceDTMSHA256: String
    let sourceHillshadeSHA256: String
    let sourceWidthPixels: Int
    let sourceHeightPixels: Int
    let sourcePostSpacingMeters: Double
    let sourceMinimumLatitudeDegrees: Double
    let sourceMaximumLatitudeDegrees: Double
    let sourceWesternLongitudeDegrees: Double
    let sourceEasternLongitudeDegrees: Double
    let landingLatitudeDegrees: Double
    let landingLongitudeDegrees: Double
    let landingPixelX: Int
    let landingPixelY: Int
    let cropOriginX: Int
    let cropOriginY: Int
    let cropSizePixels: Int
    let meshWidth: Int
    let meshHeight: Int
    let meshSampleStridePixels: Int
    let meshSpacingMeters: Double
    let landingElevationMeters: Float
    let minimumRelativeElevationMeters: Float
    let maximumRelativeElevationMeters: Float
    let heightEncoding: String
    let axisConvention: String
}

enum Apollo11TerrainResource {
    enum ResourceError: Error, Equatable {
        case missingResource(String)
        case unsupportedSchema(Int)
        case invalidDimensions
        case invalidHeightData(expectedBytes: Int, actualBytes: Int)
    }

    nonisolated static func loadManifest(
        bundle: Bundle = .main
    ) throws -> Apollo11TerrainManifest {
        guard let url = bundle.url(forResource: "Apollo11Terrain", withExtension: "json") else {
            throw ResourceError.missingResource("Apollo11Terrain.json")
        }
        let manifest = try JSONDecoder().decode(
            Apollo11TerrainManifest.self,
            from: Data(contentsOf: url)
        )
        guard manifest.schemaVersion == 1 else {
            throw ResourceError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.meshWidth >= 2,
              manifest.meshHeight >= 2,
              manifest.meshSpacingMeters > 0 else {
            throw ResourceError.invalidDimensions
        }
        return manifest
    }

    nonisolated static func loadHeights(
        manifest: Apollo11TerrainManifest,
        bundle: Bundle = .main
    ) throws -> [Float] {
        guard let url = bundle.url(
            forResource: "Apollo11TerrainHeightmap",
            withExtension: "bin"
        ) else {
            throw ResourceError.missingResource("Apollo11TerrainHeightmap.bin")
        }
        let data = try Data(contentsOf: url)
        let expectedBytes = manifest.meshWidth
            * manifest.meshHeight
            * MemoryLayout<Float>.size
        guard data.count == expectedBytes else {
            throw ResourceError.invalidHeightData(
                expectedBytes: expectedBytes,
                actualBytes: data.count
            )
        }

        return data.withUnsafeBytes { bytes in
            (0..<(manifest.meshWidth * manifest.meshHeight)).map { index in
                let bits = bytes.loadUnaligned(
                    fromByteOffset: index * MemoryLayout<UInt32>.size,
                    as: UInt32.self
                )
                return Float(bitPattern: UInt32(littleEndian: bits))
            }
        }
    }

    @MainActor
    static func makeEntity(bundle: Bundle = .main) async throws -> ModelEntity {
        let manifest = try loadManifest(bundle: bundle)
        let heights = try loadHeights(manifest: manifest, bundle: bundle)
        let width = manifest.meshWidth
        let height = manifest.meshHeight
        let spacing = Float(manifest.meshSpacingMeters)
        let halfWidth = Float(width - 1) * spacing / 2
        let halfDepth = Float(height - 1) * spacing / 2

        func heightAt(column: Int, row: Int) -> Float {
            heights[row * width + column]
        }

        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var textureCoordinates = [SIMD2<Float>]()
        positions.reserveCapacity(width * height)
        normals.reserveCapacity(width * height)
        textureCoordinates.reserveCapacity(width * height)

        for row in 0..<height {
            for column in 0..<width {
                let x = Float(column) * spacing - halfWidth
                let z = Float(row) * spacing - halfDepth
                positions.append(SIMD3(x, heightAt(column: column, row: row), z))

                let left = heightAt(column: max(column - 1, 0), row: row)
                let right = heightAt(column: min(column + 1, width - 1), row: row)
                let north = heightAt(column: column, row: max(row - 1, 0))
                let south = heightAt(column: column, row: min(row + 1, height - 1))
                let xSpan = Float(column == 0 || column == width - 1 ? 1 : 2) * spacing
                let zSpan = Float(row == 0 || row == height - 1 ? 1 : 2) * spacing
                let dhdx = (right - left) / xSpan
                let dhdz = (south - north) / zSpan
                normals.append(simd_normalize(SIMD3(-dhdx, 1, -dhdz)))

                textureCoordinates.append(SIMD2(
                    Float(column) / Float(width - 1),
                    1 - Float(row) / Float(height - 1)
                ))
            }
        }

        var indices = [UInt32]()
        indices.reserveCapacity((width - 1) * (height - 1) * 6)
        for row in 0..<(height - 1) {
            for column in 0..<(width - 1) {
                let northwest = UInt32(row * width + column)
                let northeast = northwest + 1
                let southwest = UInt32((row + 1) * width + column)
                let southeast = southwest + 1
                indices.append(contentsOf: [
                    northwest, southwest, northeast,
                    northeast, southwest, southeast
                ])
            }
        }

        var descriptor = MeshDescriptor(name: "LROC Apollo 11 terrain")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(textureCoordinates)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])

        let texture = try await TextureResource(
            named: "Apollo11TerrainHillshade",
            in: bundle
        )
        var material = UnlitMaterial()
        material.color = .init(
            tint: UIColor(white: 0.62, alpha: 1),
            texture: .init(texture)
        )

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "LROC Apollo 11 landing-site terrain"
        return entity
    }
}
