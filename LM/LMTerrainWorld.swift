import CoreGraphics
import Foundation
import LMCore
import Metal
import RealityKit
import simd

/// Full-immersion cockpit world mapping at 1:1 life scale.
///
/// The cockpit stays fixed around the user; the entire exterior world moves by
/// the inverse vehicle pose, so no artificial camera motion is ever applied.
/// Terrain entities live in world coordinates (+X north, +Y up, -Z east,
/// landing origin at the entity-space origin), and the world transform places
/// the ground directly below the user at the vehicle's altitude and heading.
struct LMFullDescentMapper: Equatable {
    /// Site-relative ENU position in RealityKit meters, 1:1 with LMCore.
    func position(from state: LMVehicleStateSnapshot) -> SIMD3<Float> {
        let si = state.positionMeters
        return SIMD3(Float(si.x), Float(si.z), Float(-si.y))
    }

    /// World-from-cockpit transform: inverse vehicle rotation about the
    /// vehicle position, so terrain below the LM stays below the user.
    func worldTransform(for state: LMVehicleStateSnapshot) -> Transform {
        let rotation = LMWorldMapper.attitudeOrientation(from: state.attitude)
        let inverse = rotation.inverse
        var transform = Transform()
        transform.scale = SIMD3<Float>(repeating: 1)
        transform.rotation = inverse
        transform.translation = inverse.act(-position(from: state))
        return transform
    }

    static func worldTransform(identityAt origin: SIMD3<Float> = .zero) -> Transform {
        var transform = Transform()
        transform.scale = SIMD3<Float>(repeating: 1)
        transform.rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        transform.translation = -origin
        return transform
    }

    /// Mission sun direction in RealityKit coordinates (pointing toward the
    /// sun), derived from the manifest's ENU azimuth/elevation.
    static func sunDirection(from manifest: LMTerrainManifest) -> SIMD3<Float> {
        LMWorldMapper.attitudeDirection(from: manifest.sunDirectionENU)
    }

    /// Orientation whose -Z axis points from the sun toward the scene, the
    /// direction a RealityKit DirectionalLight illuminates along.
    static func sunLightOrientation(from manifest: LMTerrainManifest) -> simd_quatf {
        simd_quatf(from: SIMD3(0, 0, -1), to: -sunDirection(from: manifest))
    }
}

/// Assembles the full-immersion exterior scene: nested near, medium, and far
/// terrain bands plus the mission sun.
@MainActor
enum LMTerrainWorld {
    /// Renderer-space exposure for the mission sun. RealityKit measures this
    /// in lux; 25,000 preserves the low-Sun relief without clipping the
    /// reflectance-calibrated terrain against a black immersive sky.
    nonisolated static let missionSunIlluminanceLux: Float = 25_000

    /// Keep the terminal-descent shadow map tightly fitted around the lander.
    /// A 120 m fixed projection made each shadow texel several times larger
    /// than necessary during the final tens of meters and blurred the LM shape.
    nonisolated static let missionShadowMinimumDistanceMeters: Float = 12
    nonisolated static let missionShadowMaximumDistanceMeters: Float = 45

    /// A restrained texture-derived exposure floor keeps shadowed regolith
    /// readable in an unlit immersive sky while the mission sun still supplies
    /// the dominant directional relief. This is deliberately below 1 so it
    /// cannot flatten the low-Sun topography into an unlit texture.
    nonisolated static let regolithExposureFloor: Float = 0.08

    struct Assembly {
        let worldRoot: Entity
        let sun: DirectionalLight
        let manifest: LMTerrainManifest
        let nearAlbedoTexture: TextureResource
    }

    enum WorldError: Error, Equatable {
        case missingTile(String)
    }

    nonisolated static let nearFieldTileID = "near-field"
    nonisolated static let mediumFieldTileID = "medium-field"
    nonisolated static let farFieldTileID = "far-field"

    static func load(bundle: Bundle = .main) async throws -> Assembly {
        let manifest = try LMTerrainManifest.load(bundle: bundle)

        let worldRoot = Entity()
        worldRoot.name = "TerrainWorld"

        let nearTile = try requireTile(manifest, id: nearFieldTileID)
        let mediumTile = try requireTile(manifest, id: mediumFieldTileID)
        let farTile = try requireTile(manifest, id: farFieldTileID)
        // Each power-of-two-plus-one grid shares its inner boundary exactly
        // with the next denser tile. Punch nested square holes at those grid
        // lines so the bands neither overlap nor leave a geometric gap.
        let bands = [
            (tile: nearTile, holeHalfExtent: 0.0),
            (tile: mediumTile, holeHalfExtent: nearTile.extentMeters / 2.0),
            (tile: farTile, holeHalfExtent: mediumTile.extentMeters / 2.0),
        ]
        var nearAlbedoTexture: TextureResource?

        for (tile, hole) in bands {
            let heightURL = try resourceURL(bundle: bundle, file: tile.heightFile)
            let albedoURL = try resourceURL(bundle: bundle, file: tile.albedoFile)
            let heightMap = try LMTerrainHeightMap.load(contentsOf: heightURL)
            let grid = try LMTerrainMeshBuilder.grid(
                tile: tile,
                heightMap: heightMap,
                holeHalfExtentMeters: hole
            )
            let mesh = try LMTerrainMeshBuilder.mesh(from: grid)
            let texture = try await TextureResource(
                contentsOf: albedoURL,
                options: terrainTextureCreateOptions(semantic: .color)
            )
            if tile.id == nearFieldTileID {
                nearAlbedoTexture = texture
            }
            let material = terrainMaterial(texture: texture)
            let model = ModelEntity(mesh: mesh, materials: [material])
            model.name = "Terrain-\(tile.id)"
            worldRoot.addChild(model)
        }

        let sun = DirectionalLight()
        sun.name = "MissionSun"
        sun.light.intensity = missionSunIlluminanceLux
        sun.shadow = missionShadow(altitudeMeters: nil)
        sun.orientation = LMFullDescentMapper.sunLightOrientation(from: manifest)
        worldRoot.addChild(sun)

        guard let nearAlbedoTexture else {
            throw WorldError.missingTile(nearFieldTileID)
        }
        return Assembly(
            worldRoot: worldRoot,
            sun: sun,
            manifest: manifest,
            nearAlbedoTexture: nearAlbedoTexture
        )
    }

    /// Material for a fine clipmap tile that has baked its own appearance.
    ///
    /// The tile carries a resampled slice of the measured reflectance and a
    /// tangent-space normal map for the sub-triangle regolith, both addressed
    /// by tile-local UVs. RealityKit's PBR materials expose a single texture
    /// coordinate buffer, so baking per tile is what makes a normal map
    /// possible at all without giving up the measured albedo underneath it.
    static func detailTerrainMaterial(
        _ detail: LMTerrainTileDetailTextures
    ) throws -> PhysicallyBasedMaterial {
        guard let albedoImage = LMTerrainTileDetailBaker.image(
            from: detail.albedo,
            resolution: detail.resolution,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ), let normalImage = LMTerrainTileDetailBaker.image(
            from: detail.normal,
            resolution: detail.resolution,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ) else {
            throw WorldError.missingTile("tile detail textures")
        }
        let albedo = try TextureResource.generate(
            from: albedoImage,
            options: terrainTextureCreateOptions(semantic: .color)
        )
        let normal = try TextureResource.generate(
            from: normalImage,
            options: terrainTextureCreateOptions(semantic: .normal)
        )
        var material = terrainMaterial(texture: albedo)
        material.normal = .init(texture: terrainTexture(normal))
        return material
    }

    static func terrainMaterial(texture: TextureResource) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let reflectance = terrainTexture(texture)
        material.baseColor = .init(tint: .white, texture: reflectance)
        material.roughness = .init(floatLiteral: 0.96)
        material.metallic = .init(floatLiteral: 0)
        // RealityKit multiplies the emissive texture by this color. Be
        // explicit: the initializer's black default would erase the texture.
        material.emissiveColor = .init(color: .white, texture: reflectance)
        material.emissiveIntensity = regolithExposureFloor
        return material
    }

    /// Terrain is commonly viewed at a grazing angle with radically different
    /// texel densities in adjacent measured bands. Make the sampling contract
    /// explicit so the dense NAC texture minifies through a full mip chain and
    /// blends smoothly toward the WAC parent instead of reading as a sharp
    /// rectangular card at regional scale.
    static func terrainTextureCreateOptions(
        semantic: TextureResource.Semantic
    ) -> TextureResource.CreateOptions {
        TextureResource.CreateOptions(
            semantic: semantic,
            mipmapsMode: .allocateAndGenerateAll
        )
    }

    static func terrainTexture(
        _ texture: TextureResource
    ) -> MaterialParameters.Texture {
        MaterialParameters.Texture(texture, sampler: terrainTextureSampler())
    }

    static func terrainTextureSampler() -> MaterialParameters.Texture.Sampler {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.maxAnisotropy = 8
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return MaterialParameters.Texture.Sampler(descriptor)
    }

    nonisolated static func missionShadowDistance(altitudeMeters: Double?) -> Float {
        guard let altitudeMeters else { return missionShadowMaximumDistanceMeters }
        let fitted = Float(max(0, altitudeMeters)) * 1.35 + 8
        return min(
            missionShadowMaximumDistanceMeters,
            max(missionShadowMinimumDistanceMeters, fitted)
        )
    }

    nonisolated static func missionShadow(
        altitudeMeters: Double?
    ) -> DirectionalLightComponent.Shadow {
        DirectionalLightComponent.Shadow(
            shadowProjection: .automatic(
                maximumDistance: missionShadowDistance(altitudeMeters: altitudeMeters)
            ),
            depthBias: 1
        )
    }

    static func worldTransform(for state: LMVehicleStateSnapshot?) -> Transform {
        guard let state else {
            return LMFullDescentMapper.worldTransform()
        }
        return LMFullDescentMapper().worldTransform(for: state)
    }

    private static func requireTile(
        _ manifest: LMTerrainManifest,
        id: String
    ) throws -> LMTerrainManifest.Tile {
        guard let tile = manifest.tile(id: id) else {
            throw WorldError.missingTile(id)
        }
        return tile
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
}
