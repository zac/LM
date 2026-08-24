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
    let cropWidthPixels: Int
    let cropHeightPixels: Int
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

struct Apollo11TerrainHeightField: Equatable, Sendable {
    let manifest: Apollo11TerrainManifest
    let heights: [Float]

    func relativeElevation(eastMeters: Double, northMeters: Double) -> Float? {
        let spacing = manifest.meshSpacingMeters
        let column = eastMeters / spacing + Double(manifest.meshWidth - 1) / 2
        let row = -northMeters / spacing + Double(manifest.meshHeight - 1) / 2
        guard column >= 0, row >= 0,
              column <= Double(manifest.meshWidth - 1),
              row <= Double(manifest.meshHeight - 1) else {
            return nil
        }

        let x0 = Int(column.rounded(.down))
        let y0 = Int(row.rounded(.down))
        let x1 = min(x0 + 1, manifest.meshWidth - 1)
        let y1 = min(y0 + 1, manifest.meshHeight - 1)
        let tx = Float(column - Double(x0))
        let ty = Float(row - Double(y0))
        func value(_ x: Int, _ y: Int) -> Float {
            heights[y * manifest.meshWidth + x]
        }
        let north = value(x0, y0) + (value(x1, y0) - value(x0, y0)) * tx
        let south = value(x0, y1) + (value(x1, y1) - value(x0, y1)) * tx
        return north + (south - north) * ty
    }
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
        guard manifest.schemaVersion == 2 else {
            throw ResourceError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.meshWidth >= 2,
              manifest.meshHeight >= 2,
              manifest.meshSpacingMeters > 0 else {
            throw ResourceError.invalidDimensions
        }
        return manifest
    }

    nonisolated static func loadHeightField(
        bundle: Bundle = .main
    ) throws -> Apollo11TerrainHeightField {
        let manifest = try loadManifest(bundle: bundle)
        return Apollo11TerrainHeightField(
            manifest: manifest,
            heights: try loadHeights(manifest: manifest, bundle: bundle)
        )
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
    static func makeEntity(
        heightField: Apollo11TerrainHeightField,
        bundle: Bundle = .main
    ) async throws -> Entity {
        let manifest = heightField.manifest
        let heights = heightField.heights
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

        let root = Entity()
        root.name = "Apollo 11 terrain environment"

        var farFieldMaterial = UnlitMaterial()
        farFieldMaterial.color = .init(tint: UIColor(white: 0.18, alpha: 1))
        let farField = ModelEntity(
            mesh: .generatePlane(width: 20_000, depth: 20_000),
            materials: [farFieldMaterial]
        )
        farField.name = "Lunar far field"
        farField.position.y = manifest.minimumRelativeElevationMeters - 4
        root.addChild(farField)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "LROC Apollo 11 landing-site terrain"
        root.addChild(entity)

        return root
    }

    @MainActor
    static func makeProgressiveTileEntity(
        heightField: Apollo11TerrainHeightField,
        plan: LMTerrainTilePlan,
        bundle: Bundle = .main
    ) async throws -> ModelEntity? {
        let tileSize = plan.sizeMeters
        let sampleSpacing = plan.sampleSpacingMeters
        let sampleCount = Int(tileSize / sampleSpacing) + 1
        let sampler = LMProgressiveTerrainSampler(heightField: heightField)
        let halfSize = tileSize / 2

        var positions = [SIMD3<Float>]()
        var textureCoordinates = [SIMD2<Float>]()
        positions.reserveCapacity(sampleCount * sampleCount)
        textureCoordinates.reserveCapacity(sampleCount * sampleCount)

        let manifest = heightField.manifest
        let measuredHalfWidth = Double(manifest.meshWidth - 1) * manifest.meshSpacingMeters / 2
        let measuredHalfDepth = Double(manifest.meshHeight - 1) * manifest.meshSpacingMeters / 2
        let layerOffset = layerOffsetMeters(
            sourceSpacingMeters: manifest.meshSpacingMeters,
            requestedSpacingMeters: sampleSpacing
        )
        for row in 0..<sampleCount {
            let north = plan.centerNorthMeters + halfSize - Double(row) * sampleSpacing
            for column in 0..<sampleCount {
                let east = plan.centerEastMeters - halfSize + Double(column) * sampleSpacing
                guard let sample = sampler.sample(
                    eastMeters: east,
                    northMeters: north,
                    requestedSpacingMeters: sampleSpacing
                ) else {
                    return nil
                }
                positions.append(SIMD3(
                    Float(east),
                    sample.elevationMeters + layerOffset,
                    Float(-north)
                ))
                textureCoordinates.append(SIMD2(
                    Float((east + measuredHalfWidth) / (measuredHalfWidth * 2)),
                    Float((north + measuredHalfDepth) / (measuredHalfDepth * 2))
                ))
            }
        }

        var normals = [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: positions.count)
        for row in 0..<sampleCount {
            for column in 0..<sampleCount {
                let leftColumn = max(column - 1, 0)
                let rightColumn = min(column + 1, sampleCount - 1)
                let northRow = max(row - 1, 0)
                let southRow = min(row + 1, sampleCount - 1)
                let left = positions[row * sampleCount + leftColumn]
                let right = positions[row * sampleCount + rightColumn]
                let north = positions[northRow * sampleCount + column]
                let south = positions[southRow * sampleCount + column]
                normals[row * sampleCount + column] = simd_normalize(
                    simd_cross(south - north, right - left)
                )
            }
        }

        var indices = [UInt32]()
        indices.reserveCapacity((sampleCount - 1) * (sampleCount - 1) * 6)
        for row in 0..<(sampleCount - 1) {
            for column in 0..<(sampleCount - 1) {
                let northwest = UInt32(row * sampleCount + column)
                let northeast = northwest + 1
                let southwest = UInt32((row + 1) * sampleCount + column)
                let southeast = southwest + 1
                indices.append(contentsOf: [
                    northwest, southwest, northeast,
                    northeast, southwest, southeast,
                ])
            }
        }

        var descriptor = MeshDescriptor(name: "Progressive LROC tile")
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
        entity.name = "LROC progressive L\(plan.id.level) E\(plan.id.eastIndex) N\(plan.id.northIndex) \(sampleSpacing)m"
        return entity
    }

    private static func layerOffsetMeters(
        sourceSpacingMeters: Double,
        requestedSpacingMeters: Double
    ) -> Float {
        Float(max(log2(sourceSpacingMeters / requestedSpacingMeters), 1) * 0.004)
    }
}
