import Foundation
import RealityKit
import UIKit

/// Builds the map-scale Moon from the same Mean Earth/Polar-axis coordinate
/// authority used by terrain sites. The WAC morphologic texture already
/// contains illumination, so this first globe tier is emissive/unlit and is
/// never shaded a second time by the Explorer's movable mission sun.
enum LMLunarGlobeResource {
    enum ResourceError: LocalizedError {
        case missingTextureTier
        case missingSource(String)
        case inconsistentDatum

        var errorDescription: String? {
            switch self {
            case .missingTextureTier:
                "TerrainManifest.json does not declare a globe texture tier."
            case .missingSource(let id):
                "TerrainManifest.json does not declare globe source \(id)."
            case .inconsistentDatum:
                "The globe and terrain coordinate authorities use different lunar radii."
            }
        }
    }

    /// The initial global map does not need per-tile culling. This tessellation
    /// keeps its silhouette smooth in a tabletop view while remaining tiny
    /// compared with the 16.6-million-texel source texture.
    private static let latitudeSegments = 128
    private static let longitudeSegments = 256

    @MainActor
    static func makeEntity(
        manifest: LMTerrainManifest,
        bundle: Bundle = .main
    ) async throws -> ModelEntity {
        guard abs(manifest.globe.radiusMeters - manifest.projection.sphereRadiusMeters) < 0.001
        else {
            throw ResourceError.inconsistentDatum
        }
        guard let tier = manifest.globe.textureTiers.first else {
            throw ResourceError.missingTextureTier
        }
        guard manifest.sources.contains(where: { $0.id == tier.sourceID }) else {
            throw ResourceError.missingSource(tier.sourceID)
        }

        let textureURL = try resourceURL(bundle: bundle, file: tier.file)
        let texture = try await TextureResource(
            contentsOf: textureURL,
            options: LMTerrainWorld.terrainTextureCreateOptions(semantic: .color)
        )
        let mesh = try globeMesh(
            radiusMeters: manifest.globe.radiusMeters,
            frontCoordinate: manifest.landingOriginCoordinate
        )

        // Display the pinned morphologic product in its authored transfer
        // function. Tone mapping here crushed the maria and ray systems even
        // though no scene lighting was applied.
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(
            tint: .white,
            texture: globeTexture(texture)
        )

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "Pinned WAC global Moon"
        return entity
    }

    /// Converts a Moon-fixed coordinate into a globe-display basis centered on
    /// `frontCoordinate`: +x east, +y north, +z outward through the focus.
    /// Apollo 11 therefore appears at disk center without a hand-authored
    /// rotation, and every other point retains its exact ME relationship.
    nonisolated static func displayPosition(
        coordinate: LMSelenographicCoordinate,
        frontCoordinate: LMSelenographicCoordinate,
        radiusMeters: Double
    ) -> SIMD3<Float> {
        let system = LMSelenographicCoordinateSystem(datumRadiusMeters: radiusMeters)
        let frame = system.localFrame(at: frontCoordinate)
        let moonPosition = system.moonCenteredPosition(for: coordinate)
        let local = frame.localDirection(moonPosition.vector / radiusMeters)
        return SIMD3(
            Float(local.y * radiusMeters),
            Float(local.x * radiusMeters),
            Float(local.z * radiusMeters)
        )
    }

    /// Equirectangular texture address in the source product's ME frame.
    /// Keeping this transform testable prevents a visually plausible globe
    /// from silently drifting away from the landing-site coordinate authority.
    nonisolated static func textureCoordinate(
        for coordinate: LMSelenographicCoordinate
    ) -> SIMD2<Double> {
        SIMD2(
            (coordinate.longitudeDegrees + 180) / 360,
            (90 - coordinate.latitudeDegrees) / 180
        )
    }

    @MainActor
    private static func globeMesh(
        radiusMeters: Double,
        frontCoordinate: LMSelenographicCoordinate
    ) throws -> MeshResource {
        let rowLength = longitudeSegments + 1
        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var textureCoordinates = [SIMD2<Float>]()
        var indices = [UInt32]()
        positions.reserveCapacity((latitudeSegments + 1) * rowLength)
        normals.reserveCapacity((latitudeSegments + 1) * rowLength)
        textureCoordinates.reserveCapacity((latitudeSegments + 1) * rowLength)
        indices.reserveCapacity(latitudeSegments * longitudeSegments * 6)

        for row in 0...latitudeSegments {
            let v = Double(row) / Double(latitudeSegments)
            let latitudeDegrees = 90 - v * 180
            for column in 0...longitudeSegments {
                let u = Double(column) / Double(longitudeSegments)
                let longitudeDegrees = -180 + u * 360
                let position = displayPosition(
                    coordinate: LMSelenographicCoordinate(
                        latitudeDegrees: latitudeDegrees,
                        longitudeDegrees: longitudeDegrees
                    ),
                    frontCoordinate: frontCoordinate,
                    radiusMeters: radiusMeters
                )
                positions.append(position)
                normals.append(simd_normalize(position))
                // Preserve u == 1 on the duplicated +180-degree seam vertex.
                // LMSelenographicCoordinate canonically normalizes +180 to
                // -180; routing this mesh endpoint through that type would
                // turn the final narrow quad into an almost full-map UV span.
                textureCoordinates.append(SIMD2(Float(u), Float(v)))
            }
        }

        for row in 0..<latitudeSegments {
            for column in 0..<longitudeSegments {
                let upperLeft = UInt32(row * rowLength + column)
                let lowerLeft = UInt32((row + 1) * rowLength + column)
                let upperRight = upperLeft + 1
                let lowerRight = lowerLeft + 1
                indices.append(contentsOf: [
                    upperLeft, lowerLeft, upperRight,
                    upperRight, lowerLeft, lowerRight,
                ])
            }
        }

        var descriptor = MeshDescriptor(name: "IAU ME lunar globe")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(textureCoordinates)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    private static func resourceURL(bundle: Bundle, file: String) throws -> URL {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Terrain"
        ) ?? bundle.url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    private static func globeTexture(
        _ texture: TextureResource
    ) -> MaterialParameters.Texture {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.maxAnisotropy = 8
        // Longitude wraps continuously. Latitude clamps at the poles so the
        // first and last source rows cannot bleed across the opposite pole.
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .clampToEdge
        return MaterialParameters.Texture(
            texture,
            sampler: MaterialParameters.Texture.Sampler(descriptor)
        )
    }
}
