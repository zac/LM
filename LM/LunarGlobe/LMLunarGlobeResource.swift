import CoreGraphics
import Foundation
import RealityKit
import simd
import UIKit

/// Builds the map-scale Moon from the same Mean Earth/Polar-axis coordinate
/// authority used by terrain sites. The WAC morphologic texture already
/// contains illumination, so this first globe tier is emissive/unlit and is
/// never shaded a second time by the Explorer's movable mission sun.
enum LMLunarGlobeResource {
    /// A low-frequency black overlay whose opacity is `1 - illumination`.
    /// Alpha compositing it over the unlit WAC map is therefore exactly a
    /// brightness multiplier; it cannot introduce a second lighting model.
    @MainActor
    struct TerminatorResource {
        let entity: ModelEntity
        let opacityTexture: TextureResource
        let surfaceNormals: [SIMD3<Double>]
    }

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

    @MainActor
    static func makeTerminator(
        manifest: LMTerrainManifest,
        date: Date,
        bundle: Bundle = .main
    ) throws -> TerminatorResource {
        let normalMap = manifest.globe.normalMap
        guard manifest.sources.contains(where: { $0.id == normalMap.sourceID }) else {
            throw ResourceError.missingSource(normalMap.sourceID)
        }
        let surfaceNormals = try globeNormalSamples(
            manifest: manifest,
            bundle: bundle,
            width: 512,
            height: 256
        )
        let image = try terminatorOpacityImage(
            date: date,
            surfaceNormals: surfaceNormals
        )
        let options = TextureResource.CreateOptions(
            semantic: .scalar,
            mipmapsMode: .allocateAndGenerateAll
        )
        let texture = try TextureResource.generate(
            from: image,
            withName: "Lunar ephemeris terminator",
            options: options
        )
        let mesh = try globeMesh(
            // Keep the transparent shell far enough above the color sphere to
            // avoid depth fighting after the Moon is scaled to tabletop size.
            radiusMeters: manifest.globe.radiusMeters * 1.0005,
            frontCoordinate: manifest.landingOriginCoordinate
        )
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .black)
        material.blending = .transparent(opacity: .init(
            scale: 1,
            texture: globeTexture(texture)
        ))
        material.writesDepth = false
        material.readsDepth = true

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "Ephemeris terminator multiplier"
        return TerminatorResource(
            entity: entity,
            opacityTexture: texture,
            surfaceNormals: surfaceNormals
        )
    }

    @MainActor
    static func updateTerminator(
        _ resource: TerminatorResource,
        date: Date
    ) throws {
        try resource.opacityTexture.replace(
            withImage: terminatorOpacityImage(
                date: date,
                surfaceNormals: resource.surfaceNormals
            ),
            options: TextureResource.CreateOptions(
                semantic: .scalar,
                mipmapsMode: .allocateAndGenerateAll
            )
        )
    }

    /// The map deliberately retains some context on the lunar night side.
    /// This is a cartographic day/night cue rather than photometric lighting:
    /// the WAC morphologic source already contains its own shaded relief.
    nonisolated static let terminatorNightMultiplier = 0.58

    /// A two-degree-wide smoothstep is wider than the physical solar limb but
    /// stable in a compact dynamic mask and still visually reads as a crisp
    /// terminator at whole-Moon scale.
    nonisolated static let terminatorDotHalfWidth = sin(Double.pi / 180)

    nonisolated static func terminatorMultiplier(
        surfaceNormal: SIMD3<Double>,
        subsolarDirection: SIMD3<Double>
    ) -> Double {
        let dot = simd_dot(
            simd_normalize(surfaceNormal),
            simd_normalize(subsolarDirection)
        )
        let t = min(max(
            (dot + terminatorDotHalfWidth) / (2 * terminatorDotHalfWidth),
            0
        ), 1)
        let smooth = t * t * (3 - 2 * t)
        return terminatorNightMultiplier
            + (1 - terminatorNightMultiplier) * smooth
    }

    nonisolated static func terminatorOpacitySamples(
        date: Date,
        width: Int = 512,
        height: Int = 256,
        surfaceNormals: [SIMD3<Double>]? = nil
    ) -> [UInt8] {
        precondition(width > 0 && height > 0)
        precondition(surfaceNormals == nil || surfaceNormals?.count == width * height)
        // Use the plan's explicit ephemeris authority, then convert through
        // the same ME coordinate system as the globe and landing sites.
        let subsolarPoint = LMLunarEphemeris.subsolarPoint(at: date)
        let system = LMSelenographicCoordinateSystem()
        let subsolarDirection = simd_normalize(
            system.moonCenteredPosition(for: subsolarPoint).vector
        )

        let longitudes = (0..<width).map { column -> (Double, Double) in
            let longitude = (-180
                + (Double(column) + 0.5) * 360 / Double(width)) * .pi / 180
            return (cos(longitude), sin(longitude))
        }
        var samples = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let latitude = (90
                - (Double(row) + 0.5) * 180 / Double(height)) * .pi / 180
            let cosLatitude = cos(latitude)
            let sinLatitude = sin(latitude)
            for column in 0..<width {
                let longitude = longitudes[column]
                let normal = surfaceNormals?[row * width + column] ?? SIMD3(
                    cosLatitude * longitude.0,
                    cosLatitude * longitude.1,
                    sinLatitude
                )
                let multiplier = terminatorMultiplier(
                    surfaceNormal: normal,
                    subsolarDirection: subsolarDirection
                )
                samples[row * width + column] = UInt8(
                    ((1 - multiplier) * 255).rounded()
                )
            }
        }
        return samples
    }

    private nonisolated static func terminatorOpacityImage(
        date: Date,
        width: Int = 512,
        height: Int = 256,
        surfaceNormals: [SIMD3<Double>]? = nil
    ) throws -> CGImage {
        let samples = terminatorOpacitySamples(
            date: date,
            width: width,
            height: height,
            surfaceNormals: surfaceNormals
        )
        guard let provider = CGDataProvider(data: Data(samples) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }

    /// Decodes the offline-generated ME normal field at the dynamic
    /// terminator mask's working resolution. The vectors are normalized after
    /// interpolation because RGB stores signed vector components, not color.
    nonisolated static func globeNormalSamples(
        manifest: LMTerrainManifest,
        bundle: Bundle,
        width: Int,
        height: Int
    ) throws -> [SIMD3<Double>] {
        precondition(width > 0 && height > 0)
        let map = manifest.globe.normalMap
        guard map.coordinateFrame == manifest.globe.coordinateSystemName,
              map.encoding == "linear RGB maps normalized ME x/y/z from [-1,1] to [0,1]"
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let url = try resourceURL(bundle: bundle, file: map.file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == map.width,
              image.height == map.height
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return stride(from: 0, to: pixels.count, by: 4).map { offset in
            let vector = SIMD3<Double>(
                Double(pixels[offset]) / 127.5 - 1,
                Double(pixels[offset + 1]) / 127.5 - 1,
                Double(pixels[offset + 2]) / 127.5 - 1
            )
            return simd_length_squared(vector) > 0.01
                ? simd_normalize(vector)
                : SIMD3(0, 0, 1)
        }
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
